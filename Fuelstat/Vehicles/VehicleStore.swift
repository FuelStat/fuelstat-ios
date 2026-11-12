import Foundation
import FuelstatCore
import Observation
import UIKit

/// The signed-in user's vehicles and their key figures, shared by the list and the detail pages.
@MainActor
@Observable
final class VehicleStore {
    private(set) var vehicles: [RemoteVehicle] = []
    private(set) var stats: [String: VehicleStats] = [:]
    private(set) var hasLoaded = false
    /// Error of the last load; the list keeps showing the previous vehicles.
    private(set) var loadError: String?

    private let auth: AuthSession

    init(auth: AuthSession) {
        self.auth = auth
    }

    var api: APIClient { auth.api }

    func load() async {
        do {
            vehicles = sorted(try await auth.call { try await $0.vehicles(token: $1) })
            loadError = nil
            hasLoaded = true
            await loadStats()
            // Vehicles may have been renamed, added or removed; reloading in the foreground costs no widget budget.
            WidgetRefresh.reload()
        } catch is CancellationError {
            return
        } catch {
            loadError = error.localizedDescription
            hasLoaded = true
        }
    }

    /// Key figures for all vehicles, loaded in parallel. Failures keep the previous figures.
    private func loadStats() async {
        let ids = vehicles.map(\.id)
        let auth = auth
        let results = await withTaskGroup(of: (String, VehicleStats?).self) { group in
            for id in ids {
                group.addTask {
                    (id, try? await auth.call { try await $0.stats(vehicleID: id, token: $1) })
                }
            }
            var results: [(String, VehicleStats?)] = []
            for await result in group { results.append(result) }
            return results
        }
        for case let (id, value?) in results { stats[id] = value }
    }

    func reload(_ id: String) async throws -> RemoteVehicle {
        async let vehicle = auth.call { try await $0.vehicle(id: id, token: $1) }
        async let figures = try? auth.call { try await $0.stats(vehicleID: id, token: $1) }
        let loaded = try await vehicle
        replace(loaded)
        if let value = await figures { stats[id] = value }
        return loaded
    }

    func vehicle(_ id: String) -> RemoteVehicle? {
        vehicles.first { $0.id == id }
    }

    /// The vehicle chosen in the switcher, falling back to the one of the last fill-up.
    func resolvedSelection(_ id: String?) -> String? {
        if let id, vehicle(id) != nil { return id }
        return lastUsedVehicleID
    }

    /// Current odometer: the latest reading from the fill-ups, otherwise the value entered for the vehicle.
    func currentOdometer(of vehicle: RemoteVehicle) -> Double? {
        stats[vehicle.id]?.currentOdometerKm ?? vehicle.odometerKm
    }

    func imageURL(of vehicle: RemoteVehicle) -> URL? {
        api.resolve(vehicle.imageURL)
    }

    @discardableResult
    func create(_ input: VehicleInput) async throws -> RemoteVehicle {
        let vehicle = try await auth.call { try await $0.createVehicle(input, token: $1) }
        vehicles = sorted(vehicles + [vehicle])
        return vehicle
    }

    @discardableResult
    func update(_ id: String, _ input: VehicleInput) async throws -> RemoteVehicle {
        let vehicle = try await auth.call { try await $0.updateVehicle(id: id, input, token: $1) }
        replace(vehicle)
        return vehicle
    }

    func delete(_ id: String) async throws {
        try await auth.call { try await $0.deleteVehicle(id: id, token: $1) }
        vehicles.removeAll { $0.id == id }
        stats[id] = nil
    }

    /// Uploads a photo and makes it the vehicle's picture.
    func setPhoto(_ image: UIImage, for id: String) async throws {
        guard let jpeg = Self.jpeg(from: image) else { throw APIError.server(code: "invalid_image", status: 0) }
        let media = try await auth.call { try await $0.uploadVehicleImage(vehicleID: id, jpeg: jpeg, token: $1) }
        let vehicle = try await auth.call { try await $0.setVehicleImage(id: id, imageURL: media.url, token: $1) }
        if let url = api.resolve(vehicle.imageURL) {
            await ImageCache.shared.store(image, data: jpeg, for: url)
        }
        replace(vehicle)
    }

    func removePhoto(of id: String) async throws {
        let vehicle = try await auth.call { try await $0.setVehicleImage(id: id, imageURL: nil, token: $1) }
        replace(vehicle)
    }

    func fillups(of id: String, limit: Int) async throws -> [RemoteFillup] {
        try await auth.call { try await $0.fillups(vehicleID: id, limit: limit, token: $1) }
    }

    func fillups(of id: String, page: Int, perPage: Int) async throws -> Page<RemoteFillup> {
        try await auth.call { try await $0.fillups(vehicleID: id, page: page, perPage: perPage, token: $1) }
    }

    /// Deletes a fill-up and refreshes the vehicle's key figures.
    func deleteFillup(_ fillupID: String, of vehicleID: String) async throws {
        try await auth.call { try await $0.deleteFillup(id: fillupID, token: $1) }
        if let figures = try? await auth.call({ try await $0.stats(vehicleID: vehicleID, token: $1) }) {
            stats[vehicleID] = figures
        }
    }

    /// Due dates, most urgent first: overdue, soon, then by days left.
    func reminders(of id: String) async throws -> [RemoteReminder] {
        RemoteReminder.byUrgency(try await auth.call { try await $0.reminders(vehicleID: id, token: $1) })
    }

    /// Saves a fill-up and refreshes the vehicle's key figures. Returns the API's odometer warnings.
    func addFillup(_ input: FillupInput) async throws -> [String] {
        let created = try await auth.call { try await $0.createFillup(input, token: $1) }
        WidgetRefresh.reload()
        UserDefaults.standard.set(input.vehicleId, forKey: Self.lastVehicleKey)
        if let figures = try? await auth.call({ try await $0.stats(vehicleID: input.vehicleId, token: $1) }) {
            stats[input.vehicleId] = figures
        }
        return created.warnings.compactMap(\.message)
    }

    /// Price per unit of the latest fill-up with this unit, as a default for the next one.
    func lastPrice(of id: String, unit: String) async -> Double? {
        guard let recent = try? await fillups(of: id, limit: 10) else { return nil }
        return recent.first { $0.unit == unit && $0.amount > 0 }.flatMap { fillup in
            fillup.totalCostEur.map { $0 / fillup.amount }
        }
    }

    func stations(near latitude: Double, _ longitude: Double, type: String) async throws -> [RemoteStation] {
        try await auth.call {
            try await $0.stations(latitude: latitude, longitude: longitude, radiusKm: 5, type: type, token: $1)
        }
    }

    /// The vehicle used for the last fill-up, as default for the next one.
    var lastUsedVehicleID: String? {
        let id = Self.storedLastVehicleID
        return vehicles.contains { $0.id == id } ? id : vehicles.first?.id
    }

    private nonisolated static let lastVehicleKey = "fillup.lastVehicleID"

    /// The vehicle of the last fill-up saved in the app, also used by Siri and Shortcuts.
    nonisolated static var storedLastVehicleID: String? {
        get { UserDefaults.standard.string(forKey: lastVehicleKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastVehicleKey) }
    }

    private func replace(_ vehicle: RemoteVehicle) {
        if let index = vehicles.firstIndex(where: { $0.id == vehicle.id }) {
            vehicles[index] = vehicle
        } else {
            vehicles.append(vehicle)
        }
        vehicles = sorted(vehicles)
    }

    private func sorted(_ list: [RemoteVehicle]) -> [RemoteVehicle] {
        list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The server shrinks photos to 1600 px anyway; doing it here keeps uploads small on mobile data.
    static func jpeg(from image: UIImage, maxEdge: CGFloat = 1600) -> Data? {
        let size = image.size
        let scale = min(1, maxEdge / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
}

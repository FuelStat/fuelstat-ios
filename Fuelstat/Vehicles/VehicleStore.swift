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
        let previous = vehicle(id)?.imageURL
        let media = try await auth.call { try await $0.uploadVehicleImage(vehicleID: id, jpeg: jpeg, token: $1) }
        let vehicle = try await auth.call { try await $0.setVehicleImage(id: id, imageURL: media.url, token: $1) }
        await deleteOldPhoto(previous, of: id)
        if let url = api.resolve(vehicle.imageURL) {
            await ImageCache.shared.store(image, data: jpeg, for: url)
        }
        replace(vehicle)
    }

    func removePhoto(of id: String) async throws {
        let previous = vehicle(id)?.imageURL
        let vehicle = try await auth.call { try await $0.setVehicleImage(id: id, imageURL: nil, token: $1) }
        replace(vehicle)
        await deleteOldPhoto(previous, of: id)
    }

    /// Deletes the photo that was replaced or removed, file included, as the web app does. Without this the
    /// file stayed on the server and its signed address kept working until it expired. Failures are ignored:
    /// the vehicle no longer shows the photo either way.
    private func deleteOldPhoto(_ address: String?, of id: String) async {
        guard let name = RemoteMedia.fileName(of: address),
              let media = try? await auth.call({ try await $0.vehicleMedia(vehicleID: id, token: $1) }),
              let old = media.first(where: { $0.fileName == name }) else { return }
        _ = try? await auth.call { try await $0.deleteVehicleMedia(vehicleID: id, mediaID: old.id, token: $1) }
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
        let list = RemoteReminder.byUrgency(try await auth.call { try await $0.reminders(vehicleID: id, token: $1) })
        // Every load replans the local notifications of this vehicle, so they follow the API's dates.
        if let vehicle = vehicle(id) { await ReminderNotifications.schedule(list, for: vehicle) }
        return list
    }

    /// Due dates of all vehicles, most urgent first. Vehicles whose dates fail to load are left out.
    func allReminders() async -> [(vehicle: RemoteVehicle, reminder: RemoteReminder)] {
        var all: [(vehicle: RemoteVehicle, reminder: RemoteReminder)] = []
        for vehicle in vehicles {
            guard let list = try? await reminders(of: vehicle.id) else { continue }
            all += list.map { (vehicle, $0) }
        }
        // Stable sort by urgency across vehicles.
        return all.enumerated().sorted { lhs, rhs in
            let l = RemoteReminder.urgencyKey(lhs.element.reminder), r = RemoteReminder.urgencyKey(rhs.element.reminder)
            return l == r ? lhs.offset < rhs.offset : l < r
        }.map(\.element)
    }

    /// Saves a fill-up and refreshes the vehicle's key figures. Returns its id and the API's odometer warnings.
    func addFillup(_ input: FillupInput) async throws -> (id: String, warnings: [String]) {
        let created = try await auth.call { try await $0.createFillup(input, token: $1) }
        entryChanges += 1
        WidgetRefresh.reload()
        UserDefaults.standard.set(input.vehicleId, forKey: Self.lastVehicleKey)
        if let figures = try? await auth.call({ try await $0.stats(vehicleID: input.vehicleId, token: $1) }) {
            stats[input.vehicleId] = figures
        }
        return (created.id, created.warnings.compactMap(\.message))
    }

    // MARK: - Fuel types (FuelStat/fuelstat#140)

    /// Fuel types the server knows (`GET /fuels`), loaded once per session; nil on servers without them.
    private(set) var fuelCatalog: FuelCatalog?

    @discardableResult
    func loadFuelCatalog() async -> FuelCatalog? {
        if let fuelCatalog { return fuelCatalog }
        fuelCatalog = try? await api.fuels()
        return fuelCatalog
    }

    /// The vehicle's fuel types for fuelling or charging; empty when the server or the vehicle has none.
    func fuelOptions(of vehicle: RemoteVehicle, charging: Bool) -> [FuelOption] {
        guard let fuelCatalog else { return [] }
        return FuelChoice.options(vehicleFuels: vehicle.fuels, catalog: fuelCatalog.fuels, charging: charging)
    }

    /// Whether the vehicle can be fuelled and/or charged: from its fuel types, otherwise from the drive type.
    func entryModes(of vehicle: RemoteVehicle) -> (fuel: Bool, charge: Bool) {
        if let fuelCatalog {
            let modes = FuelChoice.modes(vehicleFuels: vehicle.fuels, catalog: fuelCatalog.fuels)
            if modes.fuel || modes.charge { return modes }
        }
        let units = vehicle.fuelType.fillupUnits
        return (units.contains { $0 != "kwh" }, units.contains("kwh"))
    }

    // MARK: - Entry list, expenses, trips

    /// Expense categories from the API, kept for the session; `reload` asks again (e.g. after changing them).
    private(set) var categories: CategoriesResponse?

    @discardableResult
    func loadCategories(reload: Bool = false) async throws -> CategoriesResponse {
        if let categories, !reload { return categories }
        let loaded = try await auth.call { try await $0.categories(token: $1) }
        categories = loaded
        return loaded
    }

    func timeline(of id: String, page: Int, perPage: Int, kinds: [TimelineItem.Kind], search: String?) async throws
        -> TimelinePage {
        try await auth.call {
            try await $0.timeline(vehicleID: id, page: page, perPage: perPage, kinds: kinds, search: search, token: $1)
        }
    }

    /// Counts saved, changed and deleted entries, so open screens know when to reload.
    private(set) var entryChanges = 0

    /// Runs a change to an entry, then refreshes the vehicle's key figures and the widgets.
    private func changingEntries<T>(of vehicleID: String, _ change: (APIClient, String) async throws -> T) async throws
        -> T {
        let result = try await auth.call(change)
        entryChanges += 1
        WidgetRefresh.reload()
        if let figures = try? await auth.call({ try await $0.stats(vehicleID: vehicleID, token: $1) }) {
            stats[vehicleID] = figures
        }
        return result
    }

    /// Deletes an entry of the list through the endpoint it belongs to.
    func delete(_ item: TimelineItem, of vehicleID: String) async throws {
        try await changingEntries(of: vehicleID) { api, token in
            switch item.source {
            case .fillup: try await api.deleteFillup(id: item.rawID, token: token)
            case .entry: try await api.deleteExpense(id: item.rawID, token: token)
            case .trip: try await api.deleteTrip(id: item.rawID, token: token)
            }
        }
    }

    /// Changes a fill-up. Returns the API's odometer warnings.
    func updateFillup(_ id: String, _ patch: FillupPatch, of vehicleID: String) async throws -> [String] {
        try await changingEntries(of: vehicleID) { try await $0.updateFillup(id: id, patch, token: $1) }.messages
    }

    func setFillupOdometer(_ id: String, km: Int, of vehicleID: String) async throws -> [String] {
        try await changingEntries(of: vehicleID) { try await $0.setFillupOdometer(id: id, km: km, token: $1) }.messages
    }

    func expense(_ id: String) async throws -> RemoteExpense {
        try await auth.call { try await $0.expense(id: id, token: $1) }
    }

    /// Saves a new expense (`id` nil) or changes one. Returns the API's odometer warnings.
    func saveExpense(_ input: ExpenseInput, id: String?) async throws -> [String] {
        try await changingEntries(of: input.vehicleId) { api, token in
            if let id {
                return try await api.updateExpense(id: id, input, token: token)
            } else {
                return try await api.createExpense(input, token: token)
            }
        }.messages
    }

    func trip(_ id: String) async throws -> RemoteTrip {
        try await auth.call { try await $0.trip(id: id, token: $1) }
    }

    /// Saves a new trip (`id` nil) or changes one. Returns the API's odometer warnings.
    func saveTrip(_ input: TripInput, id: String?) async throws -> [String] {
        try await changingEntries(of: input.vehicleId) { api, token in
            if let id {
                return try await api.updateTrip(id: id, input, token: token)
            } else {
                return try await api.createTrip(input, token: token)
            }
        }.messages
    }

    func deleteTrip(_ tripID: String, of vehicleID: String) async throws {
        try await changingEntries(of: vehicleID) { try await $0.deleteTrip(id: tripID, token: $1) }
    }

    func trips(of id: String, year: Int?, purpose: String?, page: Int) async throws -> TripsPage {
        try await auth.call {
            try await $0.trips(vehicleID: id, year: year, purpose: purpose, page: page, perPage: 50, token: $1)
        }
    }

    func tripSummary(of id: String, year: Int?) async throws -> TripSummary {
        try await auth.call { try await $0.tripSummary(vehicleID: id, year: year, token: $1) }
    }

    func tripsCSV(of id: String, year: Int?) async throws -> Data {
        try await auth.call { try await $0.tripsCSV(vehicleID: id, year: year, token: $1) }
    }

    // MARK: - Categories

    func saveCategory(_ input: CategoryInput, id: String?) async throws {
        try await auth.call { api, token in
            if let id {
                try await api.updateCategory(id: id, input, token: token)
            } else {
                try await api.createCategory(input, token: token)
            }
        }
        try await loadCategories(reload: true)
    }

    func deleteCategory(_ id: String, moveTo: String?) async throws {
        try await auth.call { try await $0.deleteCategory(id: id, moveTo: moveTo, token: $1) }
        try await loadCategories(reload: true)
    }

    // MARK: - Sharing

    func members(of id: String) async throws -> VehicleMembers {
        try await auth.call { try await $0.members(vehicleID: id, token: $1) }
    }

    func invite(to id: String, email: String, role: VehicleRole) async throws {
        try await auth.call { try await $0.invite(vehicleID: id, email: email, role: role.rawValue, token: $1) }
    }

    func revokeInvitation(_ invitationID: String, of id: String) async throws {
        try await auth.call { try await $0.revokeInvitation(vehicleID: id, invitationID: invitationID, token: $1) }
    }

    func setRole(_ role: VehicleRole, ofMember userID: String, in id: String) async throws {
        try await auth.call {
            try await $0.setMemberRole(vehicleID: id, userID: userID, role: role.rawValue, token: $1)
        }
    }

    func removeMember(_ userID: String, from id: String) async throws {
        try await auth.call { try await $0.removeMember(vehicleID: id, userID: userID, token: $1) }
    }

    /// Leaves a vehicle that was shared with the user; it disappears from the list.
    func leave(_ id: String) async throws {
        try await auth.call { try await $0.removeMember(vehicleID: id, userID: "me", token: $1) }
        vehicles.removeAll { $0.id == id }
        stats[id] = nil
    }

    func invitations() async throws -> [PendingInvitation] {
        try await auth.call { try await $0.invitations(token: $1) }
    }

    /// Accepts or declines an invitation and reloads the vehicles and the open-invitation count.
    func answer(_ invitation: PendingInvitation, accept: Bool) async throws {
        try await auth.call { try await $0.answerInvitation(id: invitation.id, accept: accept, token: $1) }
        await auth.refreshUser()
        if accept { await load() }
    }

    /// Price per unit of the latest fill-up with this unit, as a default for the next one.
    /// With a fuel type only fill-ups of that type count, so a petrol fill-up never gets the LPG price.
    func lastPrice(of id: String, unit: String, fuel: String? = nil) async -> Double? {
        guard let recent = try? await fillups(of: id, limit: 20) else { return nil }
        return recent.first { fillup in
            guard fillup.unit == unit, fillup.amount > 0 else { return false }
            guard let fuel, let other = fillup.fuel else { return true }
            return other == fuel
        }.flatMap { fillup in
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

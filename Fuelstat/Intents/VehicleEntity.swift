import AppIntents
import FuelstatCore
import Foundation

/// A vehicle as Siri, Shortcuts and Spotlight see it. Only name, plate and fuel type leave the app.
struct VehicleEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Fahrzeug", numericFormat: "\(placeholder: .int) Fahrzeuge")
    static var defaultQuery = VehicleQuery()

    let id: String

    @Property(title: "Name")
    var name: String

    @Property(title: "Kennzeichen")
    var licensePlate: String?

    @Property(title: "Antrieb")
    var fuelTypeName: String

    let fuelType: RemoteFuelType
    /// Fuel types of the vehicle (FuelStat/fuelstat#140), e.g. `["super_e5", "electricity"]`.
    let fuels: [String]
    let defaultFuel: String?

    init(_ vehicle: RemoteVehicle) {
        id = vehicle.id
        fuelType = vehicle.fuelType
        fuels = vehicle.fuels
        defaultFuel = vehicle.defaultFuel
        name = vehicle.name
        licensePlate = vehicle.licensePlate
        fuelTypeName = vehicle.fuelType.label
    }

    var displayRepresentation: DisplayRepresentation {
        let subtitle = [licensePlate, fuelTypeName].compactMap { $0 }.joined(separator: " · ")
        return DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(subtitle)",
            image: .init(systemName: fuelType == .electric ? "bolt.car" : "car.side")
        )
    }
}

/// Finds the user's vehicles via the API. Without a sign-in the lists stay empty.
struct VehicleQuery: EntityStringQuery {
    func entities(for identifiers: [VehicleEntity.ID]) async throws -> [VehicleEntity] {
        try await Self.all().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [VehicleEntity] {
        let text = string.trimmingCharacters(in: .whitespaces)
        return try await Self.all().filter { vehicle in
            [vehicle.name, vehicle.licensePlate, vehicle.fuelTypeName]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(text) }
        }
    }

    func suggestedEntities() async throws -> [VehicleEntity] {
        try await Self.all()
    }

    /// The vehicle Siri uses without asking: the only one, or the one last used in the app.
    func defaultResult() async -> VehicleEntity? {
        guard let vehicles = try? await Self.all() else { return nil }
        let choice = IntentVehicleChoice.resolve(
            explicit: nil, available: vehicles.map(\.id),
            remembered: [VehicleSelection.storedID, VehicleStore.storedLastVehicleID]
        )
        guard case .vehicle(let id) = choice else { return nil }
        return vehicles.first { $0.id == id }
    }

    static func all() async throws -> [VehicleEntity] {
        try await IntentAPI.call { try await $0.vehicles(token: $1) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map(VehicleEntity.init)
    }
}

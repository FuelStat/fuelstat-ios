import AppIntents
import Foundation
import WidgetKit

/// Vehicle choice in the widget's settings ("Widget bearbeiten").
struct WidgetVehicleEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Fahrzeug")
    static var defaultQuery = WidgetVehicleQuery()

    let id: String
    let name: String
    let licensePlate: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: licensePlate.map { "\($0)" })
    }
}

struct WidgetVehicleQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetVehicleEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetVehicleEntity] {
        guard KeychainStore.loadToken() != nil else { return [] }
        return try await SignedInAPI.call(.configured) { api, token in try await api.vehicles(token: token) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { WidgetVehicleEntity(id: $0.id, name: $0.name, licensePlate: $0.licensePlate) }
    }
}

struct SelectVehicleIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Fahrzeug wählen"
    static var description = IntentDescription("Welches Fahrzeug das Widget zeigt.")

    /// Empty: the first vehicle (alphabetically).
    @Parameter(title: "Fahrzeug")
    var vehicle: WidgetVehicleEntity?
}

/// What the widget shows. All figures come from the API (`/stats`, `/reminders`); nothing is calculated here.
struct VehicleSnapshot {
    struct Due {
        let title: String
        let days: Int?
        let dueKm: Double?
        let status: RemoteReminder.Status
    }

    let id: String
    let name: String
    let licensePlate: String?
    let fuelType: RemoteFuelType
    let averageConsumption: Double?
    let nextDue: Due?

    var consumptionUnit: String { "\(fuelType.tankCapacityUnit)/100 km" }
    var canFuel: Bool { fuelType.fillupUnits.contains { $0 != "kwh" } }
    var canCharge: Bool { fuelType.fillupUnits.contains("kwh") }

    static let preview = VehicleSnapshot(
        id: "preview", name: "VW Golf", licensePlate: "S-FS 123", fuelType: .e10, averageConsumption: 6.4,
        nextDue: Due(title: "TÜV", days: 12, dueKm: nil, status: .soon)
    )
}

struct VehicleWidgetEntry: TimelineEntry {
    enum State {
        case data(VehicleSnapshot)
        case signedOut
        case noVehicle
        case offline
    }

    let date: Date
    let state: State
}

struct VehicleProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> VehicleWidgetEntry {
        VehicleWidgetEntry(date: .now, state: .data(.preview))
    }

    func snapshot(for configuration: SelectVehicleIntent, in context: Context) async -> VehicleWidgetEntry {
        if context.isPreview { return placeholder(in: context) }
        return await load(configuration)
    }

    func timeline(for configuration: SelectVehicleIntent, in context: Context) async -> Timeline<VehicleWidgetEntry> {
        let entry = await load(configuration)
        // Data changes only with new entries (the app then reloads the widget) and once a day for due dates.
        let hours: Double = if case .offline = entry.state { 0.5 } else { 3 }
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(hours * 3600)))
    }

    private func load(_ configuration: SelectVehicleIntent) async -> VehicleWidgetEntry {
        await VehicleWidgetEntry.load(vehicleID: configuration.vehicle?.id)
    }
}

extension VehicleWidgetEntry {
    /// Loads a vehicle and its figures; without an id (or if it is gone) the first vehicle alphabetically.
    static func load(vehicleID: String?) async -> VehicleWidgetEntry {
        guard KeychainStore.loadToken() != nil else {
            return VehicleWidgetEntry(date: .now, state: .signedOut)
        }
        let api = APIClient.configured
        do {
            // Renews the device session if needed; the calls below then share the current token.
            let vehicles = try await SignedInAPI.call(api) { api, token in try await api.vehicles(token: token) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let token = try await TokenStore.shared.accessToken(api: api)
            let chosen = vehicleID.flatMap { id in vehicles.first { $0.id == id } }
            guard let vehicle = chosen ?? vehicles.first else {
                return VehicleWidgetEntry(date: .now, state: .noVehicle)
            }
            async let stats = try? api.stats(vehicleID: vehicle.id, token: token)
            async let reminders = try? api.reminders(vehicleID: vehicle.id, token: token)
            let next = await RemoteReminder.byUrgency(reminders ?? []).first
            let snapshot = VehicleSnapshot(
                id: vehicle.id, name: vehicle.name, licensePlate: vehicle.licensePlate, fuelType: vehicle.fuelType,
                averageConsumption: await stats?.averageConsumption,
                nextDue: next.map { .init(title: $0.title, days: $0.days, dueKm: $0.dueKm, status: $0.status) }
            )
            return VehicleWidgetEntry(date: .now, state: .data(snapshot))
        } catch APIError.unauthorized {
            return VehicleWidgetEntry(date: .now, state: .signedOut)
        } catch {
            return VehicleWidgetEntry(date: .now, state: .offline)
        }
    }
}

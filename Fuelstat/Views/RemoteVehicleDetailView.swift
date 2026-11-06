import SwiftUI

/// Basic master data of a vehicle from the Fuelstat API. No statistics.
struct RemoteVehicleDetailView: View {
    @Environment(AuthSession.self) private var auth
    @State private var vehicle: RemoteVehicle
    @State private var errorMessage: String?

    init(vehicle: RemoteVehicle) {
        _vehicle = State(initialValue: vehicle)
    }

    var body: some View {
        List {
            Section("Allgemein") {
                LabeledContent("Kraftstoff", value: vehicle.fuelType.label)
                row("Marke", vehicle.brand)
                row("Modell", vehicle.model)
                row("Baujahr", vehicle.year.map(String.init))
            }

            if hasRegistration {
                Section("Zulassung") {
                    row("Kennzeichen", vehicle.licensePlate)
                    row("FIN", vehicle.vin)
                    row("Erstzulassung", vehicle.firstRegistration.flatMap(Self.formatDate))
                }
            }

            if hasTechnical {
                Section("Technik") {
                    row("Kilometerstand", vehicle.odometerKm.map(Fmt.kilometres))
                    row(vehicle.fuelType.tankCapacityLabel,
                        vehicle.tankCapacity.map { "\(Fmt.number($0)) \(vehicle.fuelType.tankCapacityUnit)" })
                    row("Akkukapazität", vehicle.batteryCapacity.map { "\(Fmt.number($0)) kWh" })
                    row("Reifen Sommer", vehicle.tireSizeSummer)
                    row("Reifen Winter", vehicle.tireSizeWinter)
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(vehicle.name)
        .refreshable { await load() }
        .task { await load() }
    }

    private var hasRegistration: Bool {
        vehicle.licensePlate != nil || vehicle.vin != nil || vehicle.firstRegistration != nil
    }

    private var hasTechnical: Bool {
        vehicle.odometerKm != nil || vehicle.tankCapacity != nil || vehicle.batteryCapacity != nil
            || vehicle.tireSizeSummer != nil || vehicle.tireSizeWinter != nil
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String?) -> some View {
        if let value {
            LabeledContent(title, value: value)
        }
    }

    /// Reloads the vehicle so the page shows the current server state.
    private func load() async {
        guard let token = auth.token else { return }
        do {
            vehicle = try await auth.api.vehicle(id: vehicle.id, token: token)
            errorMessage = nil
        } catch APIError.unauthorized {
            auth.handleUnauthorized()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func formatDate(_ value: String) -> String? {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: value) else { return value }
        var style = Date.FormatStyle.dateTime.day().month().year()
        style.timeZone = TimeZone(identifier: "UTC")!
        return date.formatted(style)
    }
}

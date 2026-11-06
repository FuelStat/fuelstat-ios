import SwiftUI

/// Profil → Fahrzeuge: all vehicles of the account, add a new one, open a vehicle page.
struct VehicleManagementView: View {
    @Bindable var store: VehicleStore
    @State private var showingAddVehicle = false

    var body: some View {
        List {
            if let error = store.loadError, !store.vehicles.isEmpty {
                Label(error, systemImage: "wifi.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(store.vehicles) { vehicle in
                NavigationLink(value: Route.vehicle(vehicle.id)) {
                    VehicleRow(vehicle: vehicle, store: store)
                }
                .listRowBackground(Theme.card)
            }
        }
        .themedBackground()
        .navigationTitle("Fahrzeuge")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Fahrzeug hinzufügen", systemImage: "plus") { showingAddVehicle = true }
            }
        }
        .overlay {
            if store.vehicles.isEmpty {
                VehicleListPlaceholder(store: store)
            }
        }
        .refreshable { await store.load() }
        .sheet(isPresented: $showingAddVehicle) {
            RemoteVehicleFormView(store: store)
        }
    }
}

private struct VehicleRow: View {
    let vehicle: RemoteVehicle
    let store: VehicleStore

    @ScaledMetric(relativeTo: .headline) private var photoSize: CGFloat = 56

    private var odometer: String? { store.currentOdometer(of: vehicle).map(Fmt.kilometres) }

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            VehiclePhoto(url: store.imageURL(of: vehicle), fuelType: vehicle.fuelType)
                .frame(width: photoSize, height: photoSize)
                .clipShape(.tile)
            VStack(alignment: .leading, spacing: 2) {
                Text(vehicle.name).font(.headline)
                Text([vehicle.fuelType.label, vehicle.licensePlate].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let odometer {
                    Text(odometer)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xxs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [vehicle.name, vehicle.fuelType.label]
        if let plate = vehicle.licensePlate { parts.append(String(localized: "Kennzeichen \(plate)")) }
        if let odometer { parts.append(String(localized: "Kilometerstand \(odometer)")) }
        return parts.joined(separator: ", ")
    }
}

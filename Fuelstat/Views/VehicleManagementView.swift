import SwiftUI

/// Profil → Fahrzeuge: all vehicles of the account, add a new one, open a vehicle page.
struct VehicleManagementView: View {
    @Bindable var store: VehicleStore
    @State private var showingAddVehicle = false
    @State private var moveError: String?

    var body: some View {
        List {
            if let error = store.loadError, !store.allVehicles.isEmpty {
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
                .moveDisabled(vehicle.isShared)
            }
            .onMove { source, destination in
                Task {
                    do {
                        try await store.move(fromOffsets: source, toOffset: destination)
                    } catch {
                        moveError = error.localizedDescription
                    }
                }
            }
            if store.vehicles.filter({ !$0.isShared }).count > 1 {
                Text("Tippe auf „Sortieren“ und ziehe die Fahrzeuge in die gewünschte Reihenfolge. Geteilte Fahrzeuge stehen am Ende.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            if !store.archivedVehicles.isEmpty {
                Section {
                    ForEach(store.archivedVehicles) { vehicle in
                        NavigationLink(value: Route.vehicle(vehicle.id)) {
                            VehicleRow(vehicle: vehicle, store: store)
                        }
                        .listRowBackground(Theme.card)
                        .moveDisabled(true)
                    }
                } header: {
                    Text("Archiv")
                } footer: {
                    Text("Verkaufte und stillgelegte Fahrzeuge: Daten und Statistiken bleiben lesbar, ändern lässt sich nichts, bis du das Fahrzeug wieder aktivierst.")
                }
            }
        }
        .themedBackground()
        .navigationTitle("Fahrzeuge")
        .alert("Reihenfolge nicht gesichert", isPresented: Binding(
            get: { moveError != nil }, set: { if !$0 { moveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: moveError ?? "")
        }
        .toolbar {
            if store.vehicles.filter({ !$0.isShared }).count > 1 {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Fahrzeug hinzufügen", systemImage: "plus") { showingAddVehicle = true }
            }
        }
        .overlay {
            if store.allVehicles.isEmpty {
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
                if let summary = vehicle.archiveSummary {
                    Label(summary, systemImage: "archivebox")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if vehicle.isShared { SharedVehicleBadge(vehicle: vehicle) }
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
        if let summary = vehicle.archiveSummary { parts.append(summary) }
        if vehicle.isShared { parts.append(SharedVehicleBadge.text(for: vehicle)) }
        return parts.joined(separator: ", ")
    }
}

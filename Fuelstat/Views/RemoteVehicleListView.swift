import SwiftUI

/// Vehicles of the signed-in user, loaded from the Fuelstat API.
struct RemoteVehicleListView: View {
    @Environment(AuthSession.self) private var auth
    @State private var store: VehicleStore?

    var body: some View {
        Group {
            if let store {
                VehicleList(store: store)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if store == nil { store = VehicleStore(auth: auth) }
        }
    }
}

private struct VehicleList: View {
    @Environment(AuthSession.self) private var auth
    @Bindable var store: VehicleStore
    @State private var showingAddVehicle = false

    var body: some View {
        NavigationStack {
            List {
                if let error = store.loadError, !store.vehicles.isEmpty {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(store.vehicles) { vehicle in
                    NavigationLink(value: vehicle.id) {
                        RemoteVehicleRow(vehicle: vehicle, store: store)
                    }
                }
            }
            .navigationTitle("Fahrzeuge")
            .navigationDestination(for: String.self) { id in
                RemoteVehicleDetailView(vehicleID: id, store: store)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fahrzeug hinzufügen", systemImage: "plus") { showingAddVehicle = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if case .signedIn(let user) = auth.state {
                            Text(user.email)
                        }
                        if ServerSettings.isCustom {
                            Text("Server: \(ServerSettings.displayName(of: auth.api.baseURL))")
                        }
                        Button("Abmelden", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            Task { await auth.logout() }
                        }
                    } label: {
                        Label("Konto", systemImage: "person.crop.circle")
                    }
                }
            }
            .overlay { overlay }
            .refreshable { await store.load() }
            .task { await store.load() }
            .sheet(isPresented: $showingAddVehicle) {
                RemoteVehicleFormView(store: store)
            }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if !store.hasLoaded {
            ProgressView()
        } else if let error = store.loadError, store.vehicles.isEmpty {
            ContentUnavailableView {
                Label("Laden fehlgeschlagen", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Erneut versuchen") { Task { await store.load() } }
                    .buttonStyle(.borderedProminent)
            }
        } else if store.vehicles.isEmpty {
            ContentUnavailableView {
                Label("Noch keine Fahrzeuge", systemImage: "car")
            } description: {
                Text("Lege dein erstes Fahrzeug an.")
            } actions: {
                Button("Fahrzeug hinzufügen") { showingAddVehicle = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct RemoteVehicleRow: View {
    let vehicle: RemoteVehicle
    let store: VehicleStore

    @ScaledMetric(relativeTo: .headline) private var photoSize: CGFloat = 56

    private var odometer: String? { store.currentOdometer(of: vehicle).map(Fmt.kilometres) }

    var body: some View {
        HStack(spacing: 12) {
            VehiclePhoto(url: store.imageURL(of: vehicle), fuelType: vehicle.fuelType)
                .frame(width: photoSize, height: photoSize)
                .clipShape(RoundedRectangle(cornerRadius: 10))
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
        .padding(.vertical, 4)
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

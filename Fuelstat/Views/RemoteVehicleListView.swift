import SwiftUI

/// Vehicles of the signed-in user, loaded from the Fuelstat API.
struct RemoteVehicleListView: View {
    @Environment(AuthSession.self) private var auth

    @State private var vehicles: [RemoteVehicle] = []
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var showingAddVehicle = false

    var body: some View {
        NavigationStack {
            List(vehicles) { vehicle in
                NavigationLink(value: vehicle) {
                    RemoteVehicleRow(vehicle: vehicle)
                }
            }
            .navigationTitle("Fahrzeuge")
            .navigationDestination(for: RemoteVehicle.self) { RemoteVehicleDetailView(vehicle: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fahrzeug hinzufügen", systemImage: "plus") { showingAddVehicle = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if case .signedIn(let user) = auth.state {
                            Text(user.email)
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
            .refreshable { await load() }
            .task { await load() }
            .sheet(isPresented: $showingAddVehicle) {
                RemoteVehicleFormView { vehicle in
                    vehicles.append(vehicle)
                    vehicles.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                }
            }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        if !hasLoaded {
            ProgressView()
        } else if let errorMessage, vehicles.isEmpty {
            ContentUnavailableView {
                Label("Laden fehlgeschlagen", systemImage: "wifi.exclamationmark")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Erneut versuchen") { Task { await load() } }
                    .buttonStyle(.borderedProminent)
            }
        } else if vehicles.isEmpty {
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

    private func load() async {
        guard let token = auth.token else { return }
        do {
            vehicles = try await auth.api.vehicles(token: token)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            errorMessage = nil
        } catch APIError.unauthorized {
            auth.handleUnauthorized()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        hasLoaded = true
    }
}

private struct RemoteVehicleRow: View {
    let vehicle: RemoteVehicle

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: vehicle.fuelType.symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(vehicle.name).font(.headline)
                Text([vehicle.fuelType.label, vehicle.licensePlate].compactMap { $0 }.filter { !$0.isEmpty }
                    .joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

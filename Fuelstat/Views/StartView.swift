import SwiftUI

/// Start: the selected vehicle with key figures, due dates, nearby stations and the latest entries.
struct StartView: View {
    @Bindable var store: VehicleStore
    @Binding var selectedID: String?
    let refresh: Int
    var onShowEntries: () -> Void
    var onShowProfile: () -> Void
    var onManageVehicles: () -> Void

    @State private var path: [Route] = []
    @State private var fillups: [RemoteFillup] = []
    @State private var reminders: [RemoteReminder] = []
    @State private var showingStations = false

    private var vehicle: RemoteVehicle? { selectedID.flatMap(store.vehicle) }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let vehicle {
                    content(vehicle)
                } else {
                    VehicleListPlaceholder(store: store)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .vehicleRoutes(store: store)
        }
    }

    private func content(_ vehicle: RemoteVehicle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
                header

                if let error = store.loadError {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                NavigationLink(value: Route.vehicle(vehicle.id)) {
                    VehicleHero(vehicle: vehicle, photoURL: store.imageURL(of: vehicle),
                                odometer: store.currentOdometer(of: vehicle).map(Fmt.kilometres))
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Öffnet die Fahrzeugseite"))

                KeyFigureTiles(vehicle: vehicle, stats: store.stats[vehicle.id],
                               odometer: store.currentOdometer(of: vehicle), catalog: store.fuelCatalog)

                RemindersCard(reminders: reminders) { path.append(.reminders(vehicle.id)) }

                NearbyCard(store: store, vehicle: vehicle) { showingStations = true }

                RecentEntriesCard(fillups: fillups, fuelType: vehicle.fuelType, onShowAll: onShowEntries)
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.background.ignoresSafeArea())
        .refreshable {
            // Reloading the vehicles redraws this screen, which cancels the refresh task; the loads therefore
            // run in their own task, so the latest entries and due dates arrive all the same.
            let id = vehicle.id
            await Task {
                async let vehicles: Void = store.load()
                async let entries: Void = load(id)
                _ = await (vehicles, entries)
            }.value
        }
        .task(id: "\(vehicle.id)-\(refresh)") { await load(vehicle.id) }
        .sheet(isPresented: $showingStations) {
            if let type = vehicle.fuelType.stationSearchType(unit: "l") {
                StationPickerView(store: store, type: type)
            }
        }
    }

    private var header: some View {
        HStack {
            VehicleSwitcher(store: store, selectedID: $selectedID, onManage: onManageVehicles)
            Spacer()
            Button(action: onShowProfile) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.brand)
            }
            .accessibilityLabel("Profil")
        }
        .padding(.top, Theme.Spacing.xs)
    }

    private func load(_ id: String) async {
        async let latest = try? store.fillups(of: id, limit: 5)
        async let due = try? store.reminders(of: id)
        fillups = await latest ?? fillups
        reminders = await due ?? reminders
    }
}

import SwiftUI

/// Statistik for the selected vehicle: key figures and consumption per fill-up from `/stats`.
struct StatisticsView: View {
    @Bindable var store: VehicleStore
    @Binding var selectedID: String?
    let refresh: Int
    var onManageVehicles: () -> Void

    @State private var range: ConsumptionChartCard.Range = .year

    private var vehicle: RemoteVehicle? { selectedID.flatMap(store.vehicle) }

    var body: some View {
        NavigationStack {
            Group {
                if let vehicle {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
                            VehicleSwitcher(store: store, selectedID: $selectedID, onManage: onManageVehicles)
                            KeyFigureTiles(vehicle: vehicle, stats: store.stats[vehicle.id],
                                           odometer: store.currentOdometer(of: vehicle), catalog: store.fuelCatalog)
                            ConsumptionChartCard(stats: store.stats[vehicle.id], fuelType: vehicle.fuelType,
                                                 range: $range, catalog: store.fuelCatalog)
                        }
                        .padding(.horizontal, Theme.Spacing.screen)
                        .padding(.bottom, Theme.Spacing.xl)
                    }
                    .background(Theme.background.ignoresSafeArea())
                    .refreshable { _ = try? await store.reload(vehicle.id) }
                    .task(id: "\(vehicle.id)-\(refresh)") { _ = try? await store.reload(vehicle.id) }
                } else {
                    VehicleListPlaceholder(store: store)
                }
            }
            .navigationTitle("Statistik")
        }
    }
}

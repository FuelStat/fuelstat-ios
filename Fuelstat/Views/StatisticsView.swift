import FuelstatCore
import SwiftUI

/// Statistik for the selected vehicle: consumption (`/stats`, `/consumption`) and costs (`/costs`), all
/// calculated by the API (FuelStat/fuelstat#82, #124).
struct StatisticsView: View {
    @Bindable var store: VehicleStore
    @Binding var selectedID: String?
    let refresh: Int
    var onManageVehicles: () -> Void

    private enum Tab: Hashable { case consumption, costs }

    @State private var tab: Tab = .consumption
    @State private var range: ConsumptionChartCard.Range = .year

    @State private var consumption: VehicleConsumption?
    @State private var consumptionMessage: String?
    /// The year chosen for the costs; nil shows the whole period.
    @State private var year: Int?
    @State private var costs: VehicleCosts?
    @State private var yearCosts: [Int: VehicleCosts] = [:]
    @State private var costsMessage: String?
    /// The vehicles the loaded figures belong to, so another vehicle never shows the previous one's numbers.
    @State private var consumptionVehicleID: String?
    @State private var costsVehicleID: String?

    private var vehicle: RemoteVehicle? { selectedID.flatMap(store.vehicle) }

    var body: some View {
        NavigationStack {
            Group {
                if let vehicle {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
                            VehicleSwitcher(store: store, selectedID: $selectedID, onManage: onManageVehicles)
                            ChipGroup(options: [
                                .init(value: Tab.consumption, title: "Verbrauch"),
                                .init(value: Tab.costs, title: "Kosten"),
                            ], selection: $tab)
                            switch tab {
                            case .consumption: consumptionContent(vehicle)
                            case .costs: costsContent(vehicle)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.screen)
                        .padding(.bottom, Theme.Spacing.xl)
                    }
                    .background(Theme.background.ignoresSafeArea())
                    .refreshable {
                        await loadAll(vehicle.id)
                        await loadCosts(vehicle.id)
                    }
                    .task(id: "\(vehicle.id)-\(refresh)") { await loadAll(vehicle.id) }
                    .task(id: "\(vehicle.id)-\(refresh)-\(year.map(String.init) ?? "all")") {
                        await loadCosts(vehicle.id)
                    }
                    .onChange(of: selectedID) { year = nil }
                } else {
                    VehicleListPlaceholder(store: store)
                }
            }
            .navigationTitle("Statistik")
        }
    }

    // MARK: Consumption

    @ViewBuilder
    private func consumptionContent(_ vehicle: RemoteVehicle) -> some View {
        KeyFigureTiles(vehicle: vehicle, stats: store.stats[vehicle.id],
                       odometer: store.currentOdometer(of: vehicle), catalog: store.fuelCatalog)
        ConsumptionChartCard(stats: store.stats[vehicle.id], fuelType: vehicle.fuelType,
                             range: $range, catalog: store.fuelCatalog)
        if let consumption, consumptionVehicleID == vehicle.id {
            ConsumptionDetailSection(consumption: consumption, vehicle: vehicle, catalog: store.fuelCatalog)
        } else if let consumptionMessage {
            Label(consumptionMessage, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    // MARK: Costs

    @ViewBuilder
    private func costsContent(_ vehicle: RemoteVehicle) -> some View {
        if let costs, costsVehicleID == vehicle.id {
            CostsSection(vehicle: vehicle, costs: costs, yearCosts: yearCosts, categories: store.categories,
                         year: $year)
        } else if let costsMessage {
            Label(costsMessage, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    // MARK: Loading

    private func loadAll(_ id: String) async {
        async let reloaded = try? store.reload(id)
        async let consumptionLoaded: Void = loadConsumption(id)
        async let categoriesLoaded = try? store.loadCategories()
        _ = await (reloaded, consumptionLoaded, categoriesLoaded)
    }

    private func loadConsumption(_ id: String) async {
        do {
            let loaded = try await store.consumption(of: id)
            guard !Task.isCancelled, selectedID == id else { return }
            consumption = loaded
            consumptionMessage = nil
            consumptionVehicleID = id
        } catch is CancellationError {
            return
        } catch {
            consumptionMessage = String(localized: "Die Auswertung konnte nicht geladen werden.") + " " + error.localizedDescription
        }
    }

    /// Costs of the chosen year; for the whole period also every year for the comparison.
    private func loadCosts(_ id: String) async {
        let chosen = year
        do {
            let loaded = try await store.costs(of: id, year: chosen)
            guard !Task.isCancelled, selectedID == id, year == chosen else { return }
            costs = loaded
            costsMessage = nil
            costsVehicleID = id
            guard chosen == nil else { return }
            // One request per year, as the web app does; the figures of each year come from the API.
            var perYear: [Int: VehicleCosts] = [:]
            for value in loaded.years where perYear[value] == nil {
                if let costs = try? await store.costs(of: id, year: value) { perYear[value] = costs }
                guard !Task.isCancelled else { return }
            }
            guard selectedID == id, year == nil else { return }
            yearCosts = perYear
        } catch is CancellationError {
            return
        } catch {
            costsMessage = String(localized: "Die Kosten konnten nicht geladen werden.") + " " + error.localizedDescription
        }
    }
}

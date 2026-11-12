import FuelstatCore
import SwiftUI

/// All fill-ups and charging sessions of the selected vehicle, grouped by month, with search and filter chips.
struct EntriesView: View {
    @Bindable var store: VehicleStore
    @Binding var selectedID: String?
    let refresh: Int
    var onManageVehicles: () -> Void

    private enum Filter: Hashable {
        case all, fuel, charge
    }

    private static let pageSize = 50

    @State private var fillups: [RemoteFillup] = []
    @State private var canLoadMore = false
    @State private var loadedPages = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var filter: Filter = .all
    @State private var search = ""
    @State private var deleting: RemoteFillup?

    private var vehicle: RemoteVehicle? { selectedID.flatMap(store.vehicle) }

    private var visible: [RemoteFillup] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return fillups.filter { fillup in
            switch filter {
            case .all: break
            case .fuel: if fillup.isCharging { return false }
            case .charge: if !fillup.isCharging { return false }
            }
            return query.isEmpty || (fillup.station?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private struct Month: Identifiable {
        let id: DateComponents
        let title: String
        let fillups: [RemoteFillup]
    }

    private var months: [Month] {
        let calendar = Calendar.current
        var order: [DateComponents] = []
        var groups: [DateComponents: [RemoteFillup]] = [:]
        for fillup in visible {
            let key = fillup.filledAt.map { calendar.dateComponents([.year, .month], from: $0) } ?? DateComponents()
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(fillup)
        }
        return order.map { key in
            let title = calendar.date(from: key)?.formatted(.dateTime.month(.wide).year()) ?? String(localized: "Ohne Datum")
            return Month(id: key, title: title, fillups: groups[key] ?? [])
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let vehicle {
                    list(vehicle)
                } else {
                    VehicleListPlaceholder(store: store)
                }
            }
            .navigationTitle("Einträge")
            .vehicleRoutes(store: store)
        }
    }

    private func list(_ vehicle: RemoteVehicle) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    VehicleSwitcher(store: store, selectedID: $selectedID, onManage: onManageVehicles)
                    let options = filterOptions(vehicle)
                    if options.count > 1 {
                        ChipGroup(options: options, selection: $filter)
                    }
                }
                .listRowInsets(EdgeInsets(top: Theme.Spacing.xs, leading: Theme.Spacing.screen,
                                          bottom: Theme.Spacing.xs, trailing: Theme.Spacing.screen))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.Status.overdue)
                    .listRowBackground(Color.clear)
            }

            ForEach(months) { month in
                Section {
                    ForEach(month.fillups) { fillup in
                        FillupEntryRow(fillup: fillup, fuelType: vehicle.fuelType)
                            .listRowBackground(Theme.card)
                            .swipeActions(edge: .trailing) {
                                Button("Löschen", systemImage: "trash", role: .destructive) { deleting = fillup }
                            }
                    }
                } header: {
                    Text(month.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.brandDeep)
                        .textCase(nil)
                }
            }

            if canLoadMore, search.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .onAppear { Task { await loadMore(vehicle.id) } }
            }
        }
        .listStyle(.plain)
        .themedBackground()
        .searchable(text: $search, prompt: Text("Tankstelle suchen"))
        .overlay {
            if !isLoading, months.isEmpty, errorMessage == nil {
                if search.isEmpty && filter == .all {
                    ContentUnavailableView("Noch keine Einträge", systemImage: "list.bullet.rectangle",
                                           description: Text("Mit „+“ erfasst du deinen ersten Tank- oder Ladevorgang."))
                } else {
                    ContentUnavailableView.search
                }
            }
        }
        .refreshable { await reload(vehicle.id) }
        .task(id: "\(vehicle.id)-\(refresh)") { await reload(vehicle.id) }
        .confirmationDialog("Eintrag löschen?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible, presenting: deleting) { fillup in
            Button("Löschen", role: .destructive) { delete(fillup, of: vehicle.id) }
        } message: { _ in
            Text("Das lässt sich nicht rückgängig machen.")
        }
    }

    private func filterOptions(_ vehicle: RemoteVehicle) -> [ChipGroup<Filter>.Option] {
        var options: [ChipGroup<Filter>.Option] = [.init(value: .all, title: "Alle")]
        let units = vehicle.fuelType.fillupUnits
        if units.contains(where: { $0 != "kwh" }) {
            options.append(.init(value: .fuel, title: "Tanken", systemImage: "fuelpump.fill"))
        }
        if units.contains("kwh") {
            options.append(.init(value: .charge, title: "Laden", systemImage: "bolt.fill"))
        }
        return options.count > 2 ? options : [options[0]]
    }

    // MARK: - Loading

    private func reload(_ id: String) async {
        isLoading = fillups.isEmpty
        defer { isLoading = false }
        do {
            let page = try await store.fillups(of: id, page: 1, perPage: Self.pageSize)
            fillups = page.data
            loadedPages = 1
            canLoadMore = page.pagination.hasMore
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore(_ id: String) async {
        do {
            let page = try await store.fillups(of: id, page: loadedPages + 1, perPage: Self.pageSize)
            let known = Set(fillups.map(\.id))
            let new = page.data.filter { !known.contains($0.id) }
            fillups += new
            loadedPages += 1
            // Stop when the server returns nothing new, so a misbehaving server cannot cause an endless loop.
            canLoadMore = page.pagination.hasMore && !new.isEmpty
        } catch {
            canLoadMore = false
        }
    }

    private func delete(_ fillup: RemoteFillup, of vehicleID: String) {
        Task {
            do {
                try await store.deleteFillup(fillup.id, of: vehicleID)
                fillups.removeAll { $0.id == fillup.id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

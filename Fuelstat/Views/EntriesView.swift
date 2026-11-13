import FuelstatCore
import SwiftUI

/// All entries of the selected vehicle – fill-ups, charging sessions, expenses, odometer notes and trips – grouped
/// by month, with search and filter chips. The list, the filters and the month totals come from the API
/// (`GET /vehicles/:id/timeline`).
struct EntriesView: View {
    @Bindable var store: VehicleStore
    @Binding var selectedID: String?
    let refresh: Int
    var onManageVehicles: () -> Void

    private static let pageSize = 50

    @State private var items: [TimelineItem] = []
    @State private var monthTotals: [String: TimelinePage.Month] = [:]
    @State private var kindCounts: [String: Int] = [:]
    @State private var canLoadMore = false
    @State private var loadedPages = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// nil shows all kinds.
    @State private var filter: TimelineItem.Kind?
    @State private var search = ""
    @State private var deleting: TimelineItem?
    @State private var editing: TimelineItem?
    /// Changes after an entry was edited or deleted on its detail page.
    @State private var localRefresh = 0

    private var vehicle: RemoteVehicle? { selectedID.flatMap(store.vehicle) }

    private struct Month: Identifiable {
        /// `YYYY-MM`, empty for entries without a date.
        let id: String
        let title: String
        let items: [TimelineItem]
    }

    /// The API sorts and filters; this only groups consecutive rows under their month.
    private var months: [Month] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        var order: [String] = []
        var groups: [String: [TimelineItem]] = [:]
        var titles: [String: String] = [:]
        for item in items {
            var key = ""
            if let date = item.date {
                let parts = calendar.dateComponents([.year, .month], from: date)
                key = String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
                if titles[key] == nil {
                    var style = Date.FormatStyle.dateTime.month(.wide).year()
                    style.timeZone = calendar.timeZone
                    titles[key] = date.formatted(style)
                }
            }
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(item)
        }
        return order.map { key in
            Month(id: key, title: titles[key] ?? String(localized: "Ohne Datum"), items: groups[key] ?? [])
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
            .navigationDestination(for: TimelineItem.self) { item in
                EntryDetailView(store: store, vehicleID: selectedID ?? "", item: item) { localRefresh += 1 }
            }
        }
    }

    private func list(_ vehicle: RemoteVehicle) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    VehicleSwitcher(store: store, selectedID: $selectedID, onManage: onManageVehicles)
                    let options = filterOptions
                    if options.count > 2 {
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
                    ForEach(month.items) { item in
                        NavigationLink(value: item) {
                            TimelineRow(item: item, fuelType: vehicle.fuelType,
                                        category: store.categories?.category(item.category))
                        }
                        .listRowBackground(Theme.card)
                        .swipeActions(edge: .trailing) {
                            if vehicle.role.canRecord {
                                Button("Löschen", systemImage: "trash", role: .destructive) { deleting = item }
                                Button("Bearbeiten", systemImage: "pencil") { editing = item }
                                    .tint(Theme.brand)
                            }
                        }
                    }
                } header: {
                    monthHeader(month)
                }
            }

            if canLoadMore {
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
        .searchable(text: $search, prompt: Text("Ort, Kategorie oder Notiz suchen"))
        .overlay {
            if !isLoading, items.isEmpty, errorMessage == nil {
                if search.isEmpty && filter == nil {
                    ContentUnavailableView("Noch keine Einträge", systemImage: "list.bullet.rectangle",
                                           description: Text("Mit „+“ erfasst du deinen ersten Eintrag."))
                } else {
                    ContentUnavailableView.search
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: Route.tripLog(vehicle.id)) {
                    Label("Fahrtenbuch", systemImage: "book.closed")
                }
            }
        }
        .refreshable { await reload(vehicle.id) }
        .task(id: "\(vehicle.id)-\(refresh)-\(localRefresh)-\(store.entryChanges)-\(filter?.rawValue ?? "")-\(search)") {
            // Wait for a pause in typing before asking the server.
            if !search.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
            guard !Task.isCancelled else { return }
            await reload(vehicle.id)
        }
        .task { _ = try? await store.loadCategories() }
        .sheet(item: $editing, onDismiss: { localRefresh += 1 }) { item in
            EntryEditor(store: store, vehicleID: vehicle.id, item: item)
        }
        .confirmationDialog("Eintrag löschen?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible, presenting: deleting) { item in
            Button("Löschen", role: .destructive) { delete(item, of: vehicle.id) }
        } message: { _ in
            Text("Das lässt sich nicht rückgängig machen.")
        }
    }

    /// Month title with the number of entries and the costs of the whole month, as summed up by the API.
    private func monthHeader(_ month: Month) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(month.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.brandDeep)
            Spacer()
            if let total = monthTotals[month.id], total.total > 0 {
                Text(Fmt.currency(total.total))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityLabel(Text("Kosten im Monat: \(Fmt.currency(total.total))"))
            }
        }
        .textCase(nil)
    }

    /// "Alle" plus one chip per kind the vehicle has entries of (counts from the API, without filters).
    private var filterOptions: [ChipGroup<TimelineItem.Kind?>.Option] {
        var options: [ChipGroup<TimelineItem.Kind?>.Option] = [.init(value: nil, title: "Alle")]
        for kind in TimelineItem.Kind.allCases where (kindCounts[kind.rawValue] ?? 0) > 0 || kind == filter {
            options.append(.init(value: kind, title: kind.filterTitle, systemImage: kind.symbol))
        }
        return options
    }

    // MARK: - Loading

    private func page(_ number: Int, of id: String) async throws -> TimelinePage {
        try await store.timeline(of: id, page: number, perPage: Self.pageSize,
                                 kinds: filter.map { [$0] } ?? [],
                                 search: search.trimmingCharacters(in: .whitespaces))
    }

    private func reload(_ id: String) async {
        isLoading = items.isEmpty
        defer { isLoading = false }
        do {
            let page = try await page(1, of: id)
            items = page.items
            monthTotals = Dictionary(page.months.map { ($0.month, $0) }, uniquingKeysWith: { first, _ in first })
            kindCounts = page.kinds
            loadedPages = 1
            canLoadMore = page.hasMore
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore(_ id: String) async {
        do {
            let page = try await page(loadedPages + 1, of: id)
            let known = Set(items.map(\.id))
            let new = page.items.filter { !known.contains($0.id) }
            items += new
            for month in page.months where monthTotals[month.month] == nil { monthTotals[month.month] = month }
            loadedPages += 1
            // Stop when the server returns nothing new, so a misbehaving server cannot cause an endless loop.
            canLoadMore = page.hasMore && !new.isEmpty
        } catch {
            canLoadMore = false
        }
    }

    private func delete(_ item: TimelineItem, of vehicleID: String) {
        Task {
            do {
                try await store.delete(item, of: vehicleID)
                localRefresh += 1
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

extension TimelineItem.Kind {
    var filterTitle: LocalizedStringKey {
        switch self {
        case .fuel: "Tanken"
        case .charge: "Laden"
        case .expense: "Ausgaben"
        case .trip: "Fahrten"
        case .odometer: "Kilometer"
        }
    }

    var symbol: String {
        switch self {
        case .fuel: "fuelpump.fill"
        case .charge: "bolt.fill"
        case .expense: "eurosign.circle.fill"
        case .trip: "arrow.triangle.turn.up.right.diamond.fill"
        case .odometer: "gauge.with.needle.fill"
        }
    }
}

// MARK: - Row

/// One entry of the list as an `EntryRow`. Category name, icon and colour come from `GET /categories`.
struct TimelineRow: View {
    let item: TimelineItem
    let fuelType: RemoteFuelType
    let category: RemoteCategory?

    var body: some View {
        EntryRow(systemImage: symbol, tint: tint, title: item.title(category: category), subtitle: subtitle,
                 amount: amount, detail: detail, badge: badge)
    }

    private var symbol: String {
        switch item.kind {
        case .expense: category?.symbol ?? CategoryStyle.fallbackSymbol
        default: item.kind.symbol
        }
    }

    private var tint: Color {
        switch item.kind {
        case .fuel: fuelType.energyColor
        case .charge: Theme.Energy.electricity
        case .expense: category?.tint ?? Theme.brand
        case .trip, .odometer: Theme.brand
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let date = item.date { parts.append(date.formatted(.dateTime.day().month(.abbreviated))) }
        switch item.kind {
        case .fuel, .charge:
            if let km = item.odometerKm { parts.append(Fmt.kilometres(km)) }
        case .expense:
            if let place = item.place { parts.append(place) }
        case .trip:
            if let purpose = item.purpose.flatMap(TripPurpose.init(rawValue:)) { parts.append(purpose.label) }
        case .odometer:
            if let note = item.description { parts.append(note) }
        }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }

    private var amount: String? {
        switch item.kind {
        case .fuel, .charge, .expense: item.cost.map(Fmt.currency)
        case .trip: item.distanceKm.map { "\(Fmt.number($0, digits: 1)) km" }
        case .odometer: item.odometerKm.map(Fmt.kilometres)
        }
    }

    private var detail: String? {
        switch item.kind {
        case .fuel, .charge: item.amount.map { "\(Fmt.number($0, digits: 2)) \(item.unitLabel)" }
        default: nil
        }
    }

    private var badge: LocalizedStringKey? {
        guard item.source == .fillup else { return nil }
        if item.isMissingOdometer { return "ohne km" }
        return item.isFull == false ? "Teil" : nil
    }
}

extension TimelineItem {
    /// Title of the entry: station, category name, route or the kind.
    func title(category: RemoteCategory?) -> String {
        switch kind {
        case .fuel: place ?? String(localized: "Tanken")
        case .charge: place ?? String(localized: "Laden")
        case .expense: category?.name ?? self.category ?? String(localized: "Ausgabe")
        case .odometer: String(localized: "Kilometerstand")
        case .trip:
            [startPlace, endPlace].compactMap { $0 }.joined(separator: " → ").nonEmpty ?? String(localized: "Fahrt")
        }
    }
}

extension String {
    /// nil for an empty string.
    var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Editing

/// Opens the form that fits the entry: fill-up, expense or odometer note, or trip.
struct EntryEditor: View {
    let store: VehicleStore
    let vehicleID: String
    let item: TimelineItem

    var body: some View {
        switch item.source {
        case .fillup: FillupEntryView(store: store, vehicleID: vehicleID, editing: item)
        case .entry: ExpenseFormView(store: store, vehicleID: vehicleID, editing: item)
        case .trip: TripFormView(store: store, vehicleID: vehicleID, editingID: item.rawID)
        }
    }
}

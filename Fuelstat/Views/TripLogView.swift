import Charts
import SwiftUI

/// The trip log of a vehicle: totals per purpose, km per month, the trips of a year and the CSV export.
/// All sums, the business share and the estimated costs come from the API (`/trips/summary`).
struct TripLogView: View {
    let store: VehicleStore
    let vehicleID: String

    @State private var year: Int?
    @State private var purpose: TripPurpose?
    @State private var summary: TripSummary?
    @State private var trips: [RemoteTrip] = []
    @State private var years: [Int] = []
    @State private var canLoadMore = false
    @State private var loadedPages = 0
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var showingAdd = false
    @State private var editing: RemoteTrip?
    @State private var deleting: RemoteTrip?
    @State private var export: ExportedFile?
    @State private var isExporting = false

    private var vehicle: RemoteVehicle? { store.vehicle(vehicleID) }
    private var canRecord: Bool { vehicle?.role.canRecord ?? true }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    if !years.isEmpty {
                        ChipGroup(options: [.init(value: Int?.none, title: "Alle Jahre")]
                            + years.map { .init(value: Int?.some($0), title: LocalizedStringKey(String($0))) },
                                  selection: $year)
                    }
                    if let summary { summaryCards(summary) }
                    if let errorMessage { FormMessage(text: errorMessage) }
                }
                .listRowInsets(EdgeInsets(top: Theme.Spacing.xs, leading: Theme.Spacing.screen,
                                          bottom: Theme.Spacing.xs, trailing: Theme.Spacing.screen))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                ChipGroup(options: [.init(value: TripPurpose?.none, title: "Alle")]
                    + TripPurpose.allCases.map {
                        .init(value: TripPurpose?.some($0), title: LocalizedStringKey($0.label), systemImage: $0.symbol)
                    }, selection: $purpose)
                    .listRowInsets(EdgeInsets(top: Theme.Spacing.xs, leading: Theme.Spacing.screen,
                                              bottom: Theme.Spacing.xs, trailing: Theme.Spacing.screen))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                ForEach(trips) { trip in
                    TripRow(trip: trip)
                        .listRowBackground(Theme.card)
                        .swipeActions(edge: .trailing) {
                            if canRecord {
                                Button("Löschen", systemImage: "trash", role: .destructive) { deleting = trip }
                                Button("Bearbeiten", systemImage: "pencil") { editing = trip }
                                    .tint(Theme.brand)
                            }
                        }
                }

                if trips.isEmpty, !isLoading {
                    Text("Keine Fahrten in dieser Auswahl.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Theme.card)
                }

                if canLoadMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .onAppear { Task { await loadMore() } }
                }
            } header: {
                Text("Fahrten")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.brandDeep)
                    .textCase(nil)
            } footer: {
                Text("Ein Fahrtenbuch zur eigenen Übersicht – kein vom Finanzamt anerkanntes Fahrtenbuch.")
            }
        }
        .listStyle(.plain)
        .themedBackground()
        .overlay { if isLoading, trips.isEmpty, summary == nil { ProgressView() } }
        .navigationTitle("Fahrtenbuch")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Als CSV exportieren", systemImage: "square.and.arrow.up", action: exportCSV)
                    .disabled(isExporting || trips.isEmpty)
                if canRecord {
                    Button("Fahrt erfassen", systemImage: "plus") { showingAdd = true }
                }
            }
        }
        .refreshable { await reload() }
        .task(id: "\(year ?? 0)-\(purpose?.rawValue ?? "")-\(store.entryChanges)") { await reload() }
        .sheet(isPresented: $showingAdd) {
            TripFormView(store: store, vehicleID: vehicleID)
        }
        .sheet(item: $editing) { trip in
            TripFormView(store: store, vehicleID: vehicleID, editingID: trip.id)
        }
        .sheet(item: $export) { file in
            ShareSheet(items: [file.url])
        }
        .confirmationDialog("Fahrt löschen?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible, presenting: deleting) { trip in
            Button("Löschen", role: .destructive) { delete(trip) }
        } message: { _ in
            Text("Das lässt sich nicht rückgängig machen.")
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private func summaryCards(_ summary: TripSummary) -> some View {
        StatTileRow {
            StatTile(label: "Strecke", value: Fmt.number(summary.totalKm, digits: 0), unit: "km")
            StatTile(label: "Fahrten", value: String(summary.count))
            StatTile(label: "Dienstlich", value: summary.businessShare.map { Fmt.number($0, digits: 1) }, unit: "%")
        }

        CardContainer {
            VStack(spacing: Theme.Spacing.s) {
                ForEach(Array(TripPurpose.allCases.enumerated()), id: \.element.id) { index, purpose in
                    if index > 0 { Divider() }
                    purposeRow(purpose, summary.byPurpose[purpose.rawValue])
                }
                if summary.costPerKm != nil {
                    Text("Kosten geschätzt: Kosten pro km des Fahrzeugs × Strecke.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        if summary.months.count > 1 {
            CardContainer {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Kilometer je Monat")
                        .font(.headline)
                        .foregroundStyle(Theme.brandDeep)
                    Chart {
                        ForEach(summary.months) { month in
                            ForEach(TripPurpose.allCases) { purpose in
                                BarMark(x: .value("Monat", monthLabel(month.month)),
                                        y: .value("Kilometer", month.km[purpose.rawValue] ?? 0))
                                    .foregroundStyle(by: .value("Zweck", purpose.label))
                            }
                        }
                    }
                    .chartForegroundStyleScale(range: [Theme.brand, Theme.Energy.diesel, Theme.Energy.electricity])
                    .frame(minHeight: 180)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Kilometer je Monat"))
                    .accessibilityValue(Text(chartSummary(summary)))
                }
            }
        }
    }

    private func purposeRow(_ purpose: TripPurpose, _ total: TripSummary.PurposeTotal?) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: purpose.symbol)
                .foregroundStyle(Theme.brand)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: purpose.label).font(.body.weight(.medium))
                Text("\(total?.count ?? 0) Fahrten")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: "\(Fmt.number(total?.km ?? 0, digits: 1)) km")
                    .font(.body.weight(.semibold))
                if let cost = total?.estimatedCost {
                    Text(verbatim: "≈ \(Fmt.currency(cost))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    /// "2026-03" → "Mär 26".
    private func monthLabel(_ month: String) -> String {
        let parts = month.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2,
              let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: parts[0], month: parts[1], day: 15))
        else { return month }
        return date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
    }

    private func chartSummary(_ summary: TripSummary) -> String {
        summary.months.map { month in
            let km = month.km.values.reduce(0, +)
            return "\(monthLabel(month.month)): \(Fmt.number(km, digits: 0)) km"
        }.joined(separator: ", ")
    }

    // MARK: - Loading

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let figures = store.tripSummary(of: vehicleID, year: year)
            async let first = store.trips(of: vehicleID, year: year, purpose: purpose?.rawValue, page: 1)
            let page = try await first
            summary = try await figures
            trips = page.trips
            if !page.years.isEmpty || years.isEmpty { years = page.years }
            loadedPages = 1
            canLoadMore = page.hasMore
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore() async {
        do {
            let page = try await store.trips(of: vehicleID, year: year, purpose: purpose?.rawValue,
                                             page: loadedPages + 1)
            let known = Set(trips.map(\.id))
            let new = page.trips.filter { !known.contains($0.id) }
            trips += new
            loadedPages += 1
            canLoadMore = page.hasMore && !new.isEmpty
        } catch {
            canLoadMore = false
        }
    }

    private func delete(_ trip: RemoteTrip) {
        Task {
            do {
                try await store.deleteTrip(trip.id, of: vehicleID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Loads the CSV the API writes and hands it to the share sheet. A plan without export gets the API's message.
    private func exportCSV() {
        isExporting = true
        errorMessage = nil
        Task {
            defer { isExporting = false }
            do {
                let data = try await store.tripsCSV(of: vehicleID, year: year)
                let name = year.map { "fahrtenbuch-\($0).csv" } ?? "fahrtenbuch.csv"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                try data.write(to: url, options: .atomic)
                export = ExportedFile(url: url)
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// A file written for the share sheet.
struct ExportedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The system share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct TripRow: View {
    let trip: RemoteTrip

    private var purpose: TripPurpose? { TripPurpose(rawValue: trip.purpose) }

    var body: some View {
        EntryRow(systemImage: purpose?.symbol ?? "arrow.triangle.turn.up.right.diamond.fill",
                 title: trip.route ?? purpose?.label ?? String(localized: "Fahrt"),
                 subtitle: subtitle,
                 amount: trip.distanceKm.map { "\(Fmt.number($0, digits: 1)) km" },
                 detail: trip.odometerEnd.map(Fmt.kilometres))
    }

    private var subtitle: String {
        var parts: [String] = []
        if let date = trip.startedAt { parts.append(date.formatted(.dateTime.day().month(.abbreviated).year())) }
        if trip.route != nil, let purpose { parts.append(purpose.label) }
        if let note = trip.note { parts.append(note) }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }
}

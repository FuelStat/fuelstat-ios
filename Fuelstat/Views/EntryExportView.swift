import FuelstatCore
import SwiftUI

/// Einträge → Exportieren: all entries of a vehicle as a CSV file in the web app's format (`export.php`), through
/// the share sheet. The rows come from the API's timeline; the file is only formatted here.
struct EntryExportView: View {
    let store: VehicleStore
    let vehicle: RemoteVehicle

    @Environment(\.dismiss) private var dismiss

    @State private var items: [TimelineItem] = []
    @State private var years: [Int] = []
    @State private var year: Int?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var file: ExportedFile?

    /// Entries of the chosen year; the trip log has its own export.
    private var selected: [TimelineItem] {
        items.filter { item in
            guard let date = item.date else { return false }
            return year.map { EntryCSV.year(of: date) == $0 } ?? true
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Zeitraum", selection: $year) {
                        Text("Alle Jahre").tag(Int?.none)
                        ForEach(years, id: \.self) { Text(verbatim: String($0)).tag(Int?.some($0)) }
                    }
                } footer: {
                    Text("Die Datei hat dasselbe Format wie der Export der Web-App und lässt sich in Excel oder Numbers öffnen. Fahrten exportierst du im Fahrtenbuch.")
                }
                .listRowBackground(Theme.card)

                Section {
                    if isLoading {
                        HStack(spacing: Theme.Spacing.xs) {
                            ProgressView()
                            Text("Lade Einträge …").foregroundStyle(.secondary)
                        }
                    } else if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.Status.overdue)
                        Button("Erneut versuchen") { Task { await load() } }
                    } else {
                        LabeledContent("Einträge", value: String(selected.count))
                    }
                }
                .listRowBackground(Theme.card)
            }
            .themedBackground()
            .navigationTitle("Einträge exportieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "CSV teilen", systemImage: "square.and.arrow.up", action: share)
                    .disabled(isLoading || errorMessage != nil || selected.isEmpty)
                    .padding(.horizontal, Theme.Spacing.screen)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(.bar)
            }
            .task { await load() }
            .sheet(item: $file) { file in
                ShareSheet(items: [file.url])
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            _ = await store.loadFuelCatalog()
            _ = try? await store.loadCategories()
            var all: [TimelineItem] = []
            var page = 1
            while true {
                let loaded = try await store.timeline(of: vehicle.id, page: page, perPage: Page<TimelineItem>.maxPerPage,
                                                      kinds: [.fuel, .charge, .expense, .odometer], search: nil)
                if page == 1 { years = loaded.years.sorted(by: >) }
                all += loaded.items
                guard loaded.hasMore else { break }
                page += 1
            }
            items = all
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func share() {
        let rows = selected.compactMap(Self.row)
        let context = EntryCSVVehicle(
            name: vehicle.name,
            fuelType: vehicle.fuelType.rawValue,
            hasSeveralFuels: vehicle.fuels.count > 1,
            fuelNames: Dictionary((store.fuelCatalog?.fuels ?? []).map { ($0.key, $0.name) },
                                  uniquingKeysWith: { first, _ in first }),
            categoryNames: Dictionary((store.categories?.categories ?? []).map { ($0.key, $0.name) },
                                      uniquingKeysWith: { first, _ in first })
        )
        let data = EntryCSV.make(rows: rows, vehicle: context)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(EntryCSV.fileName(vehicleName: vehicle.name, year: year))
        do {
            try data.write(to: url, options: .atomic)
            file = ExportedFile(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func row(_ item: TimelineItem) -> EntryCSVRow? {
        guard let date = item.date else { return nil }
        return EntryCSVRow(
            date: date,
            category: item.source == .fillup ? EntryCSV.fillingCategory : item.category ?? "",
            odometerKm: item.odometerKm.map { Int($0.rounded()) },
            odometerEstimated: item.odometerEstimated,
            amount: item.amount,
            unit: item.unit,
            fuel: item.fuel,
            cost: item.cost,
            isFull: item.isFull,
            skipPrevious: item.skipPrevious,
            consumption: item.consumption,
            place: item.place,
            description: item.description
        )
    }
}

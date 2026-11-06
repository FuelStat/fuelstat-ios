import FuelstatCore
import SwiftData
import SwiftUI

struct VehicleDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let vehicle: Vehicle
    @State private var showingAddEntry = false

    private var sortedEntries: [FuelEntry] {
        vehicle.entries.sorted { ($0.odometer, $0.date) > ($1.odometer, $1.date) }
    }

    var body: some View {
        let stats = vehicle.stats
        let unit = vehicle.fuelType.unit
        List {
            Section("Statistik") {
                LabeledContent("Ø Verbrauch") {
                    Text(stats.averageConsumption.map { "\(Fmt.number($0, digits: 2)) \(unit)/100 km" } ?? "–")
                }
                LabeledContent("Kosten pro km") {
                    Text(stats.costPerKilometre.map { Fmt.pricePerUnit($0) } ?? "–")
                }
                LabeledContent("Ø Preis pro \(unit)") {
                    Text(stats.averagePricePerUnit.map { Fmt.pricePerUnit($0) } ?? "–")
                }
                LabeledContent("Gesamtkosten", value: Fmt.currency(stats.totalCost))
                LabeledContent("Erfasste Strecke", value: Fmt.kilometres(stats.trackedDistance))
            }

            Section {
                ForEach(sortedEntries) { entry in
                    FuelEntryRow(entry: entry, unit: unit)
                }
                .onDelete { offsets in
                    let entries = sortedEntries
                    for index in offsets { modelContext.delete(entries[index]) }
                }
            } header: {
                Text("Tankvorgänge")
            } footer: {
                if stats.averageConsumption == nil {
                    Text("Der Verbrauch wird zwischen zwei Volltankungen berechnet.")
                }
            }
        }
        .navigationTitle(vehicle.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Tankvorgang hinzufügen", systemImage: "plus") { showingAddEntry = true }
            }
        }
        .sheet(isPresented: $showingAddEntry) {
            FuelEntryFormView(vehicle: vehicle)
        }
    }
}

private struct FuelEntryRow: View {
    let entry: FuelEntry
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.date, format: .dateTime.day().month().year())
                    .font(.headline)
                if !entry.isFullTank {
                    Text("Teilbetankung")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.15), in: Capsule())
                }
                Spacer()
                Text(Fmt.currency(entry.totalCost)).font(.headline)
            }
            HStack {
                Text(Fmt.kilometres(entry.odometer))
                Spacer()
                Text("\(Fmt.number(entry.volume, digits: 2)) \(unit)")
                if let price = entry.fillUp.pricePerUnit {
                    Text("· \(Fmt.pricePerUnit(price))/\(unit)")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        VehicleDetailView(vehicle: PreviewData.vehicle)
    }
    .modelContainer(PreviewData.container)
}

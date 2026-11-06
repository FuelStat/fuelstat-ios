import SwiftData
import SwiftUI

struct VehicleListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @State private var showingAddVehicle = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(vehicles) { vehicle in
                    NavigationLink(value: vehicle) {
                        VehicleRow(vehicle: vehicle)
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("Fahrzeuge")
            .navigationDestination(for: Vehicle.self) { VehicleDetailView(vehicle: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Fahrzeug hinzufügen", systemImage: "plus") { showingAddVehicle = true }
                }
            }
            .overlay {
                if vehicles.isEmpty {
                    ContentUnavailableView {
                        Label("Noch keine Fahrzeuge", systemImage: "car")
                    } description: {
                        Text("Lege dein erstes Fahrzeug an, um Tankvorgänge zu erfassen.")
                    } actions: {
                        Button("Fahrzeug hinzufügen") { showingAddVehicle = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .sheet(isPresented: $showingAddVehicle) {
                VehicleFormView()
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(vehicles[index])
        }
    }
}

private struct VehicleRow: View {
    let vehicle: Vehicle

    var body: some View {
        let stats = vehicle.stats
        HStack(spacing: 12) {
            Image(systemName: vehicle.fuelType.symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(vehicle.name).font(.headline)
                Group {
                    if let avg = stats.averageConsumption {
                        Text("Ø \(Fmt.number(avg)) \(vehicle.fuelType.unit)/100 km")
                    } else {
                        Text("\(stats.fillUpCount) Tankvorgänge")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    VehicleListView()
        .modelContainer(PreviewData.container)
}

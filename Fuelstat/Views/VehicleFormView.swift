import SwiftData
import SwiftUI

struct VehicleFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var fuelType: FuelType = .petrol

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name, z. B. Golf", text: $name)
                Picker("Antrieb", selection: $fuelType) {
                    ForEach(FuelType.allCases) { Text($0.label).tag($0) }
                }
            }
            .navigationTitle("Neues Fahrzeug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        modelContext.insert(Vehicle(name: trimmedName, fuelType: fuelType))
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

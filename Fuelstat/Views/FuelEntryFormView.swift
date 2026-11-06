import SwiftData
import SwiftUI

struct FuelEntryFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let vehicle: Vehicle

    @State private var date = Date.now
    @State private var odometer: Double?
    @State private var volume: Double?
    @State private var totalCost: Double?
    @State private var isFullTank = true
    @State private var note = ""

    var body: some View {
        let unit = vehicle.fuelType.unit
        NavigationStack {
            Form {
                Section {
                    DatePicker("Datum", selection: $date)
                    LabeledContent("Kilometerstand") {
                        TextField(odometerPrompt, value: $odometer, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Menge (\(unit))") {
                        TextField("0", value: $volume, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Betrag (\(Fmt.currencyCode))") {
                        TextField("0", value: $totalCost, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Toggle("Vollgetankt", isOn: $isFullTank)
                } footer: {
                    if let warning = validationWarning {
                        Text(warning).foregroundStyle(.red)
                    }
                }
                Section("Notiz") {
                    TextField("Optional", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Tankvorgang")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern", action: save).disabled(!isValid)
                }
            }
        }
    }

    private var odometerPrompt: String {
        vehicle.latestOdometer.map { "> \(Fmt.number($0, digits: 0))" } ?? "km"
    }

    private var isValid: Bool {
        guard let odometer, let volume, let totalCost else { return false }
        return odometer >= 0 && volume > 0 && totalCost >= 0
    }

    private var validationWarning: String? {
        guard let odometer, let latest = vehicle.latestOdometer, odometer <= latest else { return nil }
        return "Kilometerstand liegt nicht über dem letzten Eintrag (\(Fmt.kilometres(latest)))."
    }

    private func save() {
        guard let odometer, let volume, let totalCost else { return }
        let entry = FuelEntry(
            date: date, odometer: odometer, volume: volume, totalCost: totalCost,
            isFullTank: isFullTank, note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        modelContext.insert(entry)
        entry.vehicle = vehicle
        dismiss()
    }
}

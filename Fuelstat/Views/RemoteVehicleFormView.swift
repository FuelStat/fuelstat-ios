import SwiftUI

/// Sheet to create a vehicle via the Fuelstat API.
struct RemoteVehicleFormView: View {
    @Environment(AuthSession.self) private var auth
    @Environment(\.dismiss) private var dismiss

    var onCreated: (RemoteVehicle) -> Void

    @State private var name = ""
    @State private var fuelType: RemoteFuelType = .e10
    @State private var brand = ""
    @State private var model = ""
    @State private var year: Int?
    @State private var licensePlate = ""
    @State private var vin = ""
    @State private var hasFirstRegistration = false
    @State private var firstRegistration = Date.now
    @State private var odometerKm: Double?
    @State private var tankCapacity: Double?
    @State private var batteryCapacity: Double?

    @State private var isSaving = false
    @State private var errorMessage: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, z. B. Familienauto", text: $name)
                    Picker("Kraftstoff", selection: $fuelType) {
                        ForEach(RemoteFuelType.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section("Allgemein") {
                    TextField("Marke", text: $brand)
                    TextField("Modell", text: $model)
                    TextField("Baujahr", value: $year, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                }

                Section("Zulassung") {
                    TextField("Kennzeichen", text: $licensePlate)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: licensePlate) { licensePlate = String(licensePlate.prefix(15)) }
                    TextField("FIN", text: $vin)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: vin) { vin = String(vin.replacingOccurrences(of: " ", with: "").prefix(17)) }
                    Toggle("Erstzulassung angeben", isOn: $hasFirstRegistration)
                    if hasFirstRegistration {
                        DatePicker("Erstzulassung", selection: $firstRegistration, in: ...Date.now,
                                   displayedComponents: .date)
                    }
                }

                Section {
                    numberField("Kilometerstand", unit: "km", value: $odometerKm)
                    numberField(fuelType.tankCapacityLabel, unit: fuelType.tankCapacityUnit, value: $tankCapacity)
                    if fuelType.hasSeparateBattery {
                        numberField("Akkukapazität", unit: "kWh", value: $batteryCapacity)
                    }
                } header: {
                    Text("Technik")
                } footer: {
                    Text("Der Kilometerstand bei Anschaffung ist die Basis für die Fahrleistung.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Neues Fahrzeug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Sichern", action: save)
                            .disabled(trimmedName.isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func numberField(_ title: String, unit: String, value: Binding<Double?>) -> some View {
        HStack {
            TextField(title, value: value, format: .number)
                .keyboardType(.decimalPad)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func save() {
        guard let token = auth.token else { return }
        let request = VehicleCreateRequest(
            name: trimmedName,
            fuelType: fuelType,
            brand: Self.nonEmpty(brand),
            model: Self.nonEmpty(model),
            year: year,
            licensePlate: Self.nonEmpty(licensePlate)?.uppercased(),
            vin: Self.nonEmpty(vin)?.uppercased(),
            firstRegistration: hasFirstRegistration ? Self.apiDate(firstRegistration) : nil,
            odometerKm: odometerKm,
            tankCapacity: tankCapacity,
            batteryCapacity: fuelType.hasSeparateBattery ? batteryCapacity : nil
        )
        errorMessage = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let vehicle = try await auth.api.createVehicle(request, token: token)
                onCreated(vehicle)
                dismiss()
            } catch APIError.unauthorized {
                auth.handleUnauthorized()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Calendar date in the user's time zone as `YYYY-MM-DD`.
    private static func apiDate(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

#Preview {
    RemoteVehicleFormView { _ in }
        .environment(AuthSession())
}

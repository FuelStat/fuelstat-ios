import FuelstatCore
import SwiftUI

/// Sheet to create a vehicle, or to change one when `editing` is set. Covers the master data of the web app:
/// drive type and fuel grades, registration, technical data, purchase and sale, service and oil intervals,
/// insurance, tax and tyres.
struct RemoteVehicleFormView: View {
    let store: VehicleStore
    var editing: RemoteVehicle?

    @Environment(\.dismiss) private var dismiss

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

    @State private var hasPurchaseDate = false
    @State private var purchaseDate = Date.now
    @State private var purchasePrice: Double?
    @State private var hasSaleDate = false
    @State private var saleDate = Date.now
    @State private var salePrice: Double?

    @State private var serviceIntervalMonths: Int?
    @State private var serviceIntervalKm: Int?
    @State private var oilIntervalMonths: Int?
    @State private var oilIntervalKm: Int?

    @State private var insuranceCompany = ""
    @State private var insurancePremium: Double?
    @State private var insuranceDueMonth: Int?
    @State private var taxAmount: Double?
    @State private var taxDueMonth: Int?

    @State private var tireSizeSummer = ""
    @State private var tireSizeWinter = ""

    /// Fuel grades; nil until the server's catalog is loaded (older servers do not have one).
    @State private var fuels: FuelSelection?
    @State private var catalog: FuelCatalog?

    @State private var isSaving = false
    @State private var errorMessage: String?

    init(store: VehicleStore, editing: RemoteVehicle? = nil) {
        self.store = store
        self.editing = editing
        guard let vehicle = editing else { return }
        _name = State(initialValue: vehicle.name)
        _fuelType = State(initialValue: vehicle.fuelType)
        _brand = State(initialValue: vehicle.brand ?? "")
        _model = State(initialValue: vehicle.model ?? "")
        _year = State(initialValue: vehicle.year)
        _licensePlate = State(initialValue: vehicle.licensePlate ?? "")
        _vin = State(initialValue: vehicle.vin ?? "")
        if let date = vehicle.firstRegistration.flatMap(Self.parseAPIDate) {
            _hasFirstRegistration = State(initialValue: true)
            _firstRegistration = State(initialValue: date)
        }
        _odometerKm = State(initialValue: vehicle.odometerKm)
        _tankCapacity = State(initialValue: vehicle.tankCapacity)
        _batteryCapacity = State(initialValue: vehicle.batteryCapacity)
        if let date = vehicle.purchaseDate.flatMap(Self.parseAPIDate) {
            _hasPurchaseDate = State(initialValue: true)
            _purchaseDate = State(initialValue: date)
        }
        _purchasePrice = State(initialValue: vehicle.purchasePrice)
        if let date = vehicle.saleDate.flatMap(Self.parseAPIDate) {
            _hasSaleDate = State(initialValue: true)
            _saleDate = State(initialValue: date)
        }
        _salePrice = State(initialValue: vehicle.salePrice)
        _serviceIntervalMonths = State(initialValue: vehicle.serviceIntervalMonths)
        _serviceIntervalKm = State(initialValue: vehicle.serviceIntervalKm)
        _oilIntervalMonths = State(initialValue: vehicle.oilIntervalMonths)
        _oilIntervalKm = State(initialValue: vehicle.oilIntervalKm)
        _insuranceCompany = State(initialValue: vehicle.insuranceCompany ?? "")
        _insurancePremium = State(initialValue: vehicle.insurancePremium)
        _insuranceDueMonth = State(initialValue: vehicle.insuranceDueMonth)
        _taxAmount = State(initialValue: vehicle.taxAmount)
        _taxDueMonth = State(initialValue: vehicle.taxDueMonth)
        _tireSizeSummer = State(initialValue: vehicle.tireSizeSummer ?? "")
        _tireSizeWinter = State(initialValue: vehicle.tireSizeWinter ?? "")
        if !vehicle.fuels.isEmpty {
            _fuels = State(initialValue: FuelSelection(keys: vehicle.fuels, defaultKey: vehicle.defaultFuel))
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    textRow("Name", prompt: "z. B. Familienauto", text: $name)
                    Picker("Antriebsart", selection: $fuelType) {
                        ForEach(RemoteFuelType.allCases) { Text($0.label).tag($0) }
                    }
                }
                .listRowBackground(Theme.card)

                fuelGradesSection

                Section("Allgemein") {
                    textRow("Marke", prompt: "z. B. VW", text: $brand)
                    textRow("Modell", prompt: "z. B. Golf", text: $model)
                    LabeledContent("Baujahr") {
                        TextField("Baujahr", value: $year, format: .number.grouping(.never), prompt: Text("z. B. 2020"))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .listRowBackground(Theme.card)

                Section("Zulassung") {
                    textRow("Kennzeichen", prompt: "z. B. B-AB 123", text: $licensePlate)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: licensePlate) { licensePlate = String(licensePlate.prefix(15)) }
                    textRow("FIN", prompt: "17 Zeichen", text: $vin)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: vin) { vin = String(vin.replacingOccurrences(of: " ", with: "").prefix(17)) }
                    Toggle("Erstzulassung angeben", isOn: $hasFirstRegistration)
                        .tint(Theme.brand)
                    if hasFirstRegistration {
                        DatePicker("Erstzulassung", selection: $firstRegistration, in: ...Date.now,
                                   displayedComponents: .date)
                    }
                }
                .listRowBackground(Theme.card)

                Section {
                    numberField("Kilometerstand bei Anschaffung", unit: "km", value: $odometerKm)
                    numberField(LocalizedStringKey(fuelType.tankCapacityLabel), unit: fuelType.tankCapacityUnit,
                                value: $tankCapacity)
                    if fuelType.hasSeparateBattery {
                        numberField("Akkukapazität", unit: "kWh", value: $batteryCapacity)
                    }
                } header: {
                    Text("Technik")
                } footer: {
                    Text("Der Kilometerstand bei Anschaffung ist die Basis für die Fahrleistung.")
                }
                .listRowBackground(Theme.card)

                Section("Kauf und Verkauf") {
                    Toggle("Kaufdatum angeben", isOn: $hasPurchaseDate)
                        .tint(Theme.brand)
                    if hasPurchaseDate {
                        DatePicker("Kaufdatum", selection: $purchaseDate, in: ...Date.now, displayedComponents: .date)
                    }
                    numberField("Kaufpreis", unit: "€", value: $purchasePrice)
                    Toggle("Verkaufsdatum angeben", isOn: $hasSaleDate)
                        .tint(Theme.brand)
                    if hasSaleDate {
                        DatePicker("Verkaufsdatum", selection: $saleDate, displayedComponents: .date)
                    }
                    numberField("Verkaufspreis", unit: "€", value: $salePrice)
                }
                .listRowBackground(Theme.card)

                Section {
                    integerField("Inspektion alle", unit: "Monate", value: $serviceIntervalMonths, prompt: "12")
                    integerField("Inspektion alle", unit: "km", value: $serviceIntervalKm, prompt: "15000")
                    integerField("Ölwechsel alle", unit: "Monate", value: $oilIntervalMonths, prompt: "z. B. 12")
                    integerField("Ölwechsel alle", unit: "km", value: $oilIntervalKm, prompt: "z. B. 15000")
                } header: {
                    Text("Wartung")
                } footer: {
                    Text("Aus den Intervallen ergeben sich die Termine für Inspektion und Ölwechsel. Ohne Angabe gelten die Standardwerte des Servers.")
                }
                .listRowBackground(Theme.card)

                Section("Versicherung und Steuer") {
                    textRow("Versicherung", prompt: "Gesellschaft", text: $insuranceCompany)
                    numberField("Beitrag pro Jahr", unit: "€", value: $insurancePremium)
                    monthPicker("Beitrag fällig im", selection: $insuranceDueMonth)
                    numberField("Kfz-Steuer pro Jahr", unit: "€", value: $taxAmount)
                    monthPicker("Steuer fällig im", selection: $taxDueMonth)
                }
                .listRowBackground(Theme.card)

                Section("Reifen") {
                    textRow("Sommerreifen", prompt: "z. B. 205/55 R16", text: $tireSizeSummer)
                    textRow("Winterreifen", prompt: "z. B. 205/55 R16", text: $tireSizeWinter)
                }
                .listRowBackground(Theme.card)

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.Status.overdue)
                    }
                }
            }
            .themedBackground()
            .navigationTitle(editing == nil ? "Neues Fahrzeug" : "Fahrzeug bearbeiten")
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
            .task { catalog = await store.loadFuelCatalog() }
            .onChange(of: fuelType) { suggestFuels() }
            .onChange(of: catalog == nil) { suggestFuels(onlyIfMissing: true) }
        }
    }

    // MARK: Fuel grades

    /// Grades of the catalog by energy. Shown only when the server has a catalog (FuelStat/fuelstat#140).
    @ViewBuilder
    private var fuelGradesSection: some View {
        if let catalog, let selection = fuels {
            Section {
                ForEach(catalog.fuels) { option in
                    Button {
                        fuels?.toggle(option.key)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: option.name)
                                    .foregroundStyle(.primary)
                                Text(verbatim: catalog.energyName(option.energy))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selection.isSelected(option.key) {
                                Image(systemName: "checkmark").foregroundStyle(Theme.brand)
                            }
                        }
                    }
                    .accessibilityAddTraits(selection.isSelected(option.key) ? [.isSelected] : [])
                }
                if selection.keys.count > 1 {
                    Picker("Standard für neue Einträge", selection: Binding(
                        get: { selection.defaultKey ?? "" },
                        set: { fuels?.setDefault($0) }
                    )) {
                        ForEach(selection.keys, id: \.self) { key in
                            Text(verbatim: catalog.fuel(key)?.name ?? key).tag(key)
                        }
                    }
                }
            } header: {
                Text("Kraftstoffsorten")
            } footer: {
                Text("Mehrere Sorten sind z. B. bei Benzin und Autogas oder Diesel und Premium-Diesel sinnvoll; beim Tanken wählst du die Sorte. Welche Sorten zur Antriebsart passen, prüft der Server.")
            }
            .listRowBackground(Theme.card)
        }
    }

    /// Takes the server's suggestion for the drive type, as the API would do on its own. Only called when the
    /// user changes the drive type, or once the catalog arrives for a new vehicle.
    private func suggestFuels(onlyIfMissing: Bool = false) {
        guard let catalog else { return }
        if onlyIfMissing, fuels != nil { return }
        // Back to the saved vehicle's own grades when the drive type is switched back.
        if let vehicle = editing, fuelType == vehicle.fuelType, !vehicle.fuels.isEmpty {
            fuels = FuelSelection(keys: vehicle.fuels, defaultKey: vehicle.defaultFuel)
            return
        }
        let keys = catalog.defaults[fuelType.rawValue] ?? []
        fuels = keys.isEmpty ? nil : FuelSelection(keys: keys, defaultKey: keys.first)
    }

    // MARK: Fields

    /// Field with a visible label on the left; the prompt is only an example.
    private func textRow(_ title: LocalizedStringKey, prompt: LocalizedStringKey, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField(title, text: text, prompt: Text(prompt))
                .multilineTextAlignment(.trailing)
        }
    }

    private func numberField(_ title: LocalizedStringKey, unit: String, value: Binding<Double?>) -> some View {
        LabeledContent(title) {
            HStack(spacing: Theme.Spacing.xxs) {
                TextField(title, value: value, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                Text(unit)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    private func integerField(_ title: LocalizedStringKey, unit: String, value: Binding<Int?>,
                              prompt: String) -> some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.xxs) {
                TextField(title, value: value, format: .number.grouping(.never), prompt: Text(verbatim: prompt))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                Text(verbatim: unit)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        } label: {
            Text(title)
        }
        .accessibilityElement(children: .combine)
    }

    private func monthPicker(_ title: LocalizedStringKey, selection: Binding<Int?>) -> some View {
        Picker(title, selection: selection) {
            Text("Nicht angegeben").tag(Int?.none)
            ForEach(1...12, id: \.self) { month in
                Text(verbatim: Calendar.current.monthSymbols[month - 1]).tag(Int?.some(month))
            }
        }
    }

    // MARK: Save

    private func save() {
        // Only grades the user changed are sent; otherwise the API keeps or suggests its own.
        let baselineKeys = editing?.fuels ?? catalog?.defaults[fuelType.rawValue] ?? []
        let changed = fuels.map { $0.differs(from: baselineKeys, defaultKey: editing?.defaultFuel) } ?? false
        let input = VehicleInput(
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
            batteryCapacity: fuelType.hasSeparateBattery ? batteryCapacity : nil,
            purchaseDate: hasPurchaseDate ? Self.apiDate(purchaseDate) : nil,
            purchasePrice: purchasePrice,
            saleDate: hasSaleDate ? Self.apiDate(saleDate) : nil,
            salePrice: salePrice,
            serviceIntervalMonths: serviceIntervalMonths,
            serviceIntervalKm: serviceIntervalKm,
            oilIntervalMonths: oilIntervalMonths,
            oilIntervalKm: oilIntervalKm,
            insuranceCompany: Self.nonEmpty(insuranceCompany),
            insurancePremium: insurancePremium,
            insuranceDueMonth: insuranceDueMonth,
            taxAmount: taxAmount,
            taxDueMonth: taxDueMonth,
            tireSizeSummer: Self.nonEmpty(tireSizeSummer),
            tireSizeWinter: Self.nonEmpty(tireSizeWinter),
            fuels: changed ? fuels?.keys : nil,
            defaultFuel: changed ? fuels?.defaultKey : nil
        )
        errorMessage = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                if let editing {
                    try await store.update(editing.id, input)
                } else {
                    try await store.create(input)
                }
                dismiss()
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

    /// `YYYY-MM-DD` as a date at noon in the user's time zone, so the date picker shows the same day.
    private static func parseAPIDate(_ text: String) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}

#Preview {
    RemoteVehicleFormView(store: VehicleStore(auth: AuthSession()))
        .environment(AuthSession())
}

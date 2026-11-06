import FuelstatCore
import SwiftUI

/// Sheet to record a fill-up or charging session, built for use at the pump.
///
/// Defaults: the vehicle of the last fill-up, now, a full tank and the price of the last fill-up. Amount, price per
/// unit and total: whichever two were entered last determine the third. For petrol and diesel, nearby stations with
/// current prices come from Tankerkönig via the Fuelstat API.
struct FillupEntryView: View {
    let store: VehicleStore

    @Environment(\.dismiss) private var dismiss

    @State private var vehicleID: String
    @State private var unit: String = "l"
    @State private var filledAt = Date.now
    @State private var odometerKm: Int?
    @State private var values = FillupAmounts()
    @State private var isFull = true
    @State private var skipPrevious = false
    @State private var station = ""

    @State private var showingStations = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var warnings: [String] = []

    @FocusState private var focusedField: FillupAmounts.Field?

    init(store: VehicleStore, vehicleID: String? = nil) {
        self.store = store
        _vehicleID = State(initialValue: vehicleID ?? store.lastUsedVehicleID ?? "")
    }

    private var vehicle: RemoteVehicle? { store.vehicle(vehicleID) }

    private var unitLabel: String {
        switch unit {
        case "kwh": "kWh"
        case "kg": "kg"
        default: "L"
        }
    }

    private var isCharging: Bool { unit == "kwh" }

    private var stationSearchType: String? { vehicle?.fuelType.stationSearchType(unit: unit) }

    /// Rules as in the web app: a positive amount, a total (0 for free charging), a plausible date.
    private var validationMessage: String? {
        guard vehicle != nil else { return String(localized: "Bitte wähle ein Fahrzeug.") }
        guard let amount = values.amount, amount > 0 else { return nil }
        if amount > 2000 { return String(localized: "Die Menge ist ungewöhnlich groß.") }
        if let total = values.total, total < 0 { return String(localized: "Der Betrag darf nicht negativ sein.") }
        if filledAt > Date.now.addingTimeInterval(10 * 60) {
            return String(localized: "Das Datum liegt in der Zukunft.")
        }
        return nil
    }

    private var canSave: Bool {
        vehicle != nil && (values.amount ?? 0) > 0 && values.total != nil && validationMessage == nil && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                vehicleSection
                amountSection
                stationSection
                detailsSection

                if let message = validationMessage ?? errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isCharging ? "Laden erfassen" : "Tanken erfassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Sichern", action: save).disabled(!canSave)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { focusedField = nil }
                }
            }
            .interactiveDismissDisabled(isSaving || values.amount != nil)
            .task(id: "\(vehicleID)-\(unit)") { await vehicleChanged() }
            .sheet(isPresented: $showingStations) {
                if let type = stationSearchType {
                    StationPickerView(store: store, type: type) { picked, price in
                        station = picked.label
                        if let price { values.set(.pricePerUnit, to: price) }
                    }
                }
            }
            .alert("Gespeichert, bitte prüfen", isPresented: Binding(
                get: { !warnings.isEmpty },
                set: { shown in
                    if !shown {
                        warnings = []
                        dismiss()
                    }
                }
            )) {
                Button("OK") {}
            } message: {
                Text(warnings.joined(separator: "\n"))
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var vehicleSection: some View {
        Section {
            if store.vehicles.count > 1 {
                Picker("Fahrzeug", selection: $vehicleID) {
                    ForEach(store.vehicles) { Text($0.name).tag($0.id) }
                }
            } else if let vehicle {
                LabeledContent("Fahrzeug", value: vehicle.name)
            }
            if let vehicle, vehicle.fuelType.fillupUnits.count > 1 {
                Picker("Art", selection: $unit) {
                    Text("Tanken").tag("l")
                    Text("Laden").tag("kwh")
                }
                .pickerStyle(.segmented)
            }
            DatePicker("Datum", selection: $filledAt, in: ...Date.now.addingTimeInterval(10 * 60))
        }
    }

    private var amountSection: some View {
        Section {
            amountField(isCharging ? "Geladen" : "Getankt", field: .amount, unit: unitLabel, digits: 2)
            amountField("Preis", field: .pricePerUnit, unit: "€/\(unitLabel)", digits: 3)
            amountField("Betrag", field: .total, unit: "€", digits: 2)
        } footer: {
            if let derived = values.derivedField {
                Text(derivedHint(derived))
            } else {
                Text("Gib zwei der drei Werte ein, der dritte wird berechnet.")
            }
        }
    }

    @ViewBuilder
    private var stationSection: some View {
        Section {
            TextField(isCharging ? "Ladestation (optional)" : "Tankstelle (optional)", text: $station)
                .textInputAutocapitalization(.words)
            if stationSearchType != nil {
                Button("Tankstellen in der Nähe", systemImage: "location") { showingStations = true }
            }
        } footer: {
            if stationSearchType != nil {
                Text("Tankstellen und Preise von Tankerkönig (CC BY 4.0).")
            }
        }
    }

    private var detailsSection: some View {
        Section {
            HStack {
                TextField("Kilometerstand (optional)", value: $odometerKm, format: .number.grouping(.automatic))
                    .keyboardType(.numberPad)
                Text("km").foregroundStyle(.secondary).accessibilityHidden(true)
            }
            Toggle(isCharging ? "Voll geladen" : "Vollgetankt", isOn: $isFull)
            Toggle("Letzten Eintrag vergessen", isOn: $skipPrevious)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let vehicle, let current = store.currentOdometer(of: vehicle) {
                    Text("Bisher: \(Fmt.kilometres(current))")
                }
                if skipPrevious {
                    Text("Der Verbrauch wird dann nicht über die Lücke hinweg berechnet.")
                }
            }
        }
    }

    private func amountField(_ title: LocalizedStringKey, field: FillupAmounts.Field, unit: String, digits: Int)
        -> some View {
        let binding = Binding<Double?>(
            get: { value(of: field) },
            set: { values.set(field, to: $0) }
        )
        return HStack {
            Text(title)
            TextField(title, value: binding, format: .number.precision(.fractionLength(0...digits)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: field)
                .foregroundStyle(values.derivedField == field ? .secondary : .primary)
                .accessibilityLabel(title)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .leading)
                .accessibilityHidden(true)
        }
    }

    private func value(of field: FillupAmounts.Field) -> Double? {
        switch field {
        case .amount: values.amount
        case .pricePerUnit: values.pricePerUnit
        case .total: values.total
        }
    }

    private func derivedHint(_ field: FillupAmounts.Field) -> String {
        switch field {
        case .amount: String(localized: "Die Menge wird aus Betrag und Preis berechnet.")
        case .pricePerUnit: String(localized: "Der Preis wird aus Menge und Betrag berechnet.")
        case .total: String(localized: "Der Betrag wird aus Menge und Preis berechnet.")
        }
    }

    // MARK: - Actions

    /// New vehicle or fuelling/charging: pick a fitting unit and prefill the last price.
    private func vehicleChanged() async {
        guard let vehicle else { return }
        let units = vehicle.fuelType.fillupUnits
        if !units.contains(unit) {
            unit = units[0]
            return // runs again for the new unit
        }
        // A price for litres does not fit kWh: start over unless amount or total were already typed.
        if values.entered.allSatisfy({ $0 == .pricePerUnit }) {
            values = FillupAmounts()
        }
        let before = values
        guard let price = await store.lastPrice(of: vehicle.id, unit: unit) else { return }
        // Only if the user has not typed a price in the meantime.
        if values == before, !values.entered.contains(.pricePerUnit) {
            values.set(.pricePerUnit, to: (price * 1000).rounded() / 1000)
        }
    }

    private func save() {
        focusedField = nil
        guard let amount = values.amount, let total = values.total else { return }
        let input = FillupInput(
            vehicleId: vehicleID,
            unit: unit,
            amount: amount,
            totalCostEur: total,
            odometerKm: odometerKm,
            station: station.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil : station.trimmingCharacters(in: .whitespaces),
            filledAt: filledAt,
            isFull: isFull,
            skipPrevious: skipPrevious
        )
        errorMessage = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let messages = try await store.addFillup(input)
                if messages.isEmpty {
                    dismiss()
                } else {
                    warnings = messages
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Nearby stations with their current price for the vehicle's fuel type.
private struct StationPickerView: View {
    let store: VehicleStore
    let type: String
    var onPick: (RemoteStation, Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var location = LocationProvider()
    @State private var stations: [RemoteStation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(stations) { station in
                    Button {
                        onPick(station, station.price(for: type))
                        dismiss()
                    } label: {
                        StationRow(station: station, price: station.price(for: type))
                    }
                    .foregroundStyle(.primary)
                }
                if !stations.isEmpty {
                    Section {
                        Link("Daten: Tankerkönig, CC BY 4.0", destination: URL(string: "https://www.tankerkoenig.de")!)
                            .font(.footnote)
                    }
                }
            }
            .overlay {
                if isLoading {
                    ProgressView("Suche Tankstellen …")
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Keine Tankstellen", systemImage: "fuelpump.slash")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Erneut versuchen") { Task { await load() } }
                    }
                } else if stations.isEmpty {
                    ContentUnavailableView("Keine Tankstellen im Umkreis von 5 km", systemImage: "fuelpump")
                }
            }
            .navigationTitle("In der Nähe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = stations.isEmpty
        errorMessage = nil
        defer { isLoading = false }
        do {
            let here = try await location.currentLocation()
            stations = try await store.stations(near: here.coordinate.latitude, here.coordinate.longitude, type: type)
        } catch is CancellationError {
            return
        } catch APIError.server(code: "http_404", _) {
            // Server without the stations endpoint (older Fuelstat version)
            errorMessage = String(localized: "Die Tankstellensuche ist auf diesem Server nicht eingerichtet.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct StationRow: View {
    let station: RemoteStation
    let price: Double?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(station.brand ?? station.name).font(.headline)
                Text(station.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if let distance = station.distanceKm {
                        Text(distance.formatted(.number.precision(.fractionLength(1))) + " km")
                    }
                    if !station.isOpen {
                        Text("geschlossen").foregroundStyle(.orange)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let price {
                Text(price.formatted(.currency(code: "EUR").precision(.fractionLength(3))))
                    .font(.headline)
                    .monospacedDigit()
            } else {
                Text("–").foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

import FuelstatCore
import SwiftUI

/// Quick-entry sheet for a fill-up or charging session, built for use at the pump.
///
/// Defaults: the selected vehicle (or the one of the last fill-up), now, a full tank and the price of the last
/// fill-up. Amount, price per unit and total: whichever two were entered last determine the third. For petrol and
/// diesel, nearby stations with current prices come from Tankerkönig via the Fuelstat API.
struct FillupEntryView: View {
    let store: VehicleStore

    @Environment(\.dismiss) private var dismiss

    @State private var vehicleID: String
    @State private var unit: String
    @State private var filledAt = Date.now
    @State private var odometerKm: Int?
    @State private var values = FillupAmounts()
    @State private var isFull = true
    @State private var skipPrevious = false
    @State private var station = ""
    @State private var selectedStationID: String?

    @State private var location = LocationProvider()
    @State private var nearby: [RemoteStation] = []
    @State private var nearbyMessage: String?
    @State private var isSearchingNearby = false
    @State private var recentStations: [String] = []

    @State private var showingStations = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var warnings: [String] = []

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case amount(FillupAmounts.Field)
        case odometer
        case station
    }

    init(store: VehicleStore, vehicleID: String? = nil, kind: EntryKind? = nil) {
        self.store = store
        _vehicleID = State(initialValue: vehicleID ?? store.lastUsedVehicleID ?? "")
        _unit = State(initialValue: kind?.rawValue ?? "l")
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

    /// Nearby stations, the ones used recently first.
    private var sortedNearby: [RemoteStation] {
        let recent = Set(recentStations)
        return nearby.enumerated().sorted { lhs, rhs in
            let l = recent.contains(lhs.element.label), r = recent.contains(rhs.element.label)
            return l != r ? l : lhs.offset < rhs.offset
        }.map(\.element)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    typeAndVehicle
                    stationSection
                    amountSection
                    fullChips
                    detailsSection

                    if let message = validationMessage ?? errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.Status.overdue)
                    }
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.vertical, Theme.Spacing.m)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Speichern", isLoading: isSaving, action: save)
                    .disabled(!canSave)
                    .padding(.horizontal, Theme.Spacing.screen)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(.bar)
            }
            .navigationTitle(isCharging ? "Laden erfassen" : "Tanken erfassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
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
                        pick(picked, price: price)
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
    private var typeAndVehicle: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let vehicle, vehicle.fuelType.fillupUnits.count > 1 {
                HStack(spacing: Theme.Spacing.xs) {
                    typeChip("Tanken", systemImage: "fuelpump.fill", unit: vehicle.fuelType.fillupUnits[0])
                    typeChip("Laden", systemImage: "bolt.fill", unit: "kwh")
                }
            }
            if store.vehicles.count > 1 {
                CardContainer(padding: Theme.Spacing.s) {
                    Picker("Fahrzeug", selection: $vehicleID) {
                        ForEach(store.vehicles) { Text($0.name).tag($0.id) }
                    }
                    .tint(Theme.brand)
                }
            } else if let vehicle {
                Label(vehicle.name, systemImage: "car.side")
                    .font(.headline)
                    .foregroundStyle(Theme.brandDeep)
            }
        }
    }

    private func typeChip(_ title: LocalizedStringKey, systemImage: String, unit value: String) -> some View {
        Button {
            Haptics.selection()
            unit = value
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(unit == value ? Theme.onBrand : Theme.brandDeep)
                .background(unit == value ? Theme.brand : Theme.cardTint, in: .tile)
                .contentShape(.tile)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(unit == value ? [.isSelected] : [])
    }

    @ViewBuilder
    private var stationSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if stationSearchType != nil {
                SectionHeader(title: "Tankstellen in der Nähe",
                              action: nearby.isEmpty ? nil : { showingStations = true })
                nearbyCards
            }

            if !recentStations.isEmpty && (stationSearchType == nil || nearby.isEmpty) {
                Text("Zuletzt genutzt")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(recentStations, id: \.self) { name in
                            FilterChip(verbatim: name, isSelected: station == name) {
                                station = name
                                selectedStationID = nil
                            }
                        }
                    }
                }
                .scrollClipDisabled()
            }

            fieldLabel(isCharging ? "Ladestation (optional)" : "Tankstelle (optional)")
            TextField(isCharging ? "Ladestation" : "Tankstelle", text: $station)
                .textInputAutocapitalization(.words)
                .focused($focusedField, equals: .station)
                .padding(Theme.Spacing.s)
                .background(Theme.card, in: .tile)
                .accessibilityLabel(isCharging ? "Ladestation" : "Tankstelle")
                .onChange(of: station) {
                    if let id = selectedStationID, nearby.first(where: { $0.id == id })?.label != station {
                        selectedStationID = nil
                    }
                }

            if stationSearchType != nil, !nearby.isEmpty {
                Link("Daten: Tankerkönig, CC BY 4.0", destination: URL(string: "https://www.tankerkoenig.de")!)
                    .font(.footnote)
                    .foregroundStyle(Theme.brand)
            }
        }
    }

    @ViewBuilder
    private var nearbyCards: some View {
        if isSearchingNearby && nearby.isEmpty {
            HStack(spacing: Theme.Spacing.xs) {
                ProgressView()
                Text("Suche Tankstellen …").foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(Theme.card, in: .tile)
        } else if nearby.isEmpty {
            Button {
                Task { await searchNearby(asking: true) }
            } label: {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Label("Tankstellen mit Preisen suchen", systemImage: "location.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.brand)
                    if let nearbyMessage {
                        Text(nearbyMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(Theme.Spacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: .tile)
            }
            .buttonStyle(.plain)
        } else if let type = stationSearchType {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(sortedNearby.prefix(10)) { candidate in
                        StationCard(station: candidate, price: candidate.price(for: type),
                                    isSelected: candidate.id == selectedStationID,
                                    isRecent: recentStations.contains(candidate.label)) {
                            pick(candidate, price: candidate.price(for: type))
                        }
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            amountField(isCharging ? "Geladen" : "Getankt", field: .amount, unit: unitLabel, digits: 2)
            HStack(spacing: Theme.Spacing.xs) {
                amountField("Preis", field: .pricePerUnit, unit: "€/\(unitLabel)", digits: 3)
                amountField("Betrag", field: .total, unit: "€", digits: 2)
            }
            Text(values.derivedField.map(derivedHint)
                 ?? String(localized: "Gib zwei der drei Werte ein, der dritte wird berechnet."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var fullChips: some View {
        HStack(spacing: Theme.Spacing.xs) {
            FilterChip(title: isCharging ? "Voll geladen" : "Vollgetankt", systemImage: "gauge.with.needle.fill",
                       isSelected: isFull) { isFull = true }
            FilterChip(title: isCharging ? "Teilladung" : "Teilbetankung", systemImage: "gauge.with.needle",
                       isSelected: !isFull) { isFull = false }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            fieldLabel("Kilometerstand (optional)")
            HStack {
                TextField("Kilometerstand", value: $odometerKm, format: .number.grouping(.automatic))
                    .keyboardType(.numberPad)
                    .font(.title3.weight(.semibold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .focused($focusedField, equals: .odometer)
                    .accessibilityLabel("Kilometerstand")
                Text("km").foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .padding(Theme.Spacing.s)
            .background(Theme.card, in: .tile)
            if let hint = odometerHint {
                Label(hint, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.Status.soon)
            } else if let vehicle, let current = store.currentOdometer(of: vehicle) {
                Text("Bisher: \(Fmt.kilometres(current))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            CardContainer(padding: Theme.Spacing.s) {
                VStack(spacing: Theme.Spacing.s) {
                    DatePicker("Datum", selection: $filledAt, in: ...Date.now.addingTimeInterval(10 * 60))
                    Divider()
                    Toggle("Letzten Eintrag vergessen", isOn: $skipPrevious)
                        .tint(Theme.brand)
                }
            }
            if skipPrevious {
                Text("Der Verbrauch wird dann nicht über die Lücke hinweg berechnet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Inline hint before saving; the API checks plausibility itself and answers with warnings after saving.
    private var odometerHint: String? {
        guard let entered = odometerKm, let vehicle, let current = store.currentOdometer(of: vehicle),
              Double(entered) < current else { return nil }
        return String(localized: "Niedriger als der bisherige Stand von \(Fmt.kilometres(current)).")
    }

    private func fieldLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private func amountField(_ title: LocalizedStringKey, field: FillupAmounts.Field, unit: String, digits: Int)
        -> some View {
        let binding = Binding<Double?>(
            get: { value(of: field) },
            set: { values.set(field, to: $0) }
        )
        let isDerived = values.derivedField == field
        return VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack(spacing: Theme.Spacing.xxs) {
                Text(title)
                if isDerived {
                    Image(systemName: "function").accessibilityLabel("berechnet")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xxs) {
                TextField(title, value: binding, format: .number.precision(.fractionLength(0...digits)))
                    .keyboardType(.decimalPad)
                    .font(.title.bold())
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(isDerived ? Color.secondary : Theme.brandDeep)
                    .focused($focusedField, equals: .amount(field))
                    .accessibilityLabel(title)
                Text(unit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(Theme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .tile)
        .overlay {
            if focusedField == .amount(field) {
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .strokeBorder(Theme.brand, lineWidth: 2)
            }
        }
        .contentShape(.tile)
        .onTapGesture { focusedField = .amount(field) }
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

    private func pick(_ picked: RemoteStation, price: Double?) {
        selectedStationID = picked.id
        station = picked.label
        if let price { values.set(.pricePerUnit, to: price) }
        Haptics.selection()
    }

    /// New vehicle or fuelling/charging: pick a fitting unit, prefill the last price, load stations.
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
        nearby = []
        selectedStationID = nil
        async let stationsLoaded: Void = searchNearby(asking: false)
        async let recentLoaded: Void = loadRecentStations(vehicle.id)
        let before = values
        let price = await store.lastPrice(of: vehicle.id, unit: unit)
        // Only if the user has not typed a price in the meantime.
        if let price, values == before, !values.entered.contains(.pricePerUnit) {
            values.set(.pricePerUnit, to: (price * 1000).rounded() / 1000)
        }
        _ = await (stationsLoaded, recentLoaded)
    }

    /// Without `asking`, only searches when location access was already granted, so opening the sheet never
    /// starts with a permission prompt.
    private func searchNearby(asking: Bool) async {
        guard let type = stationSearchType, asking || location.isAuthorized else { return }
        isSearchingNearby = true
        nearbyMessage = nil
        defer { isSearchingNearby = false }
        do {
            let here = try await location.currentLocation()
            nearby = try await store.stations(near: here.coordinate.latitude, here.coordinate.longitude, type: type)
            if nearby.isEmpty { nearbyMessage = String(localized: "Keine Tankstellen im Umkreis von 5 km.") }
        } catch is CancellationError {
            return
        } catch APIError.server(code: "http_404", _) {
            nearbyMessage = String(localized: "Die Tankstellensuche ist auf diesem Server nicht eingerichtet.")
        } catch {
            nearbyMessage = error.localizedDescription
        }
    }

    private func loadRecentStations(_ id: String) async {
        guard let recent = try? await store.fillups(of: id, limit: 20) else { return }
        var seen = Set<String>()
        recentStations = recent
            .filter { ($0.unit == "kwh") == isCharging }
            .compactMap(\.station)
            .filter { seen.insert($0).inserted }
            .prefix(5)
            .map { $0 }
    }

    private func save() {
        focusedField = nil
        guard canSave, let amount = values.amount, let total = values.total else { return }
        let trimmed = station.trimmingCharacters(in: .whitespaces)
        let input = FillupInput(
            vehicleId: vehicleID,
            unit: unit,
            amount: amount,
            totalCostEur: total,
            odometerKm: odometerKm,
            station: trimmed.isEmpty ? nil : trimmed,
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
                    Haptics.success()
                    dismiss()
                } else {
                    Haptics.warning()
                    warnings = messages
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Nearby station as a horizontal card: name, distance and price; the selected one is highlighted.
private struct StationCard: View {
    let station: RemoteStation
    let price: Double?
    let isSelected: Bool
    let isRecent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.xxs) {
                    Text(station.brand ?? station.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if isRecent {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption)
                            .accessibilityLabel("zuletzt genutzt")
                    }
                }
                Text(price.map { Fmt.pricePerUnit($0) } ?? "–")
                    .font(.title3.bold())
                    .fontDesign(.rounded)
                    .monospacedDigit()
                HStack(spacing: Theme.Spacing.xxs) {
                    if let km = station.distanceKm {
                        Text("\(km.formatted(.number.precision(.fractionLength(1)))) km")
                    }
                    if !station.isOpen {
                        Text("geschlossen")
                    }
                }
                .font(.footnote)
                .opacity(0.85)
            }
            .foregroundStyle(isSelected ? Theme.onBrand : Theme.brandDeep)
            .padding(Theme.Spacing.s)
            .frame(width: 150, alignment: .leading)
            .background(isSelected ? Theme.brand : Theme.card, in: .tile)
            .contentShape(.tile)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Nearby stations with their current price for the vehicle's fuel type.
struct StationPickerView: View {
    let store: VehicleStore
    let type: String
    /// Called with the chosen station; nil shows the list for browsing only.
    var onPick: ((RemoteStation, Double?) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var location = LocationProvider()
    @State private var stations: [RemoteStation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(stations) { station in
                    Group {
                        if let onPick {
                            Button {
                                onPick(station, station.price(for: type))
                                dismiss()
                            } label: {
                                StationRow(station: station, price: station.price(for: type))
                            }
                            .foregroundStyle(.primary)
                        } else {
                            StationRow(station: station, price: station.price(for: type))
                        }
                    }
                    .listRowBackground(Theme.card)
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
            .themedBackground()
            .navigationTitle("In der Nähe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(onPick == nil ? "Schließen" : "Abbrechen") { dismiss() }
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
                        Text("geschlossen").foregroundStyle(Theme.Status.overdue)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let price {
                Text(price.formatted(.currency(code: "EUR").precision(.fractionLength(3))))
                    .font(.headline)
                    .fontDesign(.rounded)
                    .foregroundStyle(Theme.brand)
                    .monospacedDigit()
            } else {
                Text("–").foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

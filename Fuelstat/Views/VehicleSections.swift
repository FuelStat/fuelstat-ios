import Charts
import CoreLocation
import MapKit
import SwiftUI

/// Building blocks shared by Start, the vehicle page and Statistik. All figures come from the API.

// MARK: - Key figures

struct KeyFigureTiles: View {
    let vehicle: RemoteVehicle
    let stats: VehicleStats?
    let odometer: Double?
    /// Names of the energies; needed to list them for vehicles with several (FuelStat/fuelstat#140).
    var catalog: FuelCatalog?

    private var unit: String { vehicle.fuelType.tankCapacityUnit }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            StatTileRow {
                StatTile(label: "Ø Verbrauch",
                         value: stats?.averageConsumption.map { Fmt.number($0, digits: 1) },
                         unit: "\(unit)/100 km")
                StatTile(label: "Zuletzt",
                         value: stats?.trend.map { Fmt.number($0.current, digits: 1) },
                         unit: "\(unit)/100 km",
                         trend: stats?.trend.flatMap { $0.diff == 0 ? nil : ($0.diff < 0 ? .better : .worse) })
                StatTile(label: "Ø Preis",
                         value: stats?.averagePricePerUnit.map { $0.formatted(.number.precision(.fractionLength(3))) },
                         unit: "€/\(unit)")
            }
            if let energies = stats?.energies, energies.count > 1 {
                EnergyFiguresCard(energies: energies, catalog: catalog)
            }
            if stats?.averageConsumption == nil {
                Text("Der Verbrauch erscheint nach den ersten vollen Tankfüllungen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if let missing = stats?.missingOdometer, missing > 0 {
                Text("\(missing) Einträge ohne Kilometerstand zählen nicht für den Verbrauch.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Consumption and price per energy for vehicles with several, e.g. petrol and LPG or petrol and electricity.
/// Energies fuelled only on the side get no consumption figure, as the API marks them (`minor`).
struct EnergyFiguresCard: View {
    let energies: [String: VehicleStats.EnergyFigures]
    let catalog: FuelCatalog?

    /// The order of the catalog (petrol, diesel, LPG, CNG, electricity …), unknown ones last.
    private var keys: [String] {
        let order = catalog?.energies.map(\.key) ?? []
        return energies.keys.sorted { (order.firstIndex(of: $0) ?? .max, $0) < (order.firstIndex(of: $1) ?? .max, $1) }
    }

    var body: some View {
        CardContainer(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(keys.enumerated()), id: \.element) { index, key in
                    if index > 0 { Divider().padding(.leading, Theme.Spacing.cardPadding) }
                    if let figures = energies[key] { row(key, figures) }
                }
            }
        }
    }

    private func row(_ key: String, _ figures: VehicleStats.EnergyFigures) -> some View {
        let unit = Self.unitLabel(figures.unit)
        return HStack(alignment: .firstTextBaseline) {
            Text(verbatim: catalog?.energyName(key) ?? key)
                .font(.body.weight(.medium))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if figures.minor {
                    Text("nur nebenbei getankt")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(verbatim: figures.averageConsumption.map { "Ø \(Fmt.number($0, digits: 1)) \(unit)/100 km" } ?? "–")
                        .font(.body.weight(.semibold))
                }
                if let price = figures.averagePrice {
                    Text(verbatim: "Ø \(price.formatted(.number.precision(.fractionLength(3)))) €/\(unit)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, Theme.Spacing.s)
        .accessibilityElement(children: .combine)
    }

    static func unitLabel(_ unit: String) -> String {
        switch unit {
        case "kwh": "kWh"
        case "kg": "kg"
        default: "L"
        }
    }
}

// MARK: - Reminders

struct RemindersCard: View {
    let reminders: [RemoteReminder]
    var limit = 3
    var onShowAll: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title: "Nächste Termine", action: reminders.count > limit ? onShowAll : nil)
            CardContainer(padding: 0) {
                VStack(spacing: 0) {
                    if reminders.isEmpty {
                        Text("Keine Termine. Sie ergeben sich aus Erstzulassung und Ausgaben wie TÜV oder Wartung.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(Theme.Spacing.cardPadding)
                    }
                    ForEach(Array(reminders.prefix(limit).enumerated()), id: \.element.id) { index, reminder in
                        if index > 0 { Divider().padding(.leading, Theme.Spacing.m + Theme.iconCircle + Theme.Spacing.s) }
                        ReminderRow(reminder: reminder)
                            .padding(.horizontal, Theme.Spacing.cardPadding)
                            .padding(.vertical, Theme.Spacing.s)
                    }
                }
            }
        }
    }
}

struct ReminderRow: View {
    let reminder: RemoteReminder

    @ScaledMetric(relativeTo: .body) private var circle = Theme.iconCircle

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: reminder.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.brand)
                .frame(width: circle, height: circle)
                .background(Theme.cardTint, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title).font(.body.weight(.medium))
                if let due = dueText {
                    Text(due)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let last = lastText {
                    Text(last)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: Theme.Spacing.xs)
            // Info rows (e.g. tyres) have no due date and therefore no status (FuelStat/fuelstat#172).
            if !reminder.isInfo {
                StatusBadge(status: reminder.status.badge)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Due date and/or distance; without any (status `unbekannt`, e.g. TÜV without an entry) a request to record
    /// the last one, so the API can work out the next.
    private var dueText: String? {
        if reminder.isInfo {
            return reminder.lastDate == nil ? String(localized: "\(reminder.title) erfassen") : nil
        }
        var parts: [String] = []
        if let date = reminder.dueDate { parts.append(APIDate.formatDay(date)) }
        if let km = reminder.dueKm { parts.append(Fmt.kilometres(km)) }
        if parts.isEmpty, reminder.status == .unknown { return String(localized: "Letzten Termin erfassen") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "zuletzt am 3. Mai 2026 bei 45.000 km · Winterreifen"
    private var lastText: String? {
        guard let date = reminder.lastDate else { return nil }
        var text = String(localized: "zuletzt am \(APIDate.formatDay(date))")
        if let km = reminder.lastOdometerKm { text += " " + String(localized: "bei \(Fmt.kilometres(km))") }
        if let note = reminder.lastDescription { text += " · " + note }
        return text
    }
}

extension RemoteReminder.Status {
    var badge: StatusBadge.Status {
        switch self {
        case .ok: .ok
        case .soon: .soon
        case .overdue: .overdue
        case .unknown: .unknown
        }
    }
}

/// All due dates of a vehicle. Tapping one records the matching expense (e.g. the TÜV that was just done); the
/// API then calculates the next due date from it.
struct RemindersListView: View {
    let store: VehicleStore
    let vehicleID: String

    @State private var reminders: [RemoteReminder] = []
    @State private var errorMessage: String?
    @State private var completing: RemoteReminder?

    private var canRecord: Bool { store.vehicle(vehicleID)?.role.canRecord ?? true }

    var body: some View {
        List {
            Section {
                ForEach(reminders) { reminder in
                    if canRecord {
                        Button { completing = reminder } label: {
                            ReminderRow(reminder: reminder)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("Trägt den Termin als erledigt ein"))
                    } else {
                        ReminderRow(reminder: reminder)
                    }
                }
            } footer: {
                if canRecord, !reminders.isEmpty {
                    Text("Tippe auf einen Termin, um ihn als erledigt einzutragen. Der nächste Termin ergibt sich daraus.")
                }
            }
            .listRowBackground(Theme.card)
        }
        .themedBackground()
        .overlay {
            if let errorMessage {
                ContentUnavailableView("Termine nicht verfügbar", systemImage: "calendar.badge.exclamationmark",
                                       description: Text(errorMessage))
            }
        }
        .navigationTitle("Termine")
        .refreshable { await load() }
        .task(id: store.entryChanges) { await load() }
        .sheet(item: $completing) { reminder in
            ExpenseFormView(store: store, vehicleID: vehicleID, category: reminder.category)
        }
    }

    private func load() async {
        do {
            reminders = try await store.reminders(of: vehicleID)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Entries

/// A fill-up or charging session as an `EntryRow`.
struct FillupEntryRow: View {
    let fillup: RemoteFillup
    let fuelType: RemoteFuelType

    var body: some View {
        EntryRow(
            systemImage: fillup.isCharging ? "bolt.fill" : "fuelpump.fill",
            tint: fillup.isCharging ? Theme.Energy.electricity : fuelType.energyColor,
            title: fillup.station ?? (fillup.isCharging ? String(localized: "Laden") : String(localized: "Tanken")),
            subtitle: subtitle,
            amount: fillup.totalCostEur.map { $0.formatted(.currency(code: "EUR")) },
            detail: "\(Fmt.number(fillup.amount, digits: 2)) \(fillup.unitLabel)",
            badge: fillup.isFull ? nil : "Teil"
        )
    }

    private var subtitle: String {
        var parts: [String] = []
        if let date = fillup.filledAt { parts.append(date.formatted(.dateTime.day().month(.abbreviated))) }
        if let km = fillup.odometerKm { parts.append(Fmt.kilometres(km)) }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }
}

struct RecentEntriesCard: View {
    let fillups: [RemoteFillup]
    let fuelType: RemoteFuelType
    var onShowAll: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title: "Letzte Einträge", action: fillups.isEmpty ? nil : onShowAll)
            CardContainer(padding: 0) {
                VStack(spacing: 0) {
                    if fillups.isEmpty {
                        Text("Noch keine Tank- oder Ladevorgänge.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(Theme.Spacing.cardPadding)
                    }
                    ForEach(Array(fillups.enumerated()), id: \.element.id) { index, fillup in
                        if index > 0 { Divider().padding(.leading, Theme.Spacing.m + Theme.iconCircle + Theme.Spacing.s) }
                        FillupEntryRow(fillup: fillup, fuelType: fuelType)
                            .padding(.horizontal, Theme.Spacing.cardPadding)
                            .padding(.vertical, Theme.Spacing.s)
                    }
                }
            }
        }
    }
}

// MARK: - Consumption chart

/// Consumption per full-to-full segment, as calculated by the API.
struct ConsumptionChartCard: View {
    enum Range: Hashable {
        case sixMonths, year, all
    }

    let stats: VehicleStats?
    let fuelType: RemoteFuelType
    @Binding var range: Range
    var catalog: FuelCatalog?

    /// One chart per energy (petrol and LPG separately, FuelStat/fuelstat#140), or per unit on older servers.
    /// Energies fuelled only on the side are left out, as the API marks them.
    private var series: [String] {
        var seen: [String] = []
        for segment in (stats?.segments ?? []).sorted(by: { $0.date < $1.date }) {
            let key = Self.seriesKey(segment)
            if !seen.contains(key), stats?.energies[key]?.minor != true { seen.append(key) }
        }
        let order = catalog?.energies.map(\.key) ?? fuelType.fillupUnits
        return seen.sorted { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }
    }

    private static func seriesKey(_ segment: VehicleStats.Segment) -> String { segment.energy ?? segment.unit }

    private func segments(series key: String) -> [VehicleStats.Segment] {
        let start: Date? = switch range {
        case .sixMonths: Calendar.current.date(byAdding: .month, value: -6, to: .now)
        case .year: Calendar.current.date(byAdding: .year, value: -1, to: .now)
        case .all: nil
        }
        return (stats?.segments ?? [])
            .filter { segment in Self.seriesKey(segment) == key && (start.map { segment.date >= $0 } ?? true) }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ChipGroup(options: [
                .init(value: Range.sixMonths, title: "6 Monate"),
                .init(value: Range.year, title: "Jahr"),
                .init(value: Range.all, title: "Gesamt"),
            ], selection: $range)

            if series.isEmpty {
                CardContainer {
                    Text("Für ein Diagramm braucht es mindestens zwei volle Tankfüllungen mit Kilometerstand.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(series, id: \.self) { key in
                chart(series: key)
            }
        }
    }

    private func chart(series key: String) -> some View {
        let data = segments(series: key)
        let unit = data.first?.unit ?? stats?.energies[key]?.unit ?? key
        let unitLabel = EnergyFiguresCard.unitLabel(unit)
        let color = Self.color(series: key, unit: unit, fuelType: fuelType)
        let name = series.count > 1 ? catalog?.energyName(key) : nil
        return CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Group {
                    if let name {
                        Text("Verbrauch je Tankfüllung – \(name)")
                    } else {
                        Text("Verbrauch je Tankfüllung")
                    }
                }
                .font(.headline)
                .foregroundStyle(Theme.brandDeep)
                Text("\(unitLabel)/100 km")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if data.isEmpty {
                    Text("Keine Werte in diesem Zeitraum.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Chart(data) { segment in
                        LineMark(x: .value("Datum", segment.date), y: .value("Verbrauch", segment.per100Km))
                            .foregroundStyle(color)
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Datum", segment.date), y: .value("Verbrauch", segment.per100Km))
                            .foregroundStyle(color)
                    }
                    .frame(minHeight: 180)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Verbrauch je Tankfüllung"))
                    .accessibilityValue(Text(summary(data, unit: unitLabel)))
                }
            }
        }
    }

    /// Colour of an energy; on older servers the series is a unit.
    private static func color(series key: String, unit: String, fuelType: RemoteFuelType) -> Color {
        switch key {
        case "electricity", "kwh": Theme.Energy.electricity
        case "petrol": Theme.Energy.petrol
        case "diesel": Theme.Energy.diesel
        case "lpg", "cng": Theme.Energy.gas
        case "hydrogen": Theme.Energy.hydrogen
        default: unit == "kwh" ? Theme.Energy.electricity : fuelType.energyColor
        }
    }

    private func summary(_ data: [VehicleStats.Segment], unit: String) -> String {
        guard let first = data.first, let last = data.last,
              let low = data.min(by: { $0.per100Km < $1.per100Km }),
              let high = data.max(by: { $0.per100Km < $1.per100Km }) else { return "" }
        let from = first.date.formatted(date: .abbreviated, time: .omitted)
        let to = last.date.formatted(date: .abbreviated, time: .omitted)
        return String(localized: "\(data.count) Tankfüllungen von \(from) bis \(to). Niedrigster Wert \(Fmt.number(low.per100Km, digits: 1)), höchster \(Fmt.number(high.per100Km, digits: 1)), zuletzt \(Fmt.number(last.per100Km, digits: 1)) \(unit) pro 100 km.")
    }
}

// MARK: - Nearby

/// Cheapest nearby station for the vehicle's fuel, with a small map. Only loads by itself when location access
/// was already granted; otherwise a tap asks for it.
struct NearbyCard: View {
    let store: VehicleStore
    let vehicle: RemoteVehicle
    var onOpen: () -> Void

    @State private var location = LocationProvider()
    @State private var cheapest: RemoteStation?
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var message: String?

    private var type: String? { vehicle.fuelType.stationSearchType(unit: "l") }

    var body: some View {
        if let type {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader(title: "In der Nähe")
                Button(action: onOpen) {
                    CardContainer(padding: Theme.Spacing.s) {
                        HStack(spacing: Theme.Spacing.s) {
                            thumbnail
                                .frame(width: 76, height: 76)
                                .clipShape(.tile)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                if let cheapest, let price = cheapest.price(for: type) {
                                    Text(cheapest.brand ?? cheapest.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(priceLine(price: price, station: cheapest))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.brand)
                                        .monospacedDigit()
                                    Text("Günstigste Tankstelle im Umkreis")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Tankstellen in der Nähe")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(message ?? String(localized: "Aktuelle Preise ansehen"))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.footnote.bold())
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .task(id: vehicle.id) { await load(type: type) }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let coordinate {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500
            )), interactionModes: []) {
                if let cheapest, let lat = cheapest.latitude, let lng = cheapest.longitude {
                    Marker("", systemImage: "fuelpump.fill", coordinate: .init(latitude: lat, longitude: lng))
                        .tint(Theme.brand)
                }
                UserAnnotation()
            }
        } else {
            ZStack {
                Theme.cardTint
                Image(systemName: "map")
                    .font(.title2)
                    .foregroundStyle(Theme.brand)
            }
        }
    }

    private func priceLine(price: Double, station: RemoteStation) -> String {
        let label = vehicle.fuelType == .diesel ? String(localized: "Diesel") : String(localized: "Super")
        var text = "\(label) \(Fmt.pricePerUnit(price))"
        if let km = station.distanceKm {
            text += " · " + (km < 1
                ? "\(Int((km * 1000 / 50).rounded() * 50)) m"
                : "\(km.formatted(.number.precision(.fractionLength(1)))) km")
        }
        return text
    }

    private func load(type: String) async {
        guard location.isAuthorized else { return }
        do {
            let here = try await location.currentLocation()
            coordinate = here.coordinate
            let stations = try await store.stations(near: here.coordinate.latitude, here.coordinate.longitude,
                                                    type: type)
            cheapest = stations
                .filter { $0.isOpen && $0.price(for: type) != nil }
                .min { ($0.price(for: type) ?? .infinity) < ($1.price(for: type) ?? .infinity) }
            message = cheapest == nil ? String(localized: "Keine geöffnete Tankstelle mit Preis gefunden") : nil
        } catch is CancellationError {
            return
        } catch APIError.server(code: "http_404", _) {
            message = String(localized: "Auf diesem Server nicht eingerichtet")
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Master data

struct MasterDataCards: View {
    let vehicle: RemoteVehicle
    let odometer: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
            group("Allgemein", [
                ("Kraftstoff", vehicle.fuelType.label),
                ("Marke", vehicle.brand),
                ("Modell", vehicle.model),
                ("Baujahr", vehicle.year.map(String.init)),
                ("Kilometerstand", odometer.map(Fmt.kilometres)),
            ])
            group("Zulassung", [
                ("Kennzeichen", vehicle.licensePlate),
                ("FIN", vehicle.vin),
                ("Erstzulassung", vehicle.firstRegistration.flatMap(APIDate.parseDay).map(APIDate.formatDay)),
            ])
            group("Technik", [
                ("Kilometerstand bei Anschaffung", vehicle.odometerKm.map(Fmt.kilometres)),
                (LocalizedStringKey(vehicle.fuelType.tankCapacityLabel),
                 vehicle.tankCapacity.map { "\(Fmt.number($0)) \(vehicle.fuelType.tankCapacityUnit)" }),
                ("Akkukapazität", vehicle.batteryCapacity.map { "\(Fmt.number($0)) kWh" }),
                ("Reifen Sommer", vehicle.tireSizeSummer),
                ("Reifen Winter", vehicle.tireSizeWinter),
            ])
        }
    }

    @ViewBuilder
    private func group(_ title: LocalizedStringKey, _ rows: [(LocalizedStringKey, String?)]) -> some View {
        let present = rows.compactMap { row in row.1.map { (row.0, $0) } }
        if !present.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader(title: title)
                CardContainer {
                    VStack(spacing: Theme.Spacing.s) {
                        ForEach(present.indices, id: \.self) { index in
                            if index > 0 { Divider() }
                            LabeledContent(present[index].0, value: present[index].1)
                        }
                    }
                }
            }
        }
    }
}

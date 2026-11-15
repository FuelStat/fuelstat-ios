import Charts
import FuelstatCore
import SwiftUI

/// Consumption and cost figures of Statistik (FuelStat/fuelstat `/consumption` and `/costs`, #6).
///
/// Every number comes from the API; the views only lay it out and name it. Sums and shares that the API does not
/// send are not computed here.

// MARK: - Small building blocks

/// One label/value line of a `DetailCard`.
private struct Row: Identifiable {
    let id = UUID()
    let label: Text
    let value: String
    var detail: String?

    init(_ label: LocalizedStringKey, _ value: String, detail: String? = nil) {
        self.label = Text(label)
        self.value = value
        self.detail = detail
    }

    /// For names that come from the API and must not be looked up as localization keys.
    init(verbatim label: String, _ value: String, detail: String? = nil) {
        self.label = Text(verbatim: label)
        self.value = value
        self.detail = detail
    }
}

/// Card with label/value rows separated by dividers.
private struct DetailCard: View {
    let rows: [Row]

    var body: some View {
        CardContainer(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().padding(.leading, Theme.Spacing.cardPadding) }
                    HStack(alignment: .firstTextBaseline) {
                        row.label
                            .foregroundStyle(.secondary)
                        Spacer(minLength: Theme.Spacing.s)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(verbatim: row.value)
                                .font(.body.weight(.semibold))
                                .multilineTextAlignment(.trailing)
                            if let detail = row.detail {
                                Text(verbatim: detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        .monospacedDigit()
                    }
                    .font(.body)
                    .padding(.horizontal, Theme.Spacing.cardPadding)
                    .padding(.vertical, Theme.Spacing.s)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct ChartCard<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.brandDeep)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                content
            }
        }
    }
}

private enum StatsFormat {
    static func month(_ key: String, style: Date.FormatStyle = .dateTime.month(.wide).year()) -> String {
        PeriodKey.monthStart(key).map { $0.formatted(style) } ?? key
    }

    static func shortMonth(_ key: String) -> String {
        month(key, style: .dateTime.month(.abbreviated).year(.twoDigits))
    }

    static func euro(_ value: Double?, currency: String = "EUR", digits: Int = 2) -> String {
        guard let value else { return "–" }
        return value.formatted(.currency(code: currency).precision(.fractionLength(digits)))
    }

    static func number(_ value: Double?, digits: Int = 1) -> String {
        value.map { Fmt.number($0, digits: digits) } ?? "–"
    }

    static func amount(_ value: Double?, unit: String) -> String {
        guard let value else { return "–" }
        return "\(Fmt.number(value, digits: 1)) \(EnergyFiguresCard.unitLabel(unit))"
    }

    static func percent(_ value: Double?) -> String? {
        value.map { "\(Fmt.number($0, digits: 0)) %" }
    }

    static func colour(energy: String?, unit: String, fuelType: RemoteFuelType) -> Color {
        switch energy ?? unit {
        case "electricity", "kwh": Theme.Energy.electricity
        case "petrol": Theme.Energy.petrol
        case "diesel": Theme.Energy.diesel
        case "lpg", "cng", "kg": Theme.Energy.gas
        case "hydrogen": Theme.Energy.hydrogen
        default: fuelType.energyColor
        }
    }
}

// MARK: - Consumption

struct ConsumptionDetailSection: View {
    let consumption: VehicleConsumption
    let vehicle: RemoteVehicle
    var catalog: FuelCatalog?

    private var breakdown: [(key: String, figures: VehicleConsumption.Energy)] { consumption.breakdown }

    private func name(_ key: String, _ figures: VehicleConsumption.Energy) -> String? {
        guard breakdown.count > 1 else { return nil }
        return figures.name ?? catalog?.energyName(key)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
            if let primary = consumption.primary, primary.metric == .costPer100km, let value = primary.value {
                StatTileRow {
                    StatTile(label: "Energiekosten", value: StatsFormat.number(value, digits: 2), unit: "€/100 km")
                    StatTile(label: "Energiekosten gesamt",
                             value: consumption.energyCost.map { StatsFormat.number($0, digits: 0) }, unit: "€")
                }
            }

            ForEach(breakdown, id: \.key) { entry in
                EnergyDetailCard(figures: entry.figures, title: name(entry.key, entry.figures),
                                 showShare: breakdown.count > 1)
            }

            ForEach(breakdown.filter { !$0.figures.minor && $0.figures.months.count > 1 }, id: \.key) { entry in
                MonthlyConsumptionChart(figures: entry.figures, title: name(entry.key, entry.figures),
                                        colour: StatsFormat.colour(energy: entry.figures.energy ?? entry.key,
                                                                    unit: entry.figures.unit, fuelType: vehicle.fuelType))
            }

            if breakdown.contains(where: { !$0.figures.years.isEmpty }) {
                YearsOverviewCard(breakdown: breakdown, multiple: breakdown.count > 1, catalog: catalog)
            }

            if let rates = consumption.costRates, rates.months.contains(where: { $0.costPer100km != nil }) {
                CostRateCard(rates: rates)
            }

            if consumption.byFuel.count > 1 {
                FuelPricesCard(fuels: consumption.byFuel)
            }

            if let rows = co2Rows {
                DetailCard(rows: rows)
            }
        }
    }

    private var co2Rows: [Row]? {
        guard let co2 = consumption.co2, co2.totalKg != nil else { return nil }
        var rows = [Row("CO₂ gesamt", "\(StatsFormat.number(co2.totalKg, digits: 0)) kg")]
        if let grams = co2.gramsPerKm {
            rows.append(Row("CO₂ pro Kilometer", "\(StatsFormat.number(grams, digits: 0)) g/km"))
        }
        if let share = consumption.electricShare {
            rows.append(Row("Anteil Ladekosten", StatsFormat.percent(share) ?? "–"))
        }
        return rows
    }
}

private struct EnergyDetailCard: View {
    let figures: VehicleConsumption.Energy
    let title: String?
    let showShare: Bool

    private var rows: [Row] {
        let unit = EnergyFiguresCard.unitLabel(figures.unit)
        var rows: [Row] = []
        if figures.minor {
            rows.append(Row("Verbrauch", String(localized: "nur nebenbei getankt")))
        } else {
            rows.append(Row("Ø Verbrauch", "\(StatsFormat.number(figures.average)) \(unit)/100 km"))
            if figures.minimum != nil || figures.maximum != nil {
                rows.append(Row("Niedrigster / höchster",
                                "\(StatsFormat.number(figures.minimum)) / \(StatsFormat.number(figures.maximum)) \(unit)/100 km"))
            }
        }
        rows.append(Row("Gekauft", StatsFormat.amount(figures.amountBought, unit: figures.unit),
                        detail: figures.fillCount.map { String(localized: "\($0) Vorgänge") }))
        rows.append(Row("Kosten", StatsFormat.euro(figures.cost),
                        detail: figures.averagePrice.map {
                            "Ø \($0.formatted(.number.precision(.fractionLength(3)))) €/\(unit)"
                        }))
        if showShare, let share = StatsFormat.percent(figures.costShare) {
            rows.append(Row("Anteil an den Energiekosten", share))
        }
        if let co2 = figures.co2, let total = co2.totalKg {
            rows.append(Row("CO₂", "\(StatsFormat.number(total, digits: 0)) kg",
                            detail: co2.gramsPerKm.map { "\(StatsFormat.number($0, digits: 0)) g/km" }))
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let title {
                Text(verbatim: title)
                    .font(.title3.bold())
                    .foregroundStyle(Theme.brandDeep)
                    .accessibilityAddTraits(.isHeader)
            }
            DetailCard(rows: rows)
        }
    }
}

private struct MonthlyConsumptionChart: View {
    let figures: VehicleConsumption.Energy
    let title: String?
    let colour: Color

    /// The latest twelve months with a value, oldest first.
    private var data: [(date: Date, month: String, value: Double)] {
        figures.months
            .compactMap { month in
                guard let value = month.consumption, let date = PeriodKey.monthStart(month.month) else { return nil }
                return (date, month.month, value)
            }
            .sorted { $0.date < $1.date }
            .suffix(12)
            .map { $0 }
    }

    var body: some View {
        let unit = EnergyFiguresCard.unitLabel(figures.unit)
        ChartCard(title: "Verbrauch je Monat", subtitle: [title, "\(unit)/100 km"].compactMap { $0 }.joined(separator: " · ")) {
            if data.isEmpty {
                Text("Keine Werte in diesem Zeitraum.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Chart(data, id: \.month) { point in
                    BarMark(x: .value("Monat", point.date, unit: .month), y: .value("Verbrauch", point.value))
                        .foregroundStyle(colour)
                }
                .frame(minHeight: 180)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Verbrauch je Monat"))
                .accessibilityValue(Text(summary(unit)))
            }
        }
    }

    private func summary(_ unit: String) -> String {
        data.map { "\(StatsFormat.shortMonth($0.month)): \(Fmt.number($0.value, digits: 1)) \(unit) pro 100 km" }
            .joined(separator: ", ")
    }
}

private struct YearsOverviewCard: View {
    let breakdown: [(key: String, figures: VehicleConsumption.Energy)]
    let multiple: Bool
    let catalog: FuelCatalog?

    private var years: [Int] {
        Array(Set(breakdown.flatMap { $0.figures.years.map(\.year) })).sorted(by: >)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SectionHeader(title: "Jahresübersicht")
            CardContainer(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(years.enumerated()), id: \.element) { index, year in
                        if index > 0 { Divider().padding(.leading, Theme.Spacing.cardPadding) }
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text(verbatim: String(year))
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(breakdown, id: \.key) { entry in
                                if let row = entry.figures.years.first(where: { $0.year == year }) {
                                    line(row, entry: entry)
                                }
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.cardPadding)
                        .padding(.vertical, Theme.Spacing.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func line(_ row: VehicleConsumption.Year, entry: (key: String, figures: VehicleConsumption.Energy)) -> some View {
        let unit = EnergyFiguresCard.unitLabel(entry.figures.unit)
        var parts: [String] = []
        if multiple { parts.append(entry.figures.name ?? catalog?.energyName(entry.key) ?? entry.key) }
        if !entry.figures.minor, let consumption = row.consumption {
            parts.append("Ø \(Fmt.number(consumption, digits: 1)) \(unit)/100 km")
        }
        parts.append(StatsFormat.amount(row.amountBought, unit: entry.figures.unit))
        parts.append(StatsFormat.euro(row.cost))
        if let co2 = row.co2Kg { parts.append("\(Fmt.number(co2, digits: 0)) kg CO₂") }
        return Text(verbatim: parts.joined(separator: " · "))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }
}

private struct CostRateCard: View {
    let rates: VehicleConsumption.CostRates

    private var data: [(date: Date, period: String, value: Double)] {
        rates.months
            .compactMap { rate in
                guard let value = rate.costPer100km, let date = PeriodKey.monthStart(rate.period) else { return nil }
                return (date, rate.period, value)
            }
            .sorted { $0.date < $1.date }
            .suffix(12)
            .map { $0 }
    }

    var body: some View {
        ChartCard(title: "Energiekosten je 100 km", subtitle: "€/100 km") {
            if data.count > 1 {
                Chart(data, id: \.period) { point in
                    BarMark(x: .value("Monat", point.date, unit: .month), y: .value("Kosten", point.value))
                        .foregroundStyle(Theme.brand)
                }
                .frame(minHeight: 160)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Energiekosten je 100 km und Monat"))
                .accessibilityValue(Text(data.map {
                    "\(StatsFormat.shortMonth($0.period)): \(StatsFormat.euro($0.value)) pro 100 km"
                }.joined(separator: ", ")))
            }
            VStack(spacing: 0) {
                if let best = rates.best, let value = best.costPer100km {
                    line("Günstigster Monat", period: best.period, value: value)
                }
                if let worst = rates.worst, let value = worst.costPer100km {
                    line("Teuerster Monat", period: worst.period, value: value)
                }
                ForEach(rates.years.filter { $0.costPer100km != nil }) { year in
                    HStack {
                        Text(verbatim: year.period).foregroundStyle(.secondary)
                        Spacer()
                        Text(verbatim: "\(StatsFormat.euro(year.costPer100km)) / 100 km").font(.body.weight(.semibold))
                    }
                    .padding(.vertical, Theme.Spacing.xxs)
                    .accessibilityElement(children: .combine)
                }
            }
            .monospacedDigit()
            Text("Einzelne Monate schwanken, wenn selten getankt wird; Jahreswerte sind stabiler.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func line(_ label: LocalizedStringKey, period: String, value: Double) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: "\(StatsFormat.month(period)): \(StatsFormat.euro(value))")
                .font(.body.weight(.semibold))
        }
        .padding(.vertical, Theme.Spacing.xxs)
        .accessibilityElement(children: .combine)
    }
}

private struct FuelPricesCard: View {
    let fuels: [VehicleConsumption.FuelPrice]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SectionHeader(title: "Preise je Sorte")
            DetailCard(rows: fuels.map { fuel in
                let unit = EnergyFiguresCard.unitLabel(fuel.unit)
                return Row(verbatim: fuel.name,
                           fuel.averagePrice.map { "\($0.formatted(.number.precision(.fractionLength(3)))) €/\(unit)" } ?? "–",
                           detail: detail(fuel, unit: unit))
            })
        }
    }

    private func detail(_ fuel: VehicleConsumption.FuelPrice, unit: String) -> String {
        var parts = [StatsFormat.amount(fuel.amount, unit: fuel.unit)]
        if let share = StatsFormat.percent(fuel.shareOfEnergy) { parts.append(share) }
        if let markup = fuel.markup, let perUnit = markup.perUnit {
            let amount = "+\(perUnit.formatted(.number.precision(.fractionLength(3)))) €/\(unit)"
            parts.append(markup.percent.map { "\(amount) (\(Fmt.number($0, digits: 1)) %)" } ?? amount)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Costs

/// Name, colour and symbol of a key in `/costs` (`Tankfuellung:l`, `Versicherung`, `custom:<uuid>` …), from
/// `GET /categories` and the vehicle's energy colours.
struct CostCategoryStyle {
    let categories: CategoriesResponse?
    let fuelType: RemoteFuelType

    func name(_ key: String) -> String {
        let parsed = CostCategoryKey(key)
        if parsed.isFuelling { return parsed.unit == "kwh" ? String(localized: "Laden") : String(localized: "Tanken") }
        return categories?.category(key)?.name ?? key
    }

    func colour(_ key: String) -> Color {
        let parsed = CostCategoryKey(key)
        if parsed.isFuelling {
            switch parsed.unit {
            case "kwh": return Theme.Energy.electricity
            case "kg": return fuelType == .hydrogen ? Theme.Energy.hydrogen : Theme.Energy.gas
            default: return fuelType == .electric ? Theme.Energy.petrol : fuelType.energyColor
            }
        }
        return categories?.category(key)?.color.flatMap { Color(apiHex: $0) } ?? Theme.brand
    }
}

struct CostsSection: View {
    let vehicle: RemoteVehicle
    let costs: VehicleCosts
    /// Costs of every year for the comparison; only filled when the whole period is shown.
    let yearCosts: [Int: VehicleCosts]
    let categories: CategoriesResponse?
    @Binding var year: Int?

    private var style: CostCategoryStyle { .init(categories: categories, fuelType: vehicle.fuelType) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.cardGap) {
            if costs.years.count > 0 {
                ChipGroup(options: [.init(value: Int?.none, title: "Gesamt")]
                          + costs.years.sorted(by: >).map { .init(value: Int?.some($0), title: LocalizedStringKey(String($0))) },
                          selection: $year)
            }

            if costs.total.total == 0 && costs.months.isEmpty {
                CardContainer {
                    Text("Noch keine Kosten. Sie erscheinen mit den ersten Tank- und Ladevorgängen und Ausgaben.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                summary
                monthlyChart
                groupSums
                structure
                largestExpenses
                if year == nil, yearCosts.count > 1 { yearComparison }
            }
        }
    }

    // MARK: Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            StatTileRow {
                StatTile(label: "Kosten", value: StatsFormat.number(costs.total.total, digits: 0), unit: "€")
                StatTile(label: "Pro Kilometer", value: costs.costPerKmTotal.map { StatsFormat.number($0, digits: 2) },
                         unit: "€/km")
                StatTile(label: "Pro Monat", value: costs.perMonth.map { StatsFormat.number($0, digits: 0) }, unit: "€")
            }
            DetailCard(rows: summaryRows)
            if costs.costPerKmTotal == nil {
                Text("Kosten pro Kilometer erscheinen, sobald Kilometerstände erfasst sind.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var summaryRows: [Row] {
        var rows = [
            Row("Tanken und Laden", StatsFormat.euro(costs.total.energy, currency: costs.currency),
                detail: costs.costPerKmEnergy.map { "\(StatsFormat.number($0, digits: 3)) €/km" }),
            Row("Ausgaben", StatsFormat.euro(costs.total.expenses, currency: costs.currency)),
        ]
        if let distance = costs.distanceKm {
            rows.append(Row("Gefahrene Strecke", Fmt.kilometres(distance)))
        }
        if let maintenance = costs.maintenancePer10000Km {
            rows.append(Row("Wartung je 10.000 km", StatsFormat.euro(maintenance, currency: costs.currency, digits: 0)))
        }
        if let current = costs.currentMonth {
            rows.append(Row("Laufender Monat", StatsFormat.euro(current.sums.total, currency: costs.currency),
                            detail: costs.previousMonth.map {
                                "\(StatsFormat.month($0.month)): \(StatsFormat.euro($0.sums.total, currency: costs.currency))"
                            }))
        }
        return rows
    }

    // MARK: Monthly chart

    private struct Bar: Identifiable {
        let id: String
        let date: Date
        let month: String
        let name: String
        let value: Double
    }

    /// Costs per month and category of the latest twelve months; Swift Charts stacks them.
    private var bars: [Bar] {
        let months = costs.months
            .compactMap { month in PeriodKey.monthStart(month.month).map { (month, $0) } }
            .sorted { $0.1 < $1.1 }
            .suffix(12)
        return months.flatMap { month, date in
            month.byCategory.filter { $0.value > 0 }.map { key, value in
                Bar(id: "\(month.month)|\(key)", date: date, month: month.month, name: style.name(key), value: value)
            }
        }
    }

    @ViewBuilder
    private var monthlyChart: some View {
        let data = bars
        if !data.isEmpty {
            let names = Array(Set(data.map(\.name))).sorted()
            let keyByName = Dictionary(costs.months.flatMap(\.byCategory.keys).map { (style.name($0), $0) },
                                       uniquingKeysWith: { first, _ in first })
            ChartCard(title: "Ausgaben je Monat", subtitle: year.map { String($0) } ?? String(localized: "Letzte 12 Monate")) {
                Chart(data) { bar in
                    BarMark(x: .value("Monat", bar.date, unit: .month), y: .value("Kosten", bar.value))
                        .foregroundStyle(by: .value("Kategorie", bar.name))
                }
                .chartForegroundStyleScale(domain: names, range: names.map { style.colour(keyByName[$0] ?? $0) })
                .chartLegend(.hidden)
                .frame(minHeight: 200)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Ausgaben je Monat"))
                .accessibilityValue(Text(monthSummary(data)))
            }
        }
    }

    private func monthSummary(_ data: [Bar]) -> String {
        let months = Array(Set(data.map(\.month))).sorted()
        return months.map { month in
            let sum = data.filter { $0.month == month }.map(\.value).reduce(0, +)
            return "\(StatsFormat.shortMonth(month)): \(StatsFormat.euro(sum, currency: costs.currency, digits: 0))"
        }.joined(separator: ", ")
    }

    // MARK: Cost groups

    /// Sums per cost group as the API calculates them; names come from `GET /categories`.
    @ViewBuilder
    private var groupSums: some View {
        let groups = costs.groups.filter { $0.count > 0 || $0.total > 0 }
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                SectionHeader(title: "Kosten nach Gruppe")
                DetailCard(rows: groups.map { group in
                    Row(verbatim: categories?.groups.first { $0.key == group.key }?.name ?? group.key,
                        StatsFormat.euro(group.total, currency: costs.currency),
                        detail: group.share.map { "\(StatsFormat.number($0, digits: 1)) %" })
                })
            }
        }
    }

    // MARK: Largest expenses

    @ViewBuilder
    private var largestExpenses: some View {
        if !costs.largestExpenses.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                SectionHeader(title: "Größte Einzelausgaben")
                DetailCard(rows: costs.largestExpenses.map { expense in
                    Row(verbatim: style.name(expense.category),
                        StatsFormat.euro(expense.cost, currency: costs.currency),
                        detail: expenseDetail(expense))
                })
            }
        }
    }

    private func expenseDetail(_ expense: VehicleCosts.Expense) -> String? {
        let parts = [expense.date?.formatted(.dateTime.day().month(.abbreviated).year()), expense.vendor,
                     expense.description].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Cost structure

    @ViewBuilder
    private var structure: some View {
        if !costs.categories.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                SectionHeader(title: "Kostenstruktur")
                CardContainer(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(costs.categories.enumerated()), id: \.element.id) { index, category in
                            if index > 0 { Divider().padding(.leading, Theme.Spacing.cardPadding) }
                            row(category)
                        }
                    }
                }
            }
        }
    }

    private func row(_ category: VehicleCosts.Category) -> some View {
        let biggest = costs.categories.first?.total ?? 0
        return VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(style.colour(category.key)).frame(width: 10, height: 10).accessibilityHidden(true)
                Text(verbatim: style.name(category.key)).font(.body.weight(.medium))
                Spacer()
                Text(verbatim: StatsFormat.euro(category.total, currency: costs.currency))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
            }
            // Bar length relative to the biggest category: a drawing aid, not a figure.
            GeometryReader { proxy in
                Capsule()
                    .fill(style.colour(category.key))
                    .frame(width: biggest > 0 ? max(4, proxy.size.width * category.total / biggest) : 0, height: 6)
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            Text("\(category.count) Einträge")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, Theme.Spacing.s)
        .accessibilityElement(children: .combine)
    }

    // MARK: Year comparison

    private var yearComparison: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SectionHeader(title: "Jahresvergleich")
            DetailCard(rows: yearCosts.keys.sorted(by: >).compactMap { year in
                yearCosts[year].map {
                    Row(verbatim: String(year), StatsFormat.euro($0.total.total, currency: $0.currency, digits: 0),
                        detail: yearDetail($0))
                }
            })
        }
    }

    private func yearDetail(_ costs: VehicleCosts) -> String {
        var parts: [String] = []
        if let distance = costs.distanceKm { parts.append(Fmt.kilometres(distance)) }
        if let perKm = costs.costPerKmTotal { parts.append("\(StatsFormat.number(perKm, digits: 2)) €/km") }
        return parts.joined(separator: " · ")
    }
}

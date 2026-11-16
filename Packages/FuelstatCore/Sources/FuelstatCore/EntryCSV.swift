import Foundation

/// One entry (fill-up, charging session, expense or odometer note) as the CSV export needs it. All values come from
/// the API's timeline; nothing is calculated here.
public struct EntryCSVRow: Equatable, Sendable {
    public var date: Date
    /// Category key as the API names it; fill-ups and charging sessions are `Tankfuellung`.
    public var category: String
    public var odometerKm: Int?
    /// A placeholder, not a real reading: left empty in the file.
    public var odometerEstimated: Bool
    public var amount: Double?
    /// `l`, `kwh` or `kg`
    public var unit: String?
    /// Fuel grade key (FuelStat/fuelstat#140).
    public var fuel: String?
    public var cost: Double?
    public var isFull: Bool?
    public var skipPrevious: Bool?
    /// Consumption per 100 km of the segment this fill-up closes, from the API.
    public var consumption: Double?
    public var place: String?
    public var description: String?

    public init(date: Date, category: String, odometerKm: Int? = nil, odometerEstimated: Bool = false,
                amount: Double? = nil, unit: String? = nil, fuel: String? = nil, cost: Double? = nil,
                isFull: Bool? = nil, skipPrevious: Bool? = nil, consumption: Double? = nil, place: String? = nil,
                description: String? = nil) {
        self.date = date
        self.category = category
        self.odometerKm = odometerKm
        self.odometerEstimated = odometerEstimated
        self.amount = amount
        self.unit = unit
        self.fuel = fuel
        self.cost = cost
        self.isFull = isFull
        self.skipPrevious = skipPrevious
        self.consumption = consumption
        self.place = place
        self.description = description
    }

    public var isFilling: Bool { category == EntryCSV.fillingCategory }
}

/// The vehicle side of the export: its drive type decides which columns exist.
public struct EntryCSVVehicle: Equatable, Sendable {
    public var name: String
    /// `diesel`, `e5`, `electric`, `phev` …
    public var fuelType: String
    /// The vehicle has more than one fuel grade, so the file gets a "Sorte" column.
    public var hasSeveralFuels: Bool
    /// Display names of fuel grades by key.
    public var fuelNames: [String: String]
    /// Display names of categories by key; unknown keys are written as they are.
    public var categoryNames: [String: String]

    public init(name: String, fuelType: String, hasSeveralFuels: Bool = false, fuelNames: [String: String] = [:],
                categoryNames: [String: String] = [:]) {
        self.name = name
        self.fuelType = fuelType
        self.hasSeveralFuels = hasSeveralFuels
        self.fuelNames = fuelNames
        self.categoryNames = categoryNames
    }
}

/// CSV export of a vehicle's entries in the format of the web app's `export.php`: semicolon separated, UTF-8 with
/// byte order mark so Excel opens it directly, German headers and dates, decimal comma. The import of the web app
/// recognises the columns again.
///
/// Columns the API does not deliver yet (charging type, state of charge, charging time) are written empty so the
/// file has the same shape as the web app's.
public enum EntryCSV {
    public static let fillingCategory = "Tankfuellung"

    public static func make(rows: [EntryCSVRow], vehicle: EntryCSVVehicle) -> Data {
        var lines = [header(for: vehicle)]
        for row in rows.sorted(by: { $0.date < $1.date }) {
            lines.append(fields(for: row, vehicle: vehicle))
        }
        let text = lines.map { $0.map(encode).joined(separator: ";") }.joined(separator: "\n") + "\n"
        return Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
    }

    /// Calendar year of an entry in Europe/Berlin, as the API counts years.
    public static func year(of date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        return calendar.component(.year, from: date)
    }

    /// `Familienauto_2026.csv`: letters, digits, `_` and `-` only, like the web app.
    public static func fileName(vehicleName: String, year: Int?) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        var name = ""
        var lastWasSeparator = false
        for scalar in vehicleName.unicodeScalars {
            if allowed.contains(scalar) {
                name.unicodeScalars.append(scalar)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                name += "_"
                lastWasSeparator = true
            }
        }
        if name.isEmpty { name = "fahrzeug" }
        return name + (year.map { "_\($0)" } ?? "") + ".csv"
    }

    // MARK: Columns

    private static func isElectric(_ fuelType: String) -> Bool { fuelType == "electric" }
    private static func isPlugInHybrid(_ fuelType: String) -> Bool { fuelType == "phev" }
    private static func charges(_ fuelType: String) -> Bool { isElectric(fuelType) || isPlugInHybrid(fuelType) }

    /// Unit of the amount column for vehicles with one unit.
    static func unitLabel(_ fuelType: String) -> String {
        switch fuelType {
        case "electric": "kWh"
        case "cng", "hydrogen": "kg"
        default: "l"
        }
    }

    static func header(for vehicle: EntryCSVVehicle) -> [String] {
        let unit = unitLabel(vehicle.fuelType)
        var header: [String]
        if isPlugInHybrid(vehicle.fuelType) {
            header = ["Datum", "Kategorie", "Tachostand (km)", "Menge", "Einheit", "Kosten (EUR)", "Voll", "Lücke davor",
                      "Verbrauch (pro 100km)", "Ort/Anbieter", "Beschreibung"]
        } else {
            header = ["Datum", "Kategorie", "Tachostand (km)", "Menge (\(unit))", "Kosten (EUR)",
                      isElectric(vehicle.fuelType) ? "Vollgeladen" : "Vollgetankt", "Lücke davor",
                      "Verbrauch (\(unit)/100km)", "Ort/Anbieter", "Beschreibung"]
        }
        if vehicle.hasSeveralFuels { header.insert("Sorte", at: 4) }
        if charges(vehicle.fuelType), let gap = header.firstIndex(of: "Lücke davor") {
            header.insert(contentsOf: ["Ladeart", "Ladestand vorher (%)", "Ladestand nachher (%)", "Ladedauer (min)"],
                          at: gap + 1)
        }
        return header
    }

    static func fields(for row: EntryCSVRow, vehicle: EntryCSVVehicle) -> [String] {
        let filling = row.isFilling
        var fields = [
            dateText(row.date),
            spreadsheetSafe(categoryName(row, vehicle: vehicle)),
            row.odometerEstimated ? "" : row.odometerKm.map(String.init) ?? "",
            filling ? number(row.amount) : "",
        ]
        if vehicle.hasSeveralFuels {
            fields.append(filling ? row.fuel.map { spreadsheetSafe(vehicle.fuelNames[$0] ?? $0) } ?? "" : "")
        }
        if isPlugInHybrid(vehicle.fuelType) {
            fields.append(filling ? unitText(row.unit) : "")
        }
        fields += [number(row.cost), filling ? yesNo(row.isFull) : "", filling ? yesNo(row.skipPrevious) : ""]
        if charges(vehicle.fuelType) {
            fields += ["", "", "", ""]
        }
        fields += [filling ? number(row.consumption) : "", spreadsheetSafe(row.place ?? ""),
                   spreadsheetSafe(row.description ?? "")]
        return fields
    }

    private static func categoryName(_ row: EntryCSVRow, vehicle: EntryCSVVehicle) -> String {
        if row.isFilling { return row.unit == "kwh" ? "Ladevorgang" : "Tankfüllung" }
        return vehicle.categoryNames[row.category] ?? row.category
    }

    private static func unitText(_ unit: String?) -> String {
        switch unit {
        case "kwh": "kWh"
        case "kg": "kg"
        default: "l"
        }
    }

    private static func yesNo(_ value: Bool?) -> String { value == true ? "ja" : "nein" }

    /// `12,50`: two decimals, comma, no thousands separator; empty for no value.
    private static func number(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }

    private static func dateText(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d.%02d.%04d", parts.day ?? 0, parts.month ?? 0, parts.year ?? 0)
    }

    // MARK: Escaping

    /// Text that Excel would run as a formula (`=`, `+`, `-`, `@`, tab, return) gets an apostrophe in front.
    static func spreadsheetSafe(_ text: String) -> String {
        guard let first = text.first, "=+-@\t\r".contains(first) else { return text }
        return "'" + text
    }

    /// Quotes a field like PHP's `fputcsv` with `;`: when it contains the delimiter, a quote, a line break, a tab or
    /// a space; quotes are doubled.
    static func encode(_ field: String) -> String {
        // By unicode scalar: a "\r\n" is a single Character in Swift and would match neither "\r" nor "\n".
        let needsQuotes = field.unicodeScalars.contains { ";\"\n\r\t \\".unicodeScalars.contains($0) }
        guard needsQuotes else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

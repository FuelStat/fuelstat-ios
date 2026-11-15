import Foundation

// CSV import (FuelStat/fuelstat-ios#38): reads a file, guesses which column is which and turns the rows into the
// payload of `POST /vehicles/:id/import`. This is a port of the web app's `includes/csv_import.php`, so a file behaves
// the same in both. Duplicate detection, plausibility checks and the final validation stay with the API.
//
// Left out on purpose: the "Bauteile" column (needs the vehicle's part catalog) and creating own categories for
// unknown names (they go to "Sonstiges" and keep their name in the description, like the web app does without the
// checkbox).

// MARK: - Table

/// A CSV file as header and rows of text.
public struct CSVTable: Equatable, Sendable {
    public let header: [String]
    public let rows: [[String]]
    public let delimiter: Character

    public init(header: [String], rows: [[String]], delimiter: Character = ";") {
        self.header = header
        self.rows = rows
        self.delimiter = delimiter
    }

    /// Reads a file: removes a byte order mark, decodes UTF-8 or else Windows-1252 and detects `;`, `,` or tab from
    /// the first line. Blank lines are skipped, the first remaining line is the header.
    public static func read(_ data: Data) -> CSVTable {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        let text = String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .windowsCP1252) ?? ""
        let scalars = Array(text.unicodeScalars)
        let delimiter = detectDelimiter(scalars)
        var records = parse(scalars, delimiter: delimiter)
        guard !records.isEmpty else { return CSVTable(header: [], rows: [], delimiter: Character(delimiter)) }
        let header = records.removeFirst().map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return CSVTable(header: header, rows: records, delimiter: Character(delimiter))
    }

    /// The delimiter with the most occurrences in the first line; `;` wins a tie, then `,`, then tab.
    private static func detectDelimiter(_ scalars: [Unicode.Scalar]) -> Unicode.Scalar {
        let firstLine = scalars.prefix { $0 != "\n" && $0 != "\r" }
        var best: Unicode.Scalar = ";"
        var bestCount = -1
        for candidate: Unicode.Scalar in [";", ",", "\t"] {
            let count = firstLine.filter { $0 == candidate }.count
            if count > bestCount {
                best = candidate
                bestCount = count
            }
        }
        return best
    }

    /// RFC 4180 style parsing on unicode scalars. A `\r\n` is one Character in Swift and would not equal `\n`, so
    /// the text is never split by Character.
    private static func parse(_ scalars: [Unicode.Scalar], delimiter: Unicode.Scalar) -> [[String]] {
        var records: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false

        func finishRow() {
            row.append(String(field))
            field = String.UnicodeScalarView()
            let blank = row.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !blank { records.append(row) }
            row = []
        }

        var i = 0
        while i < scalars.count {
            let s = scalars[i]
            if inQuotes {
                if s == "\"" {
                    if i + 1 < scalars.count, scalars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(s)
                }
            } else if s == "\"", field.isEmpty {
                inQuotes = true
            } else if s == delimiter {
                row.append(String(field))
                field = String.UnicodeScalarView()
            } else if s == "\n" || s == "\r" {
                if s == "\r", i + 1 < scalars.count, scalars[i + 1] == "\n" { i += 1 }
                finishRow()
            } else {
                field.append(s)
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { finishRow() }
        return records
    }
}

// MARK: - Import

/// Category of the vehicle's catalog (`GET /categories`) as far as the import needs it.
public struct ImportCategory: Equatable, Sendable {
    public let key: String
    public let name: String
    /// `expense`, `trip`, `odometer` or `fillup`.
    public let form: String
    public let isLegacy: Bool
    public let isAvailable: Bool

    public init(key: String, name: String, form: String, isLegacy: Bool, isAvailable: Bool) {
        self.key = key
        self.name = name
        self.form = form
        self.isLegacy = isLegacy
        self.isAvailable = isAvailable
    }
}

/// Fuel grade of the catalog (`GET /fuels`) for the "Sorte" column.
public struct ImportFuel: Equatable, Sendable {
    public let key: String
    public let name: String

    public init(key: String, name: String) {
        self.key = key
        self.name = name
    }
}

/// A fill-up or charge in the shape the web app sends: same timestamp, explicit `null` for a missing odometer and
/// place. Duplicates are detected by date, so a different shape would import rows twice.
public struct ImportFillup: Equatable, Sendable, Encodable {
    public var filledAt: String
    public var odometerKm: Int?
    public var amount: Double
    public var totalCostEur: Double
    public var station: String?
    public var isFull: Bool
    public var skipPrevious: Bool
    public var unit: String?
    public var fuel: String?
    public var chargeType: String?
    public var socBeforePct: Int?
    public var socAfterPct: Int?
    public var chargeMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case filledAt, odometerKm, amount, totalCostEur, station, isFull, skipPrevious, unit, fuel
        case chargeType, socBeforePct, socAfterPct, chargeMinutes
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(filledAt, forKey: .filledAt)
        try c.encode(odometerKm, forKey: .odometerKm)
        try c.encode(amount, forKey: .amount)
        try c.encode(totalCostEur, forKey: .totalCostEur)
        try c.encode(station, forKey: .station)
        try c.encode(isFull, forKey: .isFull)
        try c.encode(skipPrevious, forKey: .skipPrevious)
        try c.encodeIfPresent(unit, forKey: .unit)
        try c.encodeIfPresent(fuel, forKey: .fuel)
        try c.encodeIfPresent(chargeType, forKey: .chargeType)
        try c.encodeIfPresent(socBeforePct, forKey: .socBeforePct)
        try c.encodeIfPresent(socAfterPct, forKey: .socAfterPct)
        try c.encodeIfPresent(chargeMinutes, forKey: .chargeMinutes)
    }
}

/// An expense (or odometer note) in the shape the web app sends.
public struct ImportEntry: Equatable, Sendable, Encodable {
    public var occurredAt: String
    public var category: String
    public var amountEur: Double
    public var odometerKm: Int?
    public var vendor: String?
    public var description: String?

    enum CodingKeys: String, CodingKey { case occurredAt, category, amountEur, odometerKm, vendor, description }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(occurredAt, forKey: .occurredAt)
        try c.encode(category, forKey: .category)
        try c.encode(amountEur, forKey: .amountEur)
        try c.encode(odometerKm, forKey: .odometerKm)
        try c.encode(vendor, forKey: .vendor)
        try c.encode(description, forKey: .description)
    }
}

/// Why a row cannot be imported; the app turns it into a message.
public enum ImportRowError: Equatable, Sendable {
    case dateInvalid
    case amountMissing
    case costInvalid
}

/// One file row as the preview shows it.
public struct ImportPreviewRow: Equatable, Sendable, Identifiable {
    /// Line in the file; the header is line 1.
    public let number: Int
    /// `YYYY-MM-DD`
    public let date: String?
    public let isFillup: Bool
    /// What the row will be filed under, e.g. "Tankfüllung", "Versicherung" or "Sonstiges (Glasbruch)".
    public let categoryText: String
    public let odometerKm: Int?
    public let amount: Double?
    public let unit: String?
    public let cost: Double?
    public let isFull: Bool?
    public let chargeType: String?
    public let place: String
    public let note: String
    public let error: ImportRowError?

    public var id: Int { number }
}

/// The columns a CSV column can be assigned to.
public enum ImportField: String, CaseIterable, Sendable, Hashable {
    case date, kind, odometer, amount, unit, fuel, cost, pricePerUnit, full, gapBefore
    case chargeType, socBefore, socAfter, chargeMinutes, place, note
}

/// Rows converted for the API.
public struct ImportPlan: Equatable, Sendable {
    public var fillups: [ImportFillup] = []
    public var entries: [ImportEntry] = []
    /// File line of each element of `fillups` and `entries`, to show API answers at the right row.
    public var fillupLines: [Int] = []
    public var entryLines: [Int] = []
    public var errors: [Int: ImportRowError] = [:]
    public var preview: [ImportPreviewRow] = []
    /// Unknown or locked categories that go to "Sonstiges": name and number of rows.
    public var otherCategories: [String: Int] = [:]

    public init() {}

    public var isEmpty: Bool { fillups.isEmpty && entries.isEmpty }

    /// The plan without the rows of these file lines (e.g. rows the API rejected in the check).
    public func excluding(lines: Set<Int>) -> ImportPlan {
        var result = self
        let keepFillups = fillupLines.indices.filter { !lines.contains(fillupLines[$0]) }
        let keepEntries = entryLines.indices.filter { !lines.contains(entryLines[$0]) }
        result.fillups = keepFillups.map { fillups[$0] }
        result.fillupLines = keepFillups.map { fillupLines[$0] }
        result.entries = keepEntries.map { entries[$0] }
        result.entryLines = keepEntries.map { entryLines[$0] }
        return result
    }

    /// The API takes up to 1000 rows per request and saves each request as one transaction; the web app sends 500.
    public struct Chunk<Item: Sendable & Equatable>: Equatable, Sendable {
        public let offset: Int
        public let items: [Item]
    }

    public var fillupChunks: [Chunk<ImportFillup>] { CSVImport.chunks(fillups) }
    public var entryChunks: [Chunk<ImportEntry>] { CSVImport.chunks(entries) }
}

public enum CSVImport {
    /// Same limits as the web app.
    public static let maxFileBytes = 5 * 1024 * 1024
    public static let maxRows = 10_000
    public static let chunkSize = 500

    static func chunks<Item: Sendable & Equatable>(_ items: [Item]) -> [ImportPlan.Chunk<Item>] {
        stride(from: 0, to: items.count, by: chunkSize).map {
            ImportPlan.Chunk(offset: $0, items: Array(items[$0..<min($0 + chunkSize, items.count)]))
        }
    }

    // MARK: Column detection

    /// Normalised header names that are recognised for each field (Fuelstat export, Spritmonitor, spreadsheets). The
    /// first field in this list that knows a header wins.
    private static let synonyms: [(ImportField, [String])] = [
        (.date, ["datum", "date", "tankdatum", "ladedatum", "tag"]),
        (.kind, ["art", "typ", "type", "kategorie", "category", "eintragstyp"]),
        (.odometer, ["tachostand", "kilometerstand", "kmstand", "odometer", "tacho", "km", "odometerkm"]),
        (.amount, ["menge", "liter", "litre", "liters", "amount", "quantity", "tankmenge", "kwh", "getankt",
                   "geladen", "energie", "lademenge"]),
        (.cost, ["kosten", "gesamtpreis", "betrag", "preisgesamt", "gesamtkosten", "total", "cost", "costs",
                 "summe", "preis"]),
        (.unit, ["einheit", "unit", "mengeneinheit", "energieart"]),
        (.fuel, ["sorte", "kraftstoffsorte", "kraftstoff", "fuel", "fueltype", "spritsorte"]),
        (.pricePerUnit, ["preisproeinheit", "preisproliter", "literpreis", "preisl", "priceperliter", "priceperunit",
                         "einzelpreis", "preisprokwh", "kwhpreis", "strompreis", "preiskwh"]),
        (.full, ["vollgetankt", "vollgeladen", "voll", "full", "volltank", "isfull", "vollgetanktbzwgeladen",
                  // Header of the API's export for vehicles without a clear drive type; the web app's list lacks it.
                  "vollgetanktgeladen"]),
        (.gapBefore, ["lueckedavor", "luecke", "skipprevious", "vorherigeignorieren",
                      "vorherigetankfuellungignorieren"]),
        (.chargeType, ["ladeart", "chargetype", "ladetyp", "ladeort"]),
        (.socBefore, ["ladestandvorher", "socvorher", "socbefore", "akkuvorher", "batterievorher"]),
        (.socAfter, ["ladestandnachher", "socnachher", "socafter", "akkunachher", "batterienachher"]),
        (.chargeMinutes, ["ladedauer", "chargeminutes", "dauer", "ladezeit"]),
        (.place, ["ort", "tankstelle", "ladestation", "ladesaeule", "station", "ortanbieter", "anbieter", "vendor",
                  "location", "standort"]),
        (.note, ["beschreibung", "notiz", "bemerkung", "note", "notes", "description", "kommentar", "comment"]),
    ]

    /// Header in lower case without brackets, umlauts spelled out and only letters and digits left.
    public static func normalize(_ header: String) -> String {
        var text = header.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        while let open = text.firstIndex(of: "("), let close = text[open...].firstIndex(of: ")") {
            text.removeSubrange(open...close)
        }
        for (umlaut, spelled) in [("ä", "ae"), ("ö", "oe"), ("ü", "ue"), ("ß", "ss")] {
            text = text.replacingOccurrences(of: umlaut, with: spelled)
        }
        return String(String.UnicodeScalarView(text.unicodeScalars.filter {
            ("a"..."z").contains($0) || ("0"..."9").contains($0)
        }))
    }

    /// Guesses the column of each field from the header names.
    public static func detectMapping(header: [String]) -> [ImportField: Int] {
        var mapping: [ImportField: Int] = [:]
        for (index, name) in header.enumerated() {
            let normalized = normalize(name)
            for (field, names) in synonyms where mapping[field] == nil && names.contains(normalized) {
                mapping[field] = index
                break
            }
        }
        return mapping
    }

    // MARK: Values

    /// Decimal number from "1.234,56", "1234.56", "41,2 l" or "75,31 €": the last separator is the decimal one.
    public static func number(_ text: String?) -> Double? {
        let kept = String(String.UnicodeScalarView((text ?? "").unicodeScalars.filter {
            ("0"..."9").contains($0) || $0 == "," || $0 == "." || $0 == "-"
        }))
        guard !kept.isEmpty, kept != "-" else { return nil }
        var value = kept
        let comma = value.lastIndex(of: ","), dot = value.lastIndex(of: ".")
        if let comma, let dot {
            value = comma > dot
                ? value.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
                : value.replacingOccurrences(of: ",", with: "")
        } else if comma != nil {
            value = value.replacingOccurrences(of: ",", with: ".")
        }
        return Double(value)
    }

    /// Whole number (odometer): thousands separators and units are ignored, one or two decimals are cut off.
    public static func integer(_ text: String?) -> Int? {
        var value = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let separator = value.lastIndex(where: { $0 == "," || $0 == "." }) {
            let tail = value[value.index(after: separator)...]
            if (1...2).contains(tail.count), tail.allSatisfy({ $0.isASCII && $0.isNumber }) {
                value = String(value[..<separator])
            }
        }
        let digits = String(String.UnicodeScalarView(value.unicodeScalars.filter { ("0"..."9").contains($0) }))
        return digits.isEmpty ? nil : Int(digits)
    }

    /// `YYYY-MM-DD` from 31.12.2025, 31.12.25, 2025-12-31 or 31/12/2025, with or without a time; nil if invalid.
    public static func date(_ text: String?) -> String? {
        let scalars = Array((text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars)

        func digits(at start: Int, _ range: ClosedRange<Int>) -> (value: Int, next: Int)? {
            var end = start
            while end < scalars.count, end - start < range.upperBound, ("0"..."9").contains(scalars[end]) { end += 1 }
            guard range.contains(end - start) else { return nil }
            return (Int(String(String.UnicodeScalarView(scalars[start..<end])))!, end)
        }

        var year = 0, month = 0, day = 0
        if let y = digits(at: 0, 4...4), y.next < scalars.count, scalars[y.next] == "-",
           let m = digits(at: y.next + 1, 1...2), m.next < scalars.count, scalars[m.next] == "-",
           let d = digits(at: m.next + 1, 1...2) {
            (year, month, day) = (y.value, m.value, d.value)
        } else if let d = digits(at: 0, 1...2), d.next < scalars.count, scalars[d.next] == "." || scalars[d.next] == "/",
                  let m = digits(at: d.next + 1, 1...2), m.next < scalars.count,
                  scalars[m.next] == "." || scalars[m.next] == "/",
                  let y = digits(at: m.next + 1, 2...4) {
            (year, month, day) = (y.value, m.value, d.value)
            if year < 100 { year += year > 69 ? 1900 : 2000 }
        } else {
            return nil
        }
        guard isValidDate(year: year, month: month, day: day) else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func isValidDate(year: Int, month: Int, day: Int) -> Bool {
        guard (1...32767).contains(year), (1...12).contains(month), day >= 1 else { return false }
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return day <= days[month - 1]
    }

    /// Yes/no cell; an empty one gives `defaultValue`.
    public static func yesNo(_ text: String?, defaultValue: Bool = true) -> Bool {
        let value = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.isEmpty { return defaultValue }
        return !["nein", "no", "n", "0", "false", "falsch", "teil", "teilweise", "partial"].contains(value)
    }

    /// `l`, `kwh` or `kg` from "Liter", "kWh" and the like; nil if unknown.
    public static func unit(_ text: String?) -> String? {
        switch normalize(text ?? "") {
        case "l", "liter", "litre", "liters", "ltr": "l"
        case "kwh", "kilowattstunden": "kwh"
        case "kg", "kilogramm": "kg"
        default: nil
        }
    }

    /// `home`, `ac_public` or `dc` from "Zu Hause", "Wallbox", "AC öffentlich", "Schnelllader" and the like.
    public static func chargeType(_ text: String?) -> String? {
        let value = normalize(text ?? "")
        guard !value.isEmpty else { return nil }
        if ["home", "ac_public", "dc"].contains(value) { return value }
        if value == "acpublic" { return "ac_public" }
        if ["dc", "schnell", "hpc", "fast"].contains(where: value.contains) { return "dc" }
        if ["hause", "wallbox", "privat", "daheim"].contains(where: value.contains) { return "home" }
        if ["ac", "oeffentlich", "public", "saeule"].contains(where: value.contains) { return "ac_public" }
        return nil
    }

    /// Fuel grade from a key, a name or a short form like "E10" or "Autogas"; nil if unknown. Whether the grade
    /// belongs to the vehicle is the API's call.
    public static func fuel(_ text: String?, catalog: [ImportFuel]) -> String? {
        let value = normalize(text ?? "")
        guard !value.isEmpty else { return nil }
        let short = ["e5": "super_e5", "e10": "super_e10", "superplus": "super_plus", "super98": "super_plus",
                     "autogas": "lpg", "erdgas": "cng", "strom": "electricity", "h2": "hydrogen"]
        if let key = short[value] { return key }
        return catalog.first { value == normalize($0.key) || value == normalize($0.name) }?.key
    }

    /// What a row is: a fill-up or charge (with the unit the kind implies) or an expense with its category text.
    public struct Kind: Equatable, Sendable {
        public let isFillup: Bool
        public let category: String
        public let unit: String?
    }

    private static let fillupWords: Set = ["tankfuellung", "tanken", "tankstopp", "fuel", "refuel", "refueling",
                                           "fillup", "kraftstoff", "getankt"]
    private static let chargeWords: Set = ["laden", "ladevorgang", "ladung", "aufladen", "geladen", "charge",
                                           "charging"]
    private static let knownCategories = [
        "versicherung": "Versicherung", "werkstatt": "Werkstatt", "inspektion": "Inspektion", "steuer": "Steuer",
        "kfzsteuer": "Steuer", "reparatur": "Reparatur", "reifen": "Reifen", "tuev": "TUV", "tuv": "TUV",
        "hu": "TUV", "wartung": "Wartung", "kundendienst": "Wartung", "dekor": "Dekor", "zubehoer": "Dekor",
        "fahrt": "Fahrt", "kilometerstand": "Kilometerstand", "parken": "Parken", "parkgebuehr": "Parken",
        "maut": "Maut", "vignette": "Maut", "pflege": "Pflege", "waesche": "Pflege", "autowaesche": "Pflege",
        "waschen": "Pflege", "leasing": "Leasing", "finanzierung": "Leasing", "kredit": "Leasing",
        "sonstiges": "Sonstiges", "sonstige": "Sonstiges", "other": "Sonstiges",
    ]

    /// Kind of a row from its "Art" cell. For plug-in hybrids the kind also gives the unit: "Laden" is kWh, "Tanken"
    /// litres. Without a kind, a row with an amount is a fill-up and one without is an expense.
    public static func kind(_ text: String?, amount: Double?, defaultCategory: String) -> Kind {
        let value = normalize(text ?? "")
        if chargeWords.contains(value) { return Kind(isFillup: true, category: "Tankfuellung", unit: "kwh") }
        if fillupWords.contains(value) { return Kind(isFillup: true, category: "Tankfuellung", unit: "l") }
        if value.isEmpty, let amount, amount > 0 { return Kind(isFillup: true, category: "Tankfuellung", unit: nil) }
        if value.isEmpty { return Kind(isFillup: false, category: defaultCategory, unit: nil) }
        return Kind(isFillup: false,
                    category: knownCategories[value] ?? (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                    unit: nil)
    }

    // MARK: Conversion

    /// Converts all rows with the given column assignment. Rows that cannot be imported land in `errors`; the rest in
    /// `fillups` and `entries`, with their categories matched against the catalog.
    public static func plan(rows: [[String]], mapping: [ImportField: Int], defaultCategory: String,
                            fuels: [ImportFuel], categories: [ImportCategory]) -> ImportPlan {
        var plan = ImportPlan()
        let byKey = Dictionary(categories.filter { $0.form != "fillup" && !$0.isLegacy }.map { ($0.key, $0) },
                               uniquingKeysWith: { first, _ in first })
        let byName = Dictionary(categories.filter { $0.form != "fillup" && !$0.isLegacy }
            .map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        for (offset, row) in rows.enumerated() {
            let line = offset + 2
            func cell(_ field: ImportField) -> String? {
                guard let index = mapping[field], index < row.count else { return nil }
                return row[index]
            }
            let date = Self.date(cell(.date))
            let amount = number(cell(.amount))
            var cost = number(cell(.cost))
            let pricePerUnit = number(cell(.pricePerUnit))
            let odometer = integer(cell(.odometer))
            let kind = kind(cell(.kind), amount: amount, defaultCategory: defaultCategory)
            let place = (cell(.place) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let note = (cell(.note) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // The "Einheit" column wins over the kind; the API only takes it for plug-in hybrids.
            let unit = Self.unit(cell(.unit)) ?? kind.unit

            if cost == nil, let amount, let pricePerUnit { cost = (amount * pricePerUnit * 100).rounded() / 100 }

            var error: ImportRowError?
            if date == nil {
                error = .dateInvalid
            } else if kind.isFillup, amount == nil || amount! < 0 {
                error = .amountMissing
            } else if cost == nil || cost! < 0 {
                error = .costInvalid
            }

            let isFull: Bool? = kind.isFillup ? yesNo(cell(.full)) : nil
            let chargeType: String? = kind.isFillup ? Self.chargeType(cell(.chargeType)) : nil
            var categoryText = kind.category
            var entryCategory = kind.category
            var entryDescription: String? = note.isEmpty ? nil : note

            if !kind.isFillup {
                let original = kind.category
                let match = byKey[original] ?? byName[original.lowercased()]
                if let match, match.isAvailable || ["trip", "odometer"].contains(match.form) {
                    entryCategory = match.key
                    categoryText = match.name
                } else {
                    entryCategory = "Sonstiges"
                    entryDescription = [original, note].filter { !$0.isEmpty }.joined(separator: " – ")
                    categoryText = "Sonstiges (\(original))"
                    if error == nil { plan.otherCategories[original, default: 0] += 1 }
                }
            } else {
                categoryText = unit == "kwh" ? "Ladevorgang" : "Tankfüllung"
            }

            plan.preview.append(ImportPreviewRow(
                number: line, date: date, isFillup: kind.isFillup, categoryText: categoryText, odometerKm: odometer,
                amount: kind.isFillup ? amount : nil, unit: kind.isFillup ? unit : nil, cost: cost, isFull: isFull,
                chargeType: chargeType, place: place, note: note, error: error
            ))
            if let error {
                plan.errors[line] = error
                continue
            }

            let timestamp = date! + "T12:00:00.000Z"
            if kind.isFillup {
                var fillup = ImportFillup(
                    filledAt: timestamp, odometerKm: odometer, amount: amount!, totalCostEur: cost!,
                    station: place.isEmpty ? nil : place, isFull: isFull!,
                    skipPrevious: yesNo(cell(.gapBefore), defaultValue: false), unit: unit,
                    fuel: fuel(cell(.fuel), catalog: fuels)
                )
                // Charge details only for rows that charge; fill-ups in litres or kilograms get none.
                if unit != "l", unit != "kg" {
                    fillup.chargeType = chargeType
                    fillup.socBeforePct = optionalInteger(cell(.socBefore))
                    fillup.socAfterPct = optionalInteger(cell(.socAfter))
                    fillup.chargeMinutes = optionalInteger(cell(.chargeMinutes))
                }
                plan.fillups.append(fillup)
                plan.fillupLines.append(line)
            } else {
                plan.entries.append(ImportEntry(
                    occurredAt: timestamp, category: entryCategory, amountEur: cost!, odometerKm: odometer,
                    vendor: place.isEmpty ? nil : place, description: entryDescription
                ))
                plan.entryLines.append(line)
            }
        }
        return plan
    }

    private static func optionalInteger(_ text: String?) -> Int? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return integer(text)
    }

    // MARK: Template

    /// Sample file in the format of the export, for the vehicle's drive type (like the web app's template).
    public static func template(fuelType: String) -> Data {
        let lines: [String]
        if fuelType == "phev" {
            lines = [
                "Datum;Kategorie;Tachostand (km);Menge;Einheit;Kosten (EUR);Voll;Ort/Anbieter;Beschreibung;Ladeart;Ladestand vorher (%);Ladestand nachher (%);Ladedauer (min)",
                "05.01.2026;Laden;38302;14,80;kWh;4,14;ja;Zuhause (Wallbox);;Zu Hause;25;90;420",
                "05.01.2026;Tanken;38337;41,20;l;72,10;ja;Aral Musterstadt;;;;;",
                "06.01.2026;Laden;38390;9,60;kWh;2,69;ja;Zuhause (Wallbox);;Zu Hause;;;",
                "02.01.2026;Versicherung;;;;420,00;;HUK;Jahresbeitrag",
                "15.03.2026;Werkstatt;39100;;;189,00;;ATU;Bremsbeläge vorne",
            ]
        } else {
            let electric = fuelType == "electric"
            let unit = EntryCSV.unitLabel(fuelType)
            let full = electric ? "Vollgeladen" : "Vollgetankt"
            let chargeHeader = electric ? ";Ladeart;Ladestand vorher (%);Ladestand nachher (%);Ladedauer (min)" : ""
            let examples = electric
                ? ["05.01.2026;Laden;38337;24,50;6,13;ja;Zuhause (Wallbox);;Zu Hause;20;100;540",
                   "20.01.2026;Laden;38700;18,00;12,42;nein;EnBW Schnelllader;;DC;15;80;32"]
                : ["05.01.2026;Tankfüllung;38337;33,50;61,20;ja;Aral Musterstadt;",
                   "20.01.2026;Tankfüllung;38700;15,00;27,90;nein;Shell;"]
            lines = ["Datum;Kategorie;Tachostand (km);Menge (\(unit));Kosten (EUR);\(full);Ort/Anbieter;Beschreibung\(chargeHeader)"]
                + examples
                + ["02.01.2026;Versicherung;;;420,00;;HUK;Jahresbeitrag",
                   "15.03.2026;Werkstatt;39100;;189,00;;ATU;Bremsbeläge vorne"]
        }
        return Data([0xEF, 0xBB, 0xBF]) + Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    public static let templateFileName = "fuelstat_import_vorlage.csv"
}

import Foundation
import Testing
@testable import FuelstatCore

// Cases of the web app's tests/CsvImportTest.php, plus what is specific to Swift (line breaks) and the round trip with
// the app's own export.
struct CSVImportTests {
    private func table(_ text: String) -> CSVTable { CSVTable.read(Data(text.utf8)) }

    private func plan(_ text: String, category: String = "Werkstatt", fuels: [ImportFuel] = [],
                      categories: [ImportCategory] = []) -> ImportPlan {
        let table = table(text)
        return CSVImport.plan(rows: table.rows, mapping: CSVImport.detectMapping(header: table.header),
                              defaultCategory: category, fuels: fuels, categories: categories)
    }

    // MARK: Values

    @Test func numbers() {
        #expect(CSVImport.number("1.234,56") == 1234.56)
        #expect(CSVImport.number("1,234.56") == 1234.56)
        #expect(CSVImport.number("41,2 l") == 41.2)
        #expect(CSVImport.number("75.31 €") == 75.31)
        #expect(CSVImport.number("") == nil)
        #expect(CSVImport.number("-") == nil)
        #expect(CSVImport.number("1.2.3") == nil)
        #expect(CSVImport.number("-4,5") == -4.5)
        #expect(CSVImport.integer("39.945") == 39945)
        #expect(CSVImport.integer("39945,5") == 39945)
        #expect(CSVImport.integer("39 945 km") == 39945)
        #expect(CSVImport.integer("") == nil)
    }

    @Test func dates() {
        #expect(CSVImport.date("31.12.2025") == "2025-12-31")
        #expect(CSVImport.date("1.2.25") == "2025-02-01")
        #expect(CSVImport.date("1.2.70") == "1970-02-01")
        #expect(CSVImport.date("2025-12-31 14:30") == "2025-12-31")
        #expect(CSVImport.date("31/12/2025") == "2025-12-31")
        #expect(CSVImport.date("31.02.2025") == nil)
        #expect(CSVImport.date("29.02.2024") == "2024-02-29")
        #expect(CSVImport.date("29.02.2100") == nil)
        #expect(CSVImport.date("morgen") == nil)
        #expect(CSVImport.date("") == nil)
    }

    @Test func yesNoAndKind() {
        #expect(CSVImport.yesNo("") == true)
        #expect(CSVImport.yesNo("nein") == false)
        #expect(CSVImport.yesNo("", defaultValue: false) == false)
        #expect(CSVImport.yesNo("ja", defaultValue: false) == true)
        #expect(CSVImport.kind("Tankfüllung", amount: nil, defaultCategory: "Werkstatt").isFillup)
        #expect(CSVImport.kind("", amount: 40, defaultCategory: "Werkstatt").isFillup)
        #expect(CSVImport.kind("TÜV", amount: nil, defaultCategory: "Werkstatt").category == "TUV")
        #expect(CSVImport.kind("", amount: nil, defaultCategory: "Werkstatt").category == "Werkstatt")
        #expect(CSVImport.kind("Ladevorgang", amount: nil, defaultCategory: "Werkstatt")
            == .init(isFillup: true, category: "Tankfuellung", unit: "kwh"))
        #expect(CSVImport.unit("Liter") == "l" && CSVImport.unit("KWH") == "kwh" && CSVImport.unit("egal") == nil)
    }

    @Test func chargeTypes() {
        #expect(CSVImport.chargeType("Zu Hause") == "home" && CSVImport.chargeType("Wallbox") == "home")
        #expect(CSVImport.chargeType("home") == "home")
        #expect(CSVImport.chargeType("AC öffentlich") == "ac_public" && CSVImport.chargeType("Öffentlich") == "ac_public")
        #expect(CSVImport.chargeType("ac_public") == "ac_public")
        #expect(CSVImport.chargeType("DC") == "dc" && CSVImport.chargeType("Schnelllader") == "dc")
        #expect(CSVImport.chargeType("AC/DC") == "dc" && CSVImport.chargeType("HPC") == "dc")
        #expect(CSVImport.chargeType("") == nil && CSVImport.chargeType("irgendwas") == nil)
    }

    @Test func fuels() {
        let catalog = [ImportFuel(key: "super_e10", name: "Super E10"),
                       ImportFuel(key: "premium_diesel", name: "Premium-Diesel"),
                       ImportFuel(key: "lpg", name: "Autogas (LPG)")]
        #expect(CSVImport.fuel("Super E10", catalog: catalog) == "super_e10")
        #expect(CSVImport.fuel("premium_diesel", catalog: catalog) == "premium_diesel")
        #expect(CSVImport.fuel("Premium-Diesel", catalog: catalog) == "premium_diesel")
        #expect(CSVImport.fuel("Autogas (LPG)", catalog: catalog) == "lpg")
        #expect(CSVImport.fuel("E10", catalog: catalog) == "super_e10")
        #expect(CSVImport.fuel("Autogas", catalog: catalog) == "lpg")
        #expect(CSVImport.fuel("Kerosin", catalog: catalog) == nil)
        #expect(CSVImport.fuel("", catalog: catalog) == nil)
        #expect(CSVImport.detectMapping(header: ["Datum", "Sorte", "Menge"])[.fuel] == 1)
    }

    // MARK: Reading

    @Test func readsLineBreaksOfAllKinds() {
        #expect(table("a;b\r\n1;2\r\n3;4\r\n").rows == [["1", "2"], ["3", "4"]])
        #expect(table("a;b\n1;2\n3;4").rows == [["1", "2"], ["3", "4"]])
        #expect(table("a;b\r1;2\r3;4\r").rows == [["1", "2"], ["3", "4"]])
        #expect(table("a;b\r\n\r\n1;2\r\n;\r\n").rows == [["1", "2"]], "blank lines are skipped")
    }

    @Test func quotedFieldsMayContainDelimitersQuotesAndLineBreaks() {
        let result = table("a;b;c\r\n\"x;y\";\"sagte \"\"hi\"\"\";\"zwei\r\nZeilen\"\r\n1;2;3\r\n")
        #expect(result.rows == [["x;y", "sagte \"hi\"", "zwei\r\nZeilen"], ["1", "2", "3"]])
    }

    @Test func detectsTheDelimiter() {
        #expect(table("a;b;c\n1;2;3").delimiter == ";")
        #expect(table("a,b,c\n1,2,3").delimiter == ",")
        #expect(table("a\tb\tc\n1\t2\t3").delimiter == "\t")
        #expect(table("a;b,c\n1;2,3").delimiter == ";", "a tie goes to the semicolon")
    }

    @Test func decodesUTF8WithAndWithoutBOMAndWindows1252() {
        let text = "Datum;Beschreibung\n01.01.2026;Bremsbeläge\n"
        #expect(table(text).rows == [["01.01.2026", "Bremsbeläge"]])
        #expect(CSVTable.read(Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)).header == ["Datum", "Beschreibung"])
        #expect(CSVTable.read(text.data(using: .windowsCP1252)!).rows == [["01.01.2026", "Bremsbeläge"]])
    }

    @Test func emptyFileHasNoRows() {
        #expect(table("").header.isEmpty)
        #expect(table("Datum;Kosten\n").rows.isEmpty)
    }

    // MARK: Own export is recognised (also Windows-1252, semicolon, no BOM)

    @Test func recognisesTheExportOfTheWebApp() {
        let csv = "Datum;Kategorie;Tachostand (km);Menge (l);Kosten (EUR);Vollgetankt;Verbrauch (l/100km);Ort/Anbieter;Beschreibung\r\n"
            + "05.01.2026;Tankfüllung;38.337;33,50;61,20;ja;7,94;SB Tankstelle;\r\n"
            + "02.01.2026;Versicherung;;;420,00;;;HUK;Jahresbeitrag\r\n"
            + "20.02.2026;Tankfüllung;40.200;20,00;36,50;nein;;;\r\n"
            + "kaputt;Tankfüllung;1;1;1;;;;\r\n"
        let table = CSVTable.read(csv.data(using: .windowsCP1252)!)
        #expect(table.rows.count == 4)
        let mapping = CSVImport.detectMapping(header: table.header)
        #expect(mapping == [.date: 0, .kind: 1, .odometer: 2, .amount: 3, .cost: 4, .full: 5, .place: 7, .note: 8])
        let result = CSVImport.plan(rows: table.rows, mapping: mapping, defaultCategory: "Werkstatt", fuels: [],
                                    categories: [.init(key: "Versicherung", name: "Versicherung", form: "expense",
                                                       isLegacy: false, isAvailable: true)])
        #expect(result.fillups.count == 2)
        #expect(result.entries.count == 1)
        #expect(result.errors == [5: .dateInvalid])
        #expect(result.fillups[0] == ImportFillup(
            filledAt: "2026-01-05T12:00:00.000Z", odometerKm: 38337, amount: 33.5, totalCostEur: 61.2,
            station: "SB Tankstelle", isFull: true, skipPrevious: false, unit: "l"))
        #expect(result.fillups[1].isFull == false)
        #expect(result.entries[0].category == "Versicherung" && result.entries[0].odometerKm == nil
            && result.entries[0].vendor == "HUK")
        #expect(result.fillupLines == [2, 4] && result.entryLines == [3])
    }

    @Test func costComesFromAmountTimesPriceAndWithoutUnitTheAPIDecides() throws {
        let result = plan("date,odometer,liters,price per liter\n2025-03-01,1000,40,1.75\n")
        #expect(result.fillups[0].totalCostEur == 70)
        #expect(result.fillups[0].unit == nil)
    }

    @Test func plugInHybridUnitComesFromTheColumnThenTheKind() {
        let result = plan("Datum;Kategorie;Tachostand (km);Menge;Einheit;Kosten (EUR);Voll\n"
            + "05.01.2026;Laden;38302;14,80;kWh;4,14;ja\n"
            + "05.01.2026;Tanken;38337;41,20;l;72,10;ja\n"
            + "06.01.2026;Laden;38390;9,60;;2,69;ja\n"
            + "07.01.2026;Tankfüllung;38420;12,00;kWh;3,36;nein\n")
        #expect(result.fillups.map(\.unit) == ["kwh", "l", "kwh", "kwh"])
        #expect(result.preview.map(\.unit) == ["kwh", "l", "kwh", "kwh"])
    }

    @Test func chargeDetailsOnlyForChargingRowsAndOnlyWhenFilled() {
        let result = plan("Datum;Kategorie;Tachostand (km);Menge;Einheit;Kosten (EUR);Voll;Ort/Anbieter;Beschreibung;Ladeart;Ladestand vorher (%);Ladestand nachher (%);Ladedauer (min)\n"
            + "05.01.2026;Laden;38302;14,80;kWh;4,14;nein;Wallbox;;Zu Hause;25;90;420\n"
            + "05.01.2026;Tanken;38337;41,20;l;72,10;ja;Aral;;Zu Hause;20;80;30\n"
            + "06.01.2026;Laden;38390;9,60;kWh;2,69;ja;Wallbox;;;;;\n")
        let charge = result.fillups[0]
        #expect(charge.chargeType == "home" && charge.socBeforePct == 25 && charge.socAfterPct == 90
            && charge.chargeMinutes == 420)
        #expect(result.fillups[1].chargeType == nil && result.fillups[1].socAfterPct == nil)
        #expect(result.fillups[2].chargeType == nil && result.fillups[2].socAfterPct == nil)
    }

    @Test func categoriesAreMatchedAgainstTheCatalog() {
        let catalog = [
            ImportCategory(key: "Werkstatt", name: "Werkstatt", form: "expense", isLegacy: false, isAvailable: true),
            ImportCategory(key: "TUV", name: "TÜV", form: "expense", isLegacy: false, isAvailable: true),
            ImportCategory(key: "Parken", name: "Parken", form: "expense", isLegacy: false, isAvailable: false),
            ImportCategory(key: "custom:1", name: "Fähre", form: "expense", isLegacy: false, isAvailable: true),
            ImportCategory(key: "Fahrt", name: "Fahrt", form: "trip", isLegacy: false, isAvailable: false),
            ImportCategory(key: "Glasbruch", name: "Glasbruch", form: "expense", isLegacy: true, isAvailable: true),
        ]
        let result = plan("Datum;Kategorie;Kosten (EUR);Beschreibung\n"
            + "01.02.2026;TÜV;120;HU\n"
            + "02.02.2026;fähre;30;\n"
            + "03.02.2026;Parken;3;Bahnhof\n"
            + "04.02.2026;Schlüsseldienst;80;\n"
            + "05.02.2026;Glasbruch;200;\n"
            + "06.02.2026;Fahrt;0;A → B\n", categories: catalog)
        #expect(result.entries.map(\.category) == ["TUV", "custom:1", "Sonstiges", "Sonstiges", "Sonstiges", "Fahrt"])
        #expect(result.entries[2].description == "Parken – Bahnhof", "a locked category stays in the description")
        #expect(result.entries[3].description == "Schlüsseldienst")
        #expect(result.entries[4].description == "Glasbruch", "legacy categories are not matched")
        #expect(result.otherCategories == ["Parken": 1, "Schlüsseldienst": 1, "Glasbruch": 1])
        #expect(result.preview[3].categoryText == "Sonstiges (Schlüsseldienst)")
        #expect(result.preview[0].categoryText == "TÜV")
    }

    @Test func rowErrors() {
        let result = plan("Datum;Kategorie;Menge;Kosten (EUR)\n"
            + "morgen;Tanken;10;5\n"
            + "01.01.2026;Tanken;;5\n"
            + "01.01.2026;Versicherung;;\n"
            + "01.01.2026;Versicherung;;-5\n")
        #expect(result.errors == [2: .dateInvalid, 3: .amountMissing, 4: .costInvalid, 5: .costInvalid])
        #expect(result.isEmpty)
        #expect(result.preview.count == 4)
    }

    // MARK: Payload

    @Test func payloadHasTheShapeOfTheWebApp() throws {
        let result = plan("Datum;Kategorie;Tachostand (km);Menge;Kosten (EUR);Voll;Ort/Anbieter\n"
            + "05.01.2026;Tanken;;33,5;61,2;ja;\n"
            + "02.01.2026;Versicherung;;;420;;HUK\n",
            categories: [.init(key: "Versicherung", name: "Versicherung", form: "expense", isLegacy: false,
                               isAvailable: true)])
        let fillup = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result.fillups[0])) as! [String: Any]
        #expect(fillup["filledAt"] as? String == "2026-01-05T12:00:00.000Z")
        #expect(fillup["odometerKm"] is NSNull, "a missing odometer is sent as null")
        #expect(fillup["station"] is NSNull)
        #expect(fillup["skipPrevious"] as? Bool == false)
        #expect(fillup["fuel"] == nil && fillup["chargeType"] == nil)
        let entry = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result.entries[0])) as! [String: Any]
        #expect(entry["occurredAt"] as? String == "2026-01-02T12:00:00.000Z")
        #expect(entry["odometerKm"] is NSNull && entry["description"] is NSNull)
        #expect(entry["vendor"] as? String == "HUK")
    }

    @Test func chunksOf500WithTheirOffset() {
        var plan = ImportPlan()
        plan.fillups = Array(repeating: ImportFillup(filledAt: "x", amount: 1, totalCostEur: 1, isFull: true,
                                                     skipPrevious: false), count: 1201)
        #expect(plan.fillupChunks.map(\.offset) == [0, 500, 1000])
        #expect(plan.fillupChunks.map(\.items.count) == [500, 500, 201])
        #expect(plan.entryChunks.isEmpty)
    }

    @Test func excludingRemovesRowsByFileLine() {
        let result = plan("Datum;Kategorie;Menge;Kosten (EUR)\n"
            + "01.01.2026;Tanken;10;5\n"
            + "02.01.2026;Tanken;11;6\n"
            + "03.01.2026;Versicherung;;7\n")
        let rest = result.excluding(lines: [3])
        #expect(rest.fillups.map(\.amount) == [10])
        #expect(rest.fillupLines == [2] && rest.entryLines == [4])
        #expect(result.excluding(lines: []) == result)
    }

    // MARK: Header names

    @Test func headerNamesAreNormalised() {
        #expect(CSVImport.normalize("Lücke davor") == "lueckedavor")
        #expect(CSVImport.normalize(" Menge (kWh) ") == "menge")
        #expect(CSVImport.normalize("Ladestand vorher (%)") == "ladestandvorher")
        #expect(CSVImport.normalize("Verbrauch (l/100km)") == "verbrauch")
        #expect(CSVImport.normalize("Ünicode".decomposedStringWithCanonicalMapping) == "uenicode")
    }

    // MARK: Round trip with the app's own export

    private let day = ISO8601DateFormatter().date(from: "2026-03-05T10:00:00Z")!

    private func roundTrip(_ vehicle: EntryCSVVehicle, rows: [EntryCSVRow], fuels: [ImportFuel] = []) -> ImportPlan {
        let table = CSVTable.read(EntryCSV.make(rows: rows, vehicle: vehicle))
        let mapping = CSVImport.detectMapping(header: table.header)
        #expect(mapping[.date] == 0 && mapping[.kind] == 1)
        #expect(!mapping.values.contains(table.header.firstIndex { $0.hasPrefix("Verbrauch") } ?? -1),
                "the consumption column is not imported")
        return CSVImport.plan(rows: table.rows, mapping: mapping, defaultCategory: "Werkstatt", fuels: fuels,
                              categories: [.init(key: "Versicherung", name: "Versicherung", form: "expense",
                                                 isLegacy: false, isAvailable: true)])
    }

    @Test func exportOfADieselCarComesBack() {
        let vehicle = EntryCSVVehicle(name: "Kia", fuelType: "diesel")
        let result = roundTrip(vehicle, rows: [
            EntryCSVRow(date: day, category: "Tankfuellung", odometerKm: 12845, amount: 47.2, unit: "l", cost: 86.3,
                        isFull: false, skipPrevious: true, consumption: 5.8, place: "Aral; Nord", description: nil),
            EntryCSVRow(date: day, category: "Versicherung", cost: 300, place: "HUK", description: "Jahr\r\nBeitrag"),
        ])
        #expect(result.errors.isEmpty)
        #expect(result.fillups == [ImportFillup(
            filledAt: "2026-03-05T12:00:00.000Z", odometerKm: 12845, amount: 47.2, totalCostEur: 86.3,
            station: "Aral; Nord", isFull: false, skipPrevious: true, unit: "l")])
        #expect(result.entries.count == 1)
        #expect(result.entries[0].description == "Jahr\r\nBeitrag", "a line break inside a quoted field survives")
        #expect(result.entries[0].amountEur == 300 && result.entries[0].vendor == "HUK")
    }

    @Test func exportOfAnElectricCarComesBack() {
        let vehicle = EntryCSVVehicle(name: "ID.3", fuelType: "electric")
        let result = roundTrip(vehicle, rows: [
            EntryCSVRow(date: day, category: "Tankfuellung", odometerKm: 5000, amount: 40, unit: "kwh", cost: 12,
                        isFull: true, skipPrevious: false, consumption: 16, place: "Wallbox"),
        ])
        #expect(result.errors.isEmpty)
        #expect(result.fillups.count == 1)
        #expect(result.fillups[0].unit == "kwh", "Ladevorgang means kWh")
        #expect(result.fillups[0].isFull == true)
    }

    @Test func exportOfAPlugInHybridWithSeveralFuelsComesBack() {
        let vehicle = EntryCSVVehicle(name: "Golf GTE", fuelType: "phev", hasSeveralFuels: true,
                                      fuelNames: ["super_e10": "Super E10", "electricity": "Strom"])
        let result = roundTrip(vehicle, rows: [
            EntryCSVRow(date: day, category: "Tankfuellung", odometerKm: 1000, amount: 30, unit: "l",
                        fuel: "super_e10", cost: 55, isFull: true, skipPrevious: false),
            EntryCSVRow(date: day, category: "Tankfuellung", odometerKm: 1100, amount: 10, unit: "kwh",
                        fuel: "electricity", cost: 3, isFull: false, skipPrevious: false),
        ], fuels: [.init(key: "super_e10", name: "Super E10"), .init(key: "electricity", name: "Strom")])
        #expect(result.errors.isEmpty)
        #expect(result.fillups.map(\.unit) == ["l", "kwh"])
        #expect(result.fillups.map(\.fuel) == ["super_e10", "electricity"])
        #expect(result.fillups.map(\.isFull) == [true, false])
    }

    @Test func everyFullColumnNameOfTheAPIExportIsRecognised() {
        // Header names of GET /vehicles/:id/export (docs/api.md): the "full" column per drive type.
        for name in ["Vollgetankt", "Vollgeladen", "Voll getankt/geladen", "Voll"] {
            let mapping = CSVImport.detectMapping(header: ["Datum", "Kategorie", "Menge", "Kosten (EUR)", name])
            #expect(mapping[.full] == 4, "\(name)")
        }
        let partial = plan("Datum;Kategorie;Menge (l);Kosten (EUR);Voll getankt/geladen\n01.01.2026;Tankfüllung;10;5;nein\n")
        #expect(partial.fillups[0].isFull == false)
    }

    @Test func templatesAreImportable() {
        for type in ["diesel", "electric", "phev", "cng"] {
            let table = CSVTable.read(CSVImport.template(fuelType: type))
            let mapping = CSVImport.detectMapping(header: table.header)
            let result = CSVImport.plan(rows: table.rows, mapping: mapping, defaultCategory: "Werkstatt", fuels: [],
                                        categories: [.init(key: "Versicherung", name: "Versicherung", form: "expense",
                                                           isLegacy: false, isAvailable: true),
                                                     .init(key: "Werkstatt", name: "Werkstatt", form: "expense",
                                                           isLegacy: false, isAvailable: true)])
            #expect(result.errors.isEmpty, "template for \(type)")
            #expect(result.fillups.count + result.entries.count == table.rows.count)
            #expect(result.entries.count == 2)
        }
    }

    // MARK: Export encoder

    @Test func exportQuotesFieldsWithWindowsLineBreaks() {
        #expect(EntryCSV.encode("a\r\nb") == "\"a\r\nb\"")
        #expect(EntryCSV.encode("a\rb") == "\"a\rb\"")
    }
}

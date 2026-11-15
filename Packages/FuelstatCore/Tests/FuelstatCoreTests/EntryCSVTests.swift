import Foundation
import Testing
@testable import FuelstatCore

struct EntryCSVTests {
    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func lines(_ data: Data) -> [String] {
        String(decoding: data.dropFirst(3), as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    private let diesel = EntryCSVVehicle(name: "Kia Ceed", fuelType: "diesel",
                                         categoryNames: ["Versicherung": "Versicherung"])

    @Test func startsWithTheByteOrderMarkAndEndsWithANewline() {
        let data = EntryCSV.make(rows: [], vehicle: diesel)
        #expect(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])
        #expect(String(decoding: data.dropFirst(3), as: UTF8.self).hasSuffix("\n"))
    }

    @Test func headerOfAPetrolCar() {
        #expect(EntryCSV.header(for: diesel) == ["Datum", "Kategorie", "Tachostand (km)", "Menge (l)", "Kosten (EUR)",
                                                  "Vollgetankt", "Lücke davor", "Verbrauch (l/100km)", "Ort/Anbieter",
                                                  "Beschreibung"])
    }

    @Test func headerOfAnElectricCarHasChargingColumns() {
        let header = EntryCSV.header(for: .init(name: "ID.3", fuelType: "electric"))
        #expect(header == ["Datum", "Kategorie", "Tachostand (km)", "Menge (kWh)", "Kosten (EUR)", "Vollgeladen",
                           "Lücke davor", "Ladeart", "Ladestand vorher (%)", "Ladestand nachher (%)", "Ladedauer (min)",
                           "Verbrauch (kWh/100km)", "Ort/Anbieter", "Beschreibung"])
    }

    @Test func headerOfAPlugInHybridWithSeveralFuels() {
        let header = EntryCSV.header(for: .init(name: "Golf GTE", fuelType: "phev", hasSeveralFuels: true))
        #expect(header.prefix(7) == ["Datum", "Kategorie", "Tachostand (km)", "Menge", "Sorte", "Einheit", "Kosten (EUR)"])
        #expect(header.contains("Ladeart"))
        #expect(header.firstIndex(of: "Lücke davor")! + 1 == header.firstIndex(of: "Ladeart")!)
    }

    @Test func fillUpRowForAPetrolCar() {
        let row = EntryCSVRow(date: date("2026-03-05T10:00:00Z"), category: "Tankfuellung", odometerKm: 12845,
                              amount: 47.2, unit: "l", cost: 86.3, isFull: true, skipPrevious: false,
                              consumption: 5.837, place: "Aral, Hauptstr. 1", description: nil)
        let csv = lines(EntryCSV.make(rows: [row], vehicle: diesel))
        #expect(csv[1] == "05.03.2026;Tankfüllung;12845;47,20;86,30;ja;nein;5,84;\"Aral, Hauptstr. 1\";")
    }

    @Test func expenseRowHasNoFillingColumns() {
        let row = EntryCSVRow(date: date("2026-01-15T09:00:00Z"), category: "Versicherung", cost: 300)
        let csv = lines(EntryCSV.make(rows: [row], vehicle: diesel))
        #expect(csv[1] == "15.01.2026;Versicherung;;;300,00;;;;;")
    }

    @Test func rowsAreSortedByDateAscending() {
        let later = EntryCSVRow(date: date("2026-05-01T10:00:00Z"), category: "Versicherung", cost: 1)
        let earlier = EntryCSVRow(date: date("2026-02-01T10:00:00Z"), category: "Versicherung", cost: 2)
        let csv = lines(EntryCSV.make(rows: [later, earlier], vehicle: diesel))
        #expect(csv[1].hasPrefix("01.02.2026"))
        #expect(csv[2].hasPrefix("01.05.2026"))
    }

    @Test func datesUseBerlinTime() {
        // 23:30 UTC on New Year's Eve is already 1 January in Berlin.
        let row = EntryCSVRow(date: date("2025-12-31T23:30:00Z"), category: "Versicherung", cost: 1)
        #expect(lines(EntryCSV.make(rows: [row], vehicle: diesel))[1].hasPrefix("01.01.2026"))
    }

    @Test func plugInHybridRowsNameTheUnitAndTheGrade() {
        let vehicle = EntryCSVVehicle(name: "Golf", fuelType: "phev", hasSeveralFuels: true,
                                      fuelNames: ["super_e5": "Super E5", "electricity": "Strom"])
        let row = EntryCSVRow(date: date("2026-03-05T10:00:00Z"), category: "Tankfuellung", odometerKm: 1000,
                              amount: 20, unit: "kwh", fuel: "electricity", cost: 7, isFull: true, skipPrevious: false)
        let csv = lines(EntryCSV.make(rows: [row], vehicle: vehicle))
        #expect(csv[1] == "05.03.2026;Ladevorgang;1000;20,00;Strom;kWh;7,00;ja;nein;;;;;;;")
        #expect(csv[1].split(separator: ";", omittingEmptySubsequences: false).count == csv[0].split(separator: ";").count)
    }

    @Test func everyRowHasAsManyFieldsAsTheHeader() {
        for fuelType in ["diesel", "electric", "phev", "cng"] {
            let vehicle = EntryCSVVehicle(name: "x", fuelType: fuelType, hasSeveralFuels: fuelType == "phev")
            let rows = [EntryCSVRow(date: .now, category: "Tankfuellung", amount: 1, unit: "l", cost: 1),
                        EntryCSVRow(date: .now, category: "Wartung", cost: 1)]
            let header = EntryCSV.header(for: vehicle).count
            for row in rows {
                #expect(EntryCSV.fields(for: row, vehicle: vehicle).count == header, "\(fuelType) \(row.category)")
            }
        }
    }

    @Test func placeholderOdometerStaysEmpty() {
        let row = EntryCSVRow(date: .now, category: "Tankfuellung", odometerKm: 999, odometerEstimated: true,
                              amount: 1, unit: "l", cost: 1)
        #expect(EntryCSV.fields(for: row, vehicle: diesel)[2] == "")
    }

    @Test func formulasAreDefusedForSpreadsheets() {
        #expect(EntryCSV.spreadsheetSafe("=SUMME(A1)") == "'=SUMME(A1)")
        #expect(EntryCSV.spreadsheetSafe("+49 123") == "'+49 123")
        #expect(EntryCSV.spreadsheetSafe("-1") == "'-1")
        #expect(EntryCSV.spreadsheetSafe("@home") == "'@home")
        #expect(EntryCSV.spreadsheetSafe("Aral") == "Aral")
        #expect(EntryCSV.spreadsheetSafe("") == "")
    }

    @Test func fieldsAreQuotedLikePHP() {
        #expect(EntryCSV.encode("Aral") == "Aral")
        #expect(EntryCSV.encode("Aral Nord") == "\"Aral Nord\"")
        #expect(EntryCSV.encode("a;b") == "\"a;b\"")
        #expect(EntryCSV.encode("sagte \"hallo\"") == "\"sagte \"\"hallo\"\"\"")
        #expect(EntryCSV.encode("zwei\nZeilen") == "\"zwei\nZeilen\"")
        #expect(EntryCSV.encode("") == "")
    }

    @Test func fileNameKeepsLettersDigitsUnderscoreAndDash() {
        #expect(EntryCSV.fileName(vehicleName: "Kia Ceed", year: nil) == "Kia_Ceed.csv")
        #expect(EntryCSV.fileName(vehicleName: "Papas Golf (GTI)!", year: 2026) == "Papas_Golf_GTI__2026.csv")
        #expect(EntryCSV.fileName(vehicleName: "Müller-Wagen", year: nil) == "M_ller-Wagen.csv")
        #expect(EntryCSV.fileName(vehicleName: "", year: nil) == "fahrzeug.csv")
    }
}

struct EntryCSVYearTests {
    @Test func yearsAreCountedInBerlin() {
        let newYearsEve = ISO8601DateFormatter().date(from: "2025-12-31T23:30:00Z")!
        #expect(EntryCSV.year(of: newYearsEve) == 2026)
        #expect(EntryCSV.year(of: ISO8601DateFormatter().date(from: "2026-06-15T12:00:00Z")!) == 2026)
    }
}

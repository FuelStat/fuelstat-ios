import Foundation
import Testing
@testable import FuelstatCore

struct VehicleCostsTests {
    /// Example from `docs/api.md` (FuelStat/fuelstat), `GET /vehicles/:id/costs`, plus `categories`, `energies`, `years`.
    private let example = Data("""
    {
      "year": null,
      "currency": "EUR",
      "total": { "energy": 165, "expenses": 300, "total": 465 },
      "distanceKm": 1000,
      "costPerKm": { "energy": 0.105, "total": 0.465 },
      "perMonth": 93,
      "monthCount": 5,
      "currentMonth": { "month": "2026-03", "energy": 0, "expenses": 0, "total": 0 },
      "previousMonth": { "month": "2026-02", "energy": 55, "expenses": 0, "total": 55 },
      "months": [
        { "month": "2026-02", "energy": 55, "expenses": 0, "total": 55, "count": 2,
          "counts": { "fuel": 1, "charge": 0, "expense": 0, "trip": 1, "odometer": 0 },
          "byType": { "fuel": 55, "charge": 0, "expense": 0 },
          "byCategory": { "Tankfuellung:l": 55 } },
        { "month": "2026-01", "energy": 110, "expenses": "300.00", "total": "410.00", "count": 3,
          "byCategory": { "Tankfuellung:l": "110.00", "Versicherung": 300 } }
      ],
      "categories": [{ "key": "Versicherung", "total": 300, "count": 1 },
                     { "key": "Tankfuellung:l", "total": 165, "count": 3 }],
      "energies": [{ "energy": "petrol", "name": "Benzin", "total": 165, "count": 3, "share": 100 }],
      "years": [2026, 2025]
    }
    """.utf8)

    @Test func decodesTheDocumentedExample() throws {
        let c = try JSONDecoder().decode(VehicleCosts.self, from: example)
        #expect(c.year == nil)
        #expect(c.currency == "EUR")
        #expect(c.total == .init(energy: 165, expenses: 300, total: 465))
        #expect(c.distanceKm == 1000)
        #expect(c.costPerKmEnergy == 0.105)
        #expect(c.costPerKmTotal == 0.465)
        #expect(c.perMonth == 93)
        #expect(c.monthCount == 5)
        #expect(c.currentMonth?.month == "2026-03")
        #expect(c.previousMonth?.sums.total == 55)
        #expect(c.years == [2026, 2025])
        #expect(c.energies.first?.share == 100)
    }

    @Test func monthsKeepTheirCategoriesAndAcceptStrings() throws {
        let c = try JSONDecoder().decode(VehicleCosts.self, from: example)
        #expect(c.months.map(\.month) == ["2026-02", "2026-01"])
        #expect(c.months[0].byCategory == ["Tankfuellung:l": 55])
        #expect(c.months[1].sums.total == 410, "numerics may arrive as strings")
        #expect(c.months[1].byCategory == ["Tankfuellung:l": 110, "Versicherung": 300])
        #expect(c.months[1].count == 3)
    }

    @Test func categoriesComeBiggestFirstAsTheApiSendsThem() throws {
        let c = try JSONDecoder().decode(VehicleCosts.self, from: example)
        #expect(c.categories.map(\.key) == ["Versicherung", "Tankfuellung:l"])
        #expect(c.categories[1].count == 3)
    }

    @Test func withoutADistanceThereIsNoCostPerKm() throws {
        let json = Data(#"{"year":2025,"total":{"energy":0,"expenses":0,"total":0},"distanceKm":null,"costPerKm":{"energy":null,"total":null},"perMonth":null,"monthCount":0,"months":[],"categories":[],"years":[]}"#.utf8)
        let c = try JSONDecoder().decode(VehicleCosts.self, from: json)
        #expect(c.year == 2025)
        #expect(c.costPerKmTotal == nil)
        #expect(c.costPerKmEnergy == nil)
        #expect(c.distanceKm == nil)
        #expect(c.currentMonth == nil)
        #expect(c.months.isEmpty)
        #expect(c.currency == "EUR", "defaults to euro when the server sends none")
    }

    @Test func categoryKeysSplitFuellingFromTheUnit() {
        #expect(CostCategoryKey("Tankfuellung:kwh") == CostCategoryKey("Tankfuellung:kwh"))
        #expect(CostCategoryKey("Tankfuellung:kwh").isFuelling)
        #expect(CostCategoryKey("Tankfuellung:kwh").unit == "kwh")
        #expect(CostCategoryKey("Tankfuellung").unit == nil)
        #expect(CostCategoryKey("Versicherung").isFuelling == false)
        #expect(CostCategoryKey("Versicherung").base == "Versicherung")
        #expect(CostCategoryKey("Mein Tankfuellung:x").isFuelling == false)
    }

    @Test func monthKeysBecomeDates() throws {
        let date = try #require(PeriodKey.monthStart("2026-02"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        #expect(parts.year == 2026 && parts.month == 2 && parts.day == 1)
        #expect(PeriodKey.monthStart("2026") == nil)
        #expect(PeriodKey.monthStart("2026-13") == nil)
    }
}

struct VehicleCostsGroupTests {
    /// New fields of FuelStat/fuelstat#180 as the issue shows them.
    private let json = Data("""
    {
      "currency": "EUR", "total": { "energy": 110, "expenses": 1000, "total": 1110 },
      "groups": [
        { "key": "kraftstoff", "total": 110, "count": 2, "share": 9.9 },
        { "key": "wartung", "total": "690.00", "count": 3, "share": 62.2 },
        { "key": "unterwegs", "total": 0, "count": 0, "share": 0 }
      ],
      "maintenancePer10000Km": 690,
      "largestExpenses": [
        { "id": "a1", "at": "2026-02-10T12:00:00.000Z", "category": "Reifen", "cost": 400, "vendor": null,
          "description": "Winterreifen" },
        { "id": "a2", "at": "2026-01-05T08:30:00Z", "category": "Versicherung", "cost": "300.00", "vendor": "HUK" },
        { "category": "ohne id", "cost": 1 }
      ]
    }
    """.utf8)

    @Test func decodesGroupsMaintenanceAndLargestExpenses() throws {
        let c = try JSONDecoder().decode(VehicleCosts.self, from: json)
        #expect(c.groups.map(\.key) == ["kraftstoff", "wartung", "unterwegs"])
        #expect(c.groups[1].total == 690, "numerics may arrive as strings")
        #expect(c.groups[0].share == 9.9)
        #expect(c.maintenancePer10000Km == 690)
        #expect(c.largestExpenses.map(\.id) == ["a1", "a2"], "an unreadable row is skipped")
        #expect(c.largestExpenses[0].description == "Winterreifen")
        #expect(c.largestExpenses[0].vendor == nil)
        #expect(c.largestExpenses[0].date != nil)
        #expect(c.largestExpenses[1].cost == 300)
        #expect(c.largestExpenses[1].date != nil, "dates without fractions work too")
    }

    @Test func olderServersWithoutTheFieldsStillDecode() throws {
        let c = try JSONDecoder().decode(VehicleCosts.self, from: Data(#"{"currency":"EUR"}"#.utf8))
        #expect(c.groups.isEmpty)
        #expect(c.maintenancePer10000Km == nil)
        #expect(c.largestExpenses.isEmpty)
    }
}

import Foundation
import Testing
@testable import FuelstatCore

struct VehicleConsumptionTests {
    /// Example from `docs/api.md` (FuelStat/fuelstat), `GET /vehicles/:id/consumption`, plus the fields of #140 and #156.
    private let phev = Data("""
    {
      "fuelType": "phev",
      "units": ["l", "kwh"],
      "energies": ["petrol", "electricity"],
      "byEnergy": {
        "petrol": { "unit": "l", "energy": "petrol", "name": "Benzin", "costShare": 87.1, "minor": false,
          "avg": 4, "min": 4, "max": 4, "kmConsumed": 1000, "amountConsumed": 40, "amountBought": 70,
          "cost": 122.5, "avgPrice": 1.75, "fillCount": 2,
          "co2": { "factor": 2.37, "totalKg": 165.9, "gPerKm": 94.8 },
          "segments": [{ "fullId": "a", "date": "2026-01-20", "month": "2026-01", "km": 1000, "amount": 40, "consumption": 4 }],
          "months": [{ "month": "2026-01", "km": 1000, "amount": 40, "consumption": 4 }],
          "years": [{ "year": 2026, "fillCount": 2, "amountBought": 70, "cost": 122.5, "amountConsumed": 40,
                      "kmConsumed": 1000, "consumption": 4, "co2Kg": 165.9 }] },
        "electricity": { "unit": "kwh", "energy": "electricity", "name": "Strom", "costShare": 12.9, "minor": true,
          "avg": null, "min": null, "max": null, "kmConsumed": 0, "amountConsumed": 0, "amountBought": 50,
          "cost": "18.20", "avgPrice": "0.364", "fillCount": 3,
          "co2": { "factor": 0.363, "totalKg": 18.15, "gPerKm": null }, "segments": [], "months": [], "years": [] }
      },
      "byUnit": { "l": { "unit": "l", "avg": 4 } },
      "byFuel": {
        "e5": { "fuel": "e5", "name": "Super E5", "energy": "petrol", "unit": "l", "premium": false,
                "fillCount": 1, "amount": 30, "cost": 50, "avgPrice": 1.66, "shareOfEnergy": 40,
                "markup": null },
        "e10": { "fuel": "e10", "name": "Super E10", "energy": "petrol", "unit": "l", "premium": true,
                 "fillCount": 1, "amount": 40, "cost": 72.5, "avgPrice": 1.81, "shareOfEnergy": 60,
                 "markup": { "perUnit": 0.15, "percent": 9.04, "basePrice": 1.66 } }
      },
      "costPer100km": 14.07,
      "primary": { "metric": "costPer100km", "unit": "eur_per_100km", "value": 13.68 },
      "costPer100kmPeriods": {
        "months": [{ "period": "2026-02", "cost": 55, "distanceKm": 400, "costPer100km": 13.75 },
                   { "period": "2026-01", "cost": 40, "distanceKm": null, "costPer100km": null }],
        "years": [{ "period": "2026", "cost": 140.7, "distanceKm": 1000, "costPer100km": 14.07 }],
        "best": { "period": "2026-02", "cost": 55, "distanceKm": 400, "costPer100km": 13.75 },
        "worst": null, "minPeriodKm": 100
      },
      "energyCost": 140.7,
      "electricShare": 12.9,
      "co2": { "totalKg": 189.5, "gPerKm": 167.4 }
    }
    """.utf8)

    @Test func decodesAPlugInHybrid() throws {
        let c = try JSONDecoder().decode(VehicleConsumption.self, from: phev)
        #expect(c.units == ["l", "kwh"])
        #expect(c.primary == .init(metric: .costPer100km, unit: "eur_per_100km", value: 13.68))
        #expect(c.costPer100km == 14.07)
        #expect(c.energyCost == 140.7)
        #expect(c.electricShare == 12.9)
        #expect(c.co2?.totalKg == 189.5)
        #expect(c.co2?.gramsPerKm == 167.4)

        let petrol = try #require(c.byEnergy["petrol"])
        #expect(petrol.average == 4)
        #expect(petrol.minimum == 4)
        #expect(petrol.co2?.factor == 2.37)
        #expect(petrol.months == [.init(month: "2026-01", km: 1000, amount: 40, consumption: 4)])
        #expect(petrol.years.first?.co2Kg == 165.9)
        #expect(!petrol.minor)

        let electricity = try #require(c.byEnergy["electricity"])
        #expect(electricity.minor)
        #expect(electricity.average == nil)
        #expect(electricity.cost == 18.2, "numerics may arrive as strings")
        #expect(electricity.averagePrice == 0.364)
    }

    @Test func breakdownFollowsTheEnergyOrderOfTheApi() throws {
        let c = try JSONDecoder().decode(VehicleConsumption.self, from: phev)
        #expect(c.breakdown.map(\.key) == ["petrol", "electricity"])
    }

    @Test func fuelPricesAreSortedByAmountWithTheMarkup() throws {
        let c = try JSONDecoder().decode(VehicleConsumption.self, from: phev)
        #expect(c.byFuel.map(\.fuel) == ["e10", "e5"])
        let premium = try #require(c.byFuel.first)
        #expect(premium.premium)
        #expect(premium.markup == .init(perUnit: 0.15, percent: 9.04, basePrice: 1.66))
        #expect(c.byFuel.last?.markup == nil)
    }

    @Test func costRatesKeepNilWithoutADistance() throws {
        let c = try JSONDecoder().decode(VehicleConsumption.self, from: phev)
        let rates = try #require(c.costRates)
        #expect(rates.months.map(\.costPer100km) == [13.75, nil])
        #expect(rates.best?.period == "2026-02")
        #expect(rates.worst == nil)
        #expect(rates.minPeriodKm == 100)
        #expect(rates.years.first?.period == "2026")
    }

    /// Servers before #140 send only `byUnit`.
    @Test func olderServerWithOnlyUnits() throws {
        let json = Data("""
        {"fuelType":"e10","units":["l"],"byUnit":{"l":{"unit":"l","avg":6.4,"min":5.1,"max":8,"kmConsumed":900,
         "amountConsumed":58,"amountBought":60,"cost":104,"avgPrice":1.73,"fillCount":3,
         "co2":{"factor":2.37,"totalKg":142.2,"gPerKm":null},"months":[],"years":[]}},
         "energyCost":104,"electricShare":null,"co2":{"totalKg":142.2,"gPerKm":null}}
        """.utf8)
        let c = try JSONDecoder().decode(VehicleConsumption.self, from: json)
        #expect(c.byEnergy.isEmpty)
        #expect(c.primary == nil)
        #expect(c.costRates == nil)
        #expect(c.breakdown.map(\.key) == ["l"])
        #expect(c.breakdown.first?.figures.average == 6.4)
        #expect(c.co2?.gramsPerKm == nil)
    }

    @Test func aVehicleWithoutEntriesDecodes() throws {
        let c = try JSONDecoder().decode(VehicleConsumption.self, from: Data(#"{"fuelType":null,"units":["l"],"byUnit":{}}"#.utf8))
        #expect(c.breakdown.isEmpty)
        #expect(c.energyCost == nil)
    }

    @Test func oneUnreadableEnergyDoesNotHideTheOthers() throws {
        let json = Data(#"{"energies":["petrol","lpg"],"byEnergy":{"petrol":{"unit":"l","avg":7},"lpg":"broken"}}"#.utf8)
        let c = try JSONDecoder().decode(VehicleConsumption.self, from: json)
        #expect(c.breakdown.map(\.key) == ["petrol"])
    }
}

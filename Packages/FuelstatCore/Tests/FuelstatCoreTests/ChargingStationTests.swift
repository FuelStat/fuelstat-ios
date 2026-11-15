import Foundation
import Testing
@testable import FuelstatCore

struct ChargingStationTests {
    /// Example from `docs/api.md` (FuelStat/fuelstat), `GET /charging-stations`.
    private let example = Data("""
    {
      "stations": [
        { "id": "123456", "name": "EnBW HPC Ellwangen", "operator": "EnBW mobility+",
          "street": "Rotenbacher Str. 1", "place": "Ellwangen", "postCode": "73479",
          "lat": 48.96, "lng": 10.13, "distanceKm": 12.3,
          "points": 4, "maxKw": 300, "connectors": ["CCS", "Typ 2"],
          "usageCost": "0,59 €/kWh", "isOperational": true }
      ],
      "source": "Open Charge Map", "license": "CC BY 4.0", "sourceUrl": "https://openchargemap.org"
    }
    """.utf8)

    @Test func decodesTheDocumentedExample() throws {
        let response = try JSONDecoder().decode(ChargingStationsResponse.self, from: example)
        #expect(response.source == "Open Charge Map")
        #expect(response.license == "CC BY 4.0")
        let station = try #require(response.stations.first)
        #expect(station.id == "123456")
        #expect(station.operatorName == "EnBW mobility+")
        #expect(station.points == 4)
        #expect(station.maxKw == 300)
        #expect(station.connectors == ["CCS", "Typ 2"])
        #expect(station.usageCost == "0,59 €/kWh")
        #expect(station.distanceKm == 12.3)
        #expect(station.isOperational)
    }

    @Test func buildsTextsForTheList() throws {
        let station = try #require(JSONDecoder().decode(ChargingStationsResponse.self, from: example).stations.first)
        #expect(station.title == "EnBW mobility+ EnBW HPC Ellwangen")
        #expect(station.address == "Rotenbacher Str. 1, 73479 Ellwangen")
        #expect(station.label == "EnBW mobility+ EnBW HPC Ellwangen, Rotenbacher Str. 1, Ellwangen")
        #expect(station.maxPowerText == "300")
        #expect(station.connectorsText == "CCS · Typ 2")
    }

    @Test func nullsAndMissingFieldsAreAbsent() throws {
        let json = Data("""
        {"stations":[{"id":null,"name":"Ladepark","operator":null,"street":null,"place":null,"postCode":null,
          "lat":null,"lng":null,"distanceKm":null,"points":null,"maxKw":null,"connectors":[],"usageCost":null,
          "isOperational":false}]}
        """.utf8)
        let response = try JSONDecoder().decode(ChargingStationsResponse.self, from: json)
        let station = try #require(response.stations.first)
        #expect(response.source == nil)
        #expect(station.id == "Ladepark|")
        #expect(station.title == "Ladepark")
        #expect(station.address.isEmpty)
        #expect(station.label == "Ladepark")
        #expect(station.maxPowerText == nil)
        #expect(station.connectorsText == nil)
        #expect(!station.isOperational)
    }

    @Test func numericIdAndFractionalPower() throws {
        let json = Data(#"{"stations":[{"id":42,"name":"AC","maxKw":22.5,"connectors":["Typ 2"]}]}"#.utf8)
        let station = try #require(JSONDecoder().decode(ChargingStationsResponse.self, from: json).stations.first)
        #expect(station.id == "42")
        #expect(station.maxPowerText == "22,5")
        #expect(station.isOperational, "operational unless the API says otherwise")
    }

    @Test func operatorAlreadyInTheNameIsNotRepeated() {
        let station = ChargingStation(id: "1", name: "EnBW Schnelllader", operatorName: "EnBW")
        #expect(station.title == "EnBW Schnelllader")
    }

    @Test func oneUnreadableStationDoesNotHideTheOthers() throws {
        let json = Data(#"{"stations":[{"id":"1"},{"id":"2","name":"Gut"}]}"#.utf8)
        let response = try JSONDecoder().decode(ChargingStationsResponse.self, from: json)
        #expect(response.stations.map(\.name) == ["Gut"])
    }
}

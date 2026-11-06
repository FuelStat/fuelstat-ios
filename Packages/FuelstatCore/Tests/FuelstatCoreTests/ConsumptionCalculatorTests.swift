import Foundation
import Testing
@testable import FuelstatCore

private func fillUp(_ odometer: Double, _ volume: Double, _ cost: Double, full: Bool = true, day: Int = 0) -> FillUp {
    FillUp(date: Date(timeIntervalSince1970: Double(day) * 86_400), odometer: odometer, volume: volume, totalCost: cost, isFullTank: full)
}

@Test func emptyInputYieldsEmptyStats() {
    #expect(ConsumptionCalculator.stats(for: []) == .empty)
}

@Test func singleFillUpHasNoConsumption() {
    let stats = ConsumptionCalculator.stats(for: [fillUp(1000, 40, 70)])
    #expect(stats.fillUpCount == 1)
    #expect(stats.totalCost == 70)
    #expect(stats.averageConsumption == nil)
    #expect(stats.costPerKilometre == nil)
}

@Test func consumptionBetweenTwoFullTanks() throws {
    let stats = ConsumptionCalculator.stats(for: [
        fillUp(1000, 40, 70, day: 0),
        fillUp(1500, 30, 54, day: 7),
    ])
    #expect(stats.segments.count == 1)
    #expect(try #require(stats.averageConsumption) == 6.0)
    #expect(abs(try #require(stats.costPerKilometre) - 0.108) < 1e-9)
    #expect(stats.trackedDistance == 500)
}

@Test func partialFillUpsAreAddedToNextFullSegment() throws {
    let stats = ConsumptionCalculator.stats(for: [
        fillUp(1000, 40, 70),
        fillUp(1200, 10, 18, full: false),
        fillUp(1500, 20, 36),
    ])
    #expect(stats.segments.count == 1)
    #expect(stats.segments[0].volume == 30)
    #expect(try #require(stats.averageConsumption) == 6.0)
}

@Test func unsortedInputIsSortedByOdometer() throws {
    let stats = ConsumptionCalculator.stats(for: [
        fillUp(2000, 35, 63),
        fillUp(1000, 40, 70),
        fillUp(1500, 30, 54),
    ])
    #expect(stats.segments.map(\.distance) == [500, 500])
    #expect(try #require(stats.averageConsumption) == 6.5)
}

@Test func leadingPartialFillUpsAreIgnoredForConsumption() throws {
    let stats = ConsumptionCalculator.stats(for: [
        fillUp(900, 15, 27, full: false),
        fillUp(1000, 40, 70),
        fillUp(1500, 30, 54),
    ])
    #expect(try #require(stats.averageConsumption) == 6.0)
    #expect(stats.totalVolume == 85)
}

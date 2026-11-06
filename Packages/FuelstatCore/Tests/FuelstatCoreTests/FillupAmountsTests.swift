import Testing
@testable import FuelstatCore

struct FillupAmountsTests {
    @Test func amountAndPriceGiveTotal() {
        var values = FillupAmounts()
        values.set(.pricePerUnit, to: 1.759)
        values.set(.amount, to: 42.5)
        #expect(values.total == 74.76)
        #expect(values.derivedField == .total)
    }

    @Test func amountAndTotalGivePrice() {
        var values = FillupAmounts()
        values.set(.amount, to: 40)
        values.set(.total, to: 70.36)
        #expect(values.pricePerUnit == 1.759)
    }

    @Test func totalAndPriceGiveAmount() {
        var values = FillupAmounts()
        values.set(.total, to: 50)
        values.set(.pricePerUnit, to: 1.8)
        #expect(values.amount == 27.78)
    }

    @Test func theTwoLatestEntriesWin() {
        var values = FillupAmounts()
        values.set(.pricePerUnit, to: 1.70) // e.g. prefilled from the last fill-up
        values.set(.amount, to: 40)
        #expect(values.total == 68)
        // Now the user types the total from the pump display: the price is recalculated, not the total.
        values.set(.total, to: 70)
        #expect(values.pricePerUnit == 1.75)
        #expect(values.entered == [.amount, .total])
    }

    @Test func clearingAFieldStopsCalculating() {
        var values = FillupAmounts()
        values.set(.amount, to: 40)
        values.set(.pricePerUnit, to: 1.5)
        values.set(.amount, to: nil)
        #expect(values.derivedField == nil)
        #expect(values.total == 60, "the last result stays until two values are known again")
    }

    @Test func zeroAmountDoesNotDivide() {
        var values = FillupAmounts()
        values.set(.amount, to: 0)
        values.set(.total, to: 10)
        #expect(values.pricePerUnit == nil)
    }
}

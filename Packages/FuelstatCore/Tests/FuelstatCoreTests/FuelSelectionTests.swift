import Testing
@testable import FuelstatCore

struct FuelSelectionTests {
    @Test func defaultFallsBackToTheFirstGrade() {
        #expect(FuelSelection(keys: ["super_e5", "lpg"], defaultKey: "nope").defaultKey == "super_e5")
        #expect(FuelSelection(keys: ["super_e5", "lpg"], defaultKey: "lpg").defaultKey == "lpg")
        #expect(FuelSelection(keys: [], defaultKey: nil).defaultKey == nil)
    }

    @Test func duplicatesAndTooManyAreDropped() {
        let many = (1...12).map { "fuel\($0)" }
        #expect(FuelSelection(keys: ["a", "a", "b"], defaultKey: nil).keys == ["a", "b"])
        #expect(FuelSelection(keys: many, defaultKey: nil).keys.count == FuelSelection.maxCount)
    }

    @Test func togglingAddsAndRemoves() {
        var selection = FuelSelection(keys: ["super_e5"], defaultKey: "super_e5")
        selection.toggle("lpg")
        #expect(selection.keys == ["super_e5", "lpg"])
        #expect(selection.isSelected("lpg"))
        selection.toggle("super_e5")
        #expect(selection.keys == ["lpg"])
        #expect(selection.defaultKey == "lpg", "removing the default hands it to the first remaining grade")
    }

    @Test func theLastGradeStays() {
        var selection = FuelSelection(keys: ["diesel"], defaultKey: "diesel")
        selection.toggle("diesel")
        #expect(selection.keys == ["diesel"])
    }

    @Test func noMoreThanEightGrades() {
        var selection = FuelSelection(keys: (1...8).map { "fuel\($0)" }, defaultKey: nil)
        #expect(!selection.canAddMore)
        selection.toggle("extra")
        #expect(selection.keys.count == 8)
        #expect(!selection.isSelected("extra"))
    }

    @Test func onlyASelectedGradeCanBeTheDefault() {
        var selection = FuelSelection(keys: ["super_e5", "lpg"], defaultKey: "super_e5")
        selection.setDefault("diesel")
        #expect(selection.defaultKey == "super_e5")
        selection.setDefault("lpg")
        #expect(selection.defaultKey == "lpg")
    }

    @Test func detectsChangesAgainstTheSavedVehicle() {
        var selection = FuelSelection(keys: ["super_e5", "lpg"], defaultKey: "super_e5")
        #expect(!selection.differs(from: ["super_e5", "lpg"], defaultKey: "super_e5"))
        #expect(!selection.differs(from: ["super_e5", "lpg"], defaultKey: nil))
        selection.setDefault("lpg")
        #expect(selection.differs(from: ["super_e5", "lpg"], defaultKey: "super_e5"))
        #expect(FuelSelection(keys: ["super_e5"], defaultKey: nil).differs(from: ["super_e5", "lpg"], defaultKey: nil))
    }
}

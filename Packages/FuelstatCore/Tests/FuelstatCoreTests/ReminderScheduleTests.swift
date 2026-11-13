import Foundation
import Testing
@testable import FuelstatCore

struct ReminderScheduleTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func firesLeadDaysBeforeInTheMorning() {
        let fire = ReminderSchedule.fireDate(dueDay: "2027-03-20", leadDays: 7, now: date(2027, 1, 1), calendar: calendar)
        #expect(fire == date(2027, 3, 13, 9))
    }

    @Test func acceptsTimestamps() {
        let fire = ReminderSchedule.fireDate(dueDay: "2027-03-20T00:00:00.000Z", leadDays: 1, now: date(2027, 1, 1),
                                             calendar: calendar)
        #expect(fire == date(2027, 3, 19, 9))
    }

    @Test func insideTheLeadTimeItFiresTheNextMorning() {
        let fire = ReminderSchedule.fireDate(dueDay: "2027-03-20", leadDays: 30, now: date(2027, 3, 15, 12),
                                             calendar: calendar)
        #expect(fire == date(2027, 3, 16, 9))
    }

    @Test func beforeNineItFiresTheSameMorning() {
        let fire = ReminderSchedule.fireDate(dueDay: "2027-03-20", leadDays: 30, now: date(2027, 3, 15, 7),
                                             calendar: calendar)
        #expect(fire == date(2027, 3, 15, 9))
    }

    @Test func onTheDueDayAfterNineThereIsNothingLeftToAnnounce() {
        #expect(ReminderSchedule.fireDate(dueDay: "2027-03-20", leadDays: 7, now: date(2027, 3, 20, 10),
                                          calendar: calendar) == nil)
    }

    @Test func overdueAndUnreadableDatesAreNotScheduled() {
        #expect(ReminderSchedule.fireDate(dueDay: "2027-03-20", leadDays: 7, now: date(2027, 3, 21), calendar: calendar) == nil)
        #expect(ReminderSchedule.fireDate(dueDay: "bald", leadDays: 7, now: date(2027, 3, 1), calendar: calendar) == nil)
        #expect(ReminderSchedule.fireDate(dueDay: "2027-02-31", leadDays: 7, now: date(2027, 1, 1), calendar: calendar) == nil)
    }

    @Test func identifiersCarryTheVehicle() {
        let id = ReminderSchedule.identifier(vehicleID: "3f9c-1", category: "TUV")
        #expect(id == "reminder.3f9c-1.TUV")
        #expect(ReminderSchedule.vehicleID(fromIdentifier: id) == "3f9c-1")
        #expect(ReminderSchedule.vehicleID(fromIdentifier: "odometer.x") == nil)
    }
}

import Foundation

/// When a local notification for a due date fires. The due date itself comes from the API; this only places the
/// notification a number of days before it, in the morning.
public enum ReminderSchedule {
    /// Hour of the day (local time) at which reminders are delivered.
    public static let hour = 9

    /// Lead times offered in the settings, in days.
    public static let leadDayOptions = [1, 3, 7, 14, 30]
    public static let defaultLeadDays = 7

    /// Fire date for a due day (`YYYY-MM-DD` from the API).
    ///
    /// - `leadDays` before the due day at `hour`:00 local time.
    /// - If that moment has passed but the due day has not, the next morning (or today, before `hour`:00).
    /// - nil when the due day is over or cannot be read: overdue dates are shown in the app, not announced.
    public static func fireDate(dueDay: String, leadDays: Int, now: Date, calendar: Calendar = .current) -> Date? {
        let parts = dueDay.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var due = DateComponents()
        (due.year, due.month, due.day, due.hour) = (parts[0], parts[1], parts[2], hour)
        guard let dueMorning = calendar.date(from: due),
              calendar.component(.month, from: dueMorning) == parts[1],
              let endOfDueDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: dueMorning)),
              now < endOfDueDay,
              let planned = calendar.date(byAdding: .day, value: -max(leadDays, 0), to: dueMorning) else { return nil }
        if planned > now { return planned }

        var today = calendar.dateComponents([.year, .month, .day], from: now)
        today.hour = hour
        guard let thisMorning = calendar.date(from: today) else { return nil }
        if thisMorning > now { return thisMorning }
        guard let nextMorning = calendar.date(byAdding: .day, value: 1, to: thisMorning),
              nextMorning < endOfDueDay else { return nil }
        return nextMorning
    }

    /// Stable identifier of the notification for one due date of one vehicle, so rescheduling replaces it.
    public static func identifier(vehicleID: String, category: String) -> String {
        "\(identifierPrefix)\(vehicleID).\(category)"
    }

    public static let identifierPrefix = "reminder."

    /// The vehicle a notification identifier belongs to.
    public static func vehicleID(fromIdentifier identifier: String) -> String? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        let id = identifier.dropFirst(identifierPrefix.count).split(separator: ".").first.map(String.init)
        return id?.isEmpty == false ? id : nil
    }
}

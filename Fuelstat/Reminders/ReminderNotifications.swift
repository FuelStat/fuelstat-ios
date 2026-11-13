import Foundation
import FuelstatCore
import UserNotifications

/// Local notifications for due dates (TÜV, service, insurance, tax) – no push server and no paid developer
/// program needed. The dates come from `GET /vehicles/:id/reminders`; the app only places a notification a number
/// of days before each one and replans whenever the dates are loaded.
enum ReminderNotifications {
    private static let enabledKey = "reminders.local.enabled"
    private static let leadDaysKey = "reminders.local.leadDays"

    /// The user switched reminders on. Permission is only asked for at that moment, never at launch.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Days before the due date at which the reminder appears.
    static var leadDays: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: leadDaysKey)
            return stored > 0 ? stored : ReminderSchedule.defaultLeadDays
        }
        set { UserDefaults.standard.set(newValue, forKey: leadDaysKey) }
    }

    /// Asks for permission to show notifications. Returns false when the user (or a restriction) refuses.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Replaces the planned notifications of one vehicle with the ones for its current due dates.
    static func schedule(_ reminders: [RemoteReminder], for vehicle: RemoteVehicle) async {
        guard isEnabled else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let prefix = ReminderSchedule.identifier(vehicleID: vehicle.id, category: "")
        let outdated = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: outdated)

        for reminder in reminders {
            guard let dueDay = reminder.dueDay, let dueDate = reminder.dueDate,
                  let fireDate = ReminderSchedule.fireDate(dueDay: dueDay, leadDays: leadDays, now: .now) else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(reminder.title) – \(vehicle.name)"
            content.body = String(localized: "Fällig am \(APIDate.formatDay(dueDate)).")
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let request = UNNotificationRequest(
                identifier: ReminderSchedule.identifier(vehicleID: vehicle.id, category: reminder.category),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    /// Removes everything planned and delivered, e.g. after signing out or switching reminders off.
    static func removeAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    /// Number of reminders currently planned, for the settings screen.
    static func plannedCount() async -> Int {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(ReminderSchedule.identifierPrefix) }.count
    }

    static func installDelegate() {
        UNUserNotificationCenter.current().delegate = Delegate.shared
    }

    /// Shows reminders while the app is open and opens the vehicle when one is tapped.
    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        static let shared = Delegate()

        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
            -> UNNotificationPresentationOptions {
            [.banner, .list, .sound]
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    didReceive response: UNNotificationResponse) async {
            let identifier = response.notification.request.identifier
            guard let vehicleID = ReminderSchedule.vehicleID(fromIdentifier: identifier) else { return }
            await MainActor.run { IntentRouter.shared.pending = .openVehicle(vehicleID) }
        }
    }
}

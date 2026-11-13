import UIKit

/// Home Screen quick actions (long press on the app icon). A separate system feature from App Intents; they open the
/// app and hand the request to the same `IntentRouter` the intents use.
enum QuickActions {
    private enum Kind: String {
        case fuel = "org.fuelstat.ios.quick.fuel"
        case charge = "org.fuelstat.ios.quick.charge"
        case vehicle = "org.fuelstat.ios.quick.vehicle"
    }

    private static let vehicleIDKey = "vehicleID"

    /// Offers fuel and/or charging depending on the vehicles, plus up to two vehicles to open (iOS shows four).
    @MainActor
    static func update(for vehicles: [RemoteVehicle], selectedID: String?) {
        let units = Set(vehicles.flatMap(\.fuelType.fillupUnits))
        var items: [UIApplicationShortcutItem] = []
        if units.contains(where: { $0 != "kwh" }) {
            items.append(UIApplicationShortcutItem(
                type: Kind.fuel.rawValue, localizedTitle: String(localized: "Tanken erfassen"),
                localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "fuelpump")
            ))
        }
        if units.contains("kwh") {
            items.append(UIApplicationShortcutItem(
                type: Kind.charge.rawValue, localizedTitle: String(localized: "Laden erfassen"),
                localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "bolt.car")
            ))
        }
        if vehicles.count > 1 {
            let ordered = vehicles.sorted { ($0.id == selectedID ? 0 : 1) < ($1.id == selectedID ? 0 : 1) }
            for vehicle in ordered.prefix(2) {
                items.append(UIApplicationShortcutItem(
                    type: Kind.vehicle.rawValue, localizedTitle: vehicle.name,
                    localizedSubtitle: vehicle.licensePlate,
                    icon: UIApplicationShortcutIcon(systemImageName: "car.side"),
                    userInfo: [vehicleIDKey: vehicle.id as NSString]
                ))
            }
        }
        UIApplication.shared.shortcutItems = items
    }

    /// Removes the actions, e.g. after signing out.
    @MainActor
    static func clear() {
        UIApplication.shared.shortcutItems = []
    }

    @MainActor
    @discardableResult
    static func handle(_ item: UIApplicationShortcutItem) -> Bool {
        switch Kind(rawValue: item.type) {
        case .fuel:
            IntentRouter.shared.pending = .addEntry(.fuel, vehicleID: nil)
        case .charge:
            IntentRouter.shared.pending = .addEntry(.charge, vehicleID: nil)
        case .vehicle:
            guard let id = item.userInfo?[vehicleIDKey] as? String else { return false }
            IntentRouter.shared.pending = .openVehicle(id)
        case nil:
            return false
        }
        return true
    }
}

/// Receives quick actions: at launch via the scene options, while running via the scene delegate.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Taps on local reminders open the vehicle (see ReminderNotifications).
        ReminderNotifications.installDelegate()
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem {
            MainActor.assumeIsolated { _ = QuickActions.handle(item) }
        }
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = QuickActionSceneDelegate.self
        return configuration
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(MainActor.assumeIsolated { QuickActions.handle(shortcutItem) })
    }
}

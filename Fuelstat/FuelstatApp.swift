import FuelstatCore
import SwiftData
import SwiftUI
import WidgetKit

@main
struct FuelstatApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var auth: AuthSession
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Widgets read the sign-in from the shared Keychain group; move items stored by earlier versions there.
        KeychainStore.moveToSharedGroup()
        ServerSettings.shareWithWidgets()
        _auth = State(initialValue: AuthSession())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .onOpenURL { url in
                    // Links from the widgets: open a vehicle or the entry sheet.
                    switch AppLink(url: url) {
                    case .addEntry(let kind, let vehicleID):
                        IntentRouter.shared.pending = .addEntry(kind.flatMap(EntryKind.init(linkKind:)),
                                                                vehicleID: vehicleID)
                    case .vehicle(let id):
                        IntentRouter.shared.pending = .openVehicle(id)
                    case nil:
                        break
                    }
                }
        }
        .modelContainer(for: [Vehicle.self, FuelEntry.self])
        .onChange(of: scenePhase) {
            // Keep active users signed in: renew the token when the app comes to the foreground.
            if scenePhase == .active {
                Task { await auth.renewIfNeeded() }
            }
        }
    }
}

/// Asks WidgetKit to reload the widgets after the data or the sign-in changed.
enum WidgetRefresh {
    static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension EntryKind {
    init?(linkKind: String) {
        switch linkKind {
        case "fuel": self = .fuel
        case "charge": self = .charge
        default: return nil
        }
    }
}

private struct RootView: View {
    @Environment(AuthSession.self) private var auth

    var body: some View {
        switch auth.state {
        case .restoring:
            ProgressView()
                .task { await auth.restore() }
        case .signedOut:
            LoginView()
                .onAppear { QuickActions.clear() }
        case .signedIn(let user):
            // A new list per user, so no vehicles of a previous account remain.
            MainTabView()
                .id(user.id)
        }
    }
}

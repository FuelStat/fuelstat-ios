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
    @Environment(\.scenePhase) private var scenePhase
    /// The minimum app version from `/health` (FuelStat/fuelstat#118) is higher than this app's.
    @State private var requiredVersion: String?

    var body: some View {
        content
            .fullScreenCover(item: Binding(get: { requiredVersion.map(RequiredUpdate.init) }, set: { _ in })) { update in
                AppUpdateRequiredView(minimumVersion: update.version) { await checkVersion() }
            }
            .task(id: scenePhase == .active) {
                if scenePhase == .active { await checkVersion() }
            }
    }

    /// Asks the server which app versions it supports. Offline nothing changes.
    private func checkVersion() async {
        guard let health = try? await auth.api.health() else { return }
        if case .updateRequired(let minimum) = health.appStatus {
            requiredVersion = minimum
        } else {
            requiredVersion = nil
        }
    }

    @ViewBuilder
    private var content: some View {
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

private struct RequiredUpdate: Identifiable {
    let version: String
    var id: String { version }
}

/// Shown when the server no longer supports this app version. Nothing else works until the app is updated, so the
/// screen cannot be dismissed; "Erneut prüfen" asks the server again.
private struct AppUpdateRequiredView: View {
    let minimumVersion: String
    let recheck: () async -> Void

    @State private var isChecking = false

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.brand)
                .accessibilityHidden(true)
            Text("Bitte aktualisiere Fuelstat")
                .font(.title.bold())
                .foregroundStyle(Theme.brandDeep)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Der Server unterstützt diese Version (\(AppVersion.marketing ?? "–")) nicht mehr. Nötig ist mindestens Version \(minimumVersion).")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            PrimaryButton(title: "Erneut prüfen", isLoading: isChecking) {
                isChecking = true
                Task {
                    await recheck()
                    isChecking = false
                }
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .interactiveDismissDisabled()
    }
}

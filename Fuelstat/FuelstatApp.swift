import SwiftData
import SwiftUI

@main
struct FuelstatApp: App {
    @State private var auth = AuthSession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
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

private struct RootView: View {
    @Environment(AuthSession.self) private var auth

    var body: some View {
        switch auth.state {
        case .restoring:
            ProgressView()
                .task { await auth.restore() }
        case .signedOut:
            LoginView()
        case .signedIn(let user):
            // A new list per user, so no vehicles of a previous account remain.
            MainTabView()
                .id(user.id)
        }
    }
}

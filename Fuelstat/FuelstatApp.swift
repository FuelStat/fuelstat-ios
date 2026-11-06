import SwiftData
import SwiftUI

@main
struct FuelstatApp: App {
    @State private var auth = AuthSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
        }
        .modelContainer(for: [Vehicle.self, FuelEntry.self])
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
        case .signedIn:
            RemoteVehicleListView()
        }
    }
}

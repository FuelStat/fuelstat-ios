import SwiftUI

/// Profil: account, vehicles, server and sign-out.
struct ProfileView: View {
    @Environment(AuthSession.self) private var auth
    @Bindable var store: VehicleStore
    @Binding var path: [Route]

    @State private var confirmingLogout = false
    @State private var serverVersion: String?

    private var email: String? {
        if case .signedIn(let user) = auth.state { return user.email }
        return nil
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.largeTitle)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Theme.brand)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(email ?? "")
                                .font(.headline)
                            Text("Server: \(ServerSettings.displayName(of: auth.api.baseURL))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xxs)
                    .accessibilityElement(children: .combine)
                }
                .listRowBackground(Theme.card)

                Section {
                    NavigationLink(value: Route.vehicles) {
                        LabeledContent {
                            Text("\(store.vehicles.count)")
                        } label: {
                            Label("Fahrzeuge", systemImage: "car.2")
                        }
                    }
                }
                .listRowBackground(Theme.card)

                Section {
                    Button("Abmelden", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        confirmingLogout = true
                    }
                }
                .listRowBackground(Theme.card)

                Section("Über") {
                    LabeledContent("App-Version", value: version)
                    LabeledContent("Server-Version", value: serverVersion ?? "–")
                    Link(destination: URL(string: "https://github.com/FuelStat/fuelstat-ios")!) {
                        Label("Quellcode auf GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    Link(destination: URL(string: "https://www.tankerkoenig.de")!) {
                        Label("Tankstellendaten: Tankerkönig, CC BY 4.0", systemImage: "fuelpump")
                    }
                }
                .listRowBackground(Theme.card)
            }
            .themedBackground()
            .navigationTitle("Profil")
            .task { await loadServerVersion() }
            .refreshable { await loadServerVersion() }
            .vehicleRoutes(store: store)
            .confirmationDialog("Abmelden?", isPresented: $confirmingLogout, titleVisibility: .visible) {
                Button("Abmelden", role: .destructive) { Task { await auth.logout() } }
            }
        }
    }

    private func loadServerVersion() async {
        if let health = try? await auth.api.health() {
            serverVersion = health.version ?? String(localized: "unbekannt")
        } else if serverVersion == nil {
            serverVersion = String(localized: "nicht erreichbar")
        }
    }
}

import SwiftUI

/// Profil: account, vehicles, feedback, sign-out, about, legal pages and account deletion.
struct ProfileView: View {
    @Environment(AuthSession.self) private var auth
    @Bindable var store: VehicleStore
    @Binding var path: [Route]

    @State private var confirmingLogout = false
    @State private var serverVersion: String?
    @State private var termsVersion: String?
    @State private var webPage: WebPage?

    private var email: String? {
        if case .signedIn(let user) = auth.state { return user.email }
        return nil
    }

    private var version: String { "\(AppInfo.version) (\(AppInfo.build))" }

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

                Section("Hilfe und Feedback") {
                    NavigationLink(value: Route.feedback) {
                        Label("Feedback senden", systemImage: "bubble.left.and.text.bubble.right")
                    }
                    NavigationLink(value: Route.releaseNotes) {
                        Label("Neuigkeiten", systemImage: "sparkles")
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

                Section {
                    WebPageRow(page: .imprint, selection: $webPage)
                    WebPageRow(page: .privacy, selection: $webPage)
                    WebPageRow(page: .terms, detail: termsVersion.map { String(localized: "Fassung \($0)") },
                               selection: $webPage)
                } header: {
                    Text("Rechtliches")
                } footer: {
                    Text("Seiten von \(ServerSettings.displayName(of: auth.api.baseURL))")
                }
                .listRowBackground(Theme.card)

                Section {
                    NavigationLink(value: Route.deleteAccount) {
                        Label("Konto löschen", systemImage: "person.crop.circle.badge.xmark")
                            .foregroundStyle(Theme.Status.overdue)
                    }
                } footer: {
                    Text("Löscht dein Konto mit allen Fahrzeugen und Einträgen.")
                }
                .listRowBackground(Theme.card)
            }
            .themedBackground()
            .navigationTitle("Profil")
            .task { await loadServerVersion() }
            .refreshable { await loadServerVersion() }
            .vehicleRoutes(store: store)
            .webPageSheet($webPage, apiBaseURL: auth.api.baseURL)
            .confirmationDialog("Abmelden?", isPresented: $confirmingLogout, titleVisibility: .visible) {
                Button("Abmelden", role: .destructive) { Task { await auth.logout() } }
            }
        }
    }

    private func loadServerVersion() async {
        if let health = try? await auth.api.health() {
            serverVersion = health.version ?? String(localized: "unbekannt")
            termsVersion = health.termsVersion.map(Self.formatTermsVersion)
        } else if serverVersion == nil {
            serverVersion = String(localized: "nicht erreichbar")
        }
    }

    /// `2026-11-09` → `09.11.2026`; other formats are shown as they are.
    private static func formatTermsVersion(_ version: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: version) else { return version }
        return date.formatted(date: .numeric, time: .omitted)
    }
}

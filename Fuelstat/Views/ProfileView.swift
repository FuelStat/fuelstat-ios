import FuelstatCore
import SwiftUI

/// Profil: account, vehicles, feedback, sign-out, about, legal pages and account deletion.
struct ProfileView: View {
    @Environment(AuthSession.self) private var auth
    @Bindable var store: VehicleStore
    @Binding var path: [Route]

    @State private var confirmingLogout = false
    @State private var serverVersion: String?
    @State private var termsVersion: String?
    @State private var recommendedVersion: String?
    @State private var webPage: WebPage?

    private var version: String { "\(AppInfo.version) (\(AppInfo.build))" }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let user = auth.user {
                    Section {
                        NavigationLink(value: Route.account) {
                            HStack(spacing: Theme.Spacing.s) {
                                ProfileAvatar(user: user, size: 48)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.displayName)
                                        .font(.headline)
                                    if user.username != nil {
                                        Text(user.email)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("Server: \(ServerSettings.displayName(of: auth.api.baseURL))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, Theme.Spacing.xxs)
                            .accessibilityElement(children: .combine)
                            .accessibilityHint(Text("Profil, Passwort und Zwei-Faktor-Anmeldung"))
                        }
                    }
                    .listRowBackground(Theme.card)

                    if user.needsEmailConfirmation {
                        Section {
                            EmailConfirmationNotice(user: user)
                        }
                        .listRowBackground(Theme.card)
                    }
                }

                Section {
                    NavigationLink(value: Route.vehicles) {
                        LabeledContent {
                            Text("\(store.vehicles.count)")
                        } label: {
                            Label("Fahrzeuge", systemImage: "car.2")
                        }
                    }
                    if let open = auth.user?.pendingInvitations, open > 0 {
                        NavigationLink(value: Route.invitations) {
                            LabeledContent {
                                Text("\(open)")
                            } label: {
                                Label("Einladungen", systemImage: "envelope.badge")
                            }
                        }
                    }
                    NavigationLink(value: Route.allReminders) {
                        Label("Termine und Erinnerungen", systemImage: "calendar.badge.clock")
                    }
                    NavigationLink(value: Route.categories) {
                        Label("Kategorien", systemImage: "tag")
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
                    if let recommendedVersion {
                        Label("Version \(recommendedVersion) nutzt alle Funktionen dieses Servers. Bitte aktualisiere die App.",
                              systemImage: "arrow.down.app")
                            .font(.subheadline)
                            .foregroundStyle(Theme.brandDeep)
                    }
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
            .task {
                await auth.refreshUser()
                await loadServerVersion()
            }
            .refreshable {
                await auth.refreshUser()
                await loadServerVersion()
            }
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
            if case .updateRecommended(let recommended) = health.appStatus {
                recommendedVersion = recommended
            } else {
                recommendedVersion = nil
            }
            termsVersion = health.termsVersion.map {
                TermsVersion.date(from: $0)?.formatted(date: .numeric, time: .omitted) ?? $0
            }
        } else if serverVersion == nil {
            serverVersion = String(localized: "nicht erreichbar")
        }
    }
}

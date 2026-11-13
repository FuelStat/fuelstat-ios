import SwiftUI

/// Konto → Angemeldete Geräte: the apps signed in to the account (device sessions, FuelStat/fuelstat#117).
/// Another device can be signed out with a swipe; this one through "Abmelden". The web app has no device sessions
/// and is not listed.
struct DevicesView: View {
    @Environment(AuthSession.self) private var auth

    @State private var sessions: [DeviceSession] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var ending: DeviceSession?
    @State private var confirmingLogout = false

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    FormMessage(text: errorMessage)
                }
                .listRowBackground(Theme.card)
            }

            Section {
                ForEach(sessions) { session in
                    DeviceRow(session: session)
                        .swipeActions(edge: .trailing) {
                            Button("Abmelden", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                                if session.isCurrent { confirmingLogout = true } else { ending = session }
                            }
                        }
                }
                if sessions.isEmpty, !isLoading, errorMessage == nil {
                    Text("Keine Apps angemeldet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    if !auth.hasDeviceSession {
                        Text("Dieses iPhone nutzt noch die frühere Anmeldung und erscheint erst nach dem nächsten Anmelden in der Liste. Dann bleibst du angemeldet, solange du die App mindestens alle 180 Tage öffnest.")
                    }
                    Text("Zum Abmelden nach links wischen. Die Web-App erscheint hier nicht; sie meldest du über „Auf allen Geräten abmelden“ ab.")
                }
            }
            .listRowBackground(Theme.card)
        }
        .themedBackground()
        .overlay { if isLoading, sessions.isEmpty { ProgressView() } }
        .navigationTitle("Angemeldete Geräte")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog("Gerät abmelden?", isPresented: Binding(
            get: { ending != nil }, set: { if !$0 { ending = nil } }
        ), titleVisibility: .visible, presenting: ending) { session in
            Button("„\(session.name)“ abmelden", role: .destructive) { end(session) }
        } message: { _ in
            Text("Die App auf diesem Gerät muss sich danach neu anmelden.")
        }
        .confirmationDialog("Dieses iPhone abmelden?", isPresented: $confirmingLogout, titleVisibility: .visible) {
            Button("Abmelden", role: .destructive) { Task { await auth.logout() } }
        }
    }

    private func load() async {
        defer { isLoading = false }
        do {
            // This device first, then by last use as the API sorts them.
            sessions = try await auth.sessions().sorted { $0.isCurrent && !$1.isCurrent }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func end(_ session: DeviceSession) {
        errorMessage = nil
        Task {
            do {
                try await auth.endSession(session.id)
                sessions.removeAll { $0.id == session.id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct DeviceRow: View {
    let session: DeviceSession

    @ScaledMetric(relativeTo: .body) private var circle = Theme.iconCircle

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.brand)
                .frame(width: circle, height: circle)
                .background(Theme.cardTint, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(verbatim: session.name).font(.body.weight(.medium))
                    if session.isCurrent {
                        Text("Dieses Gerät")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6)
                            .background(Theme.cardTint, in: .capsule)
                    }
                }
                Text(verbatim: subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch session.platform {
        case "ios": "iphone"
        case "android": "smartphone"
        default: "desktopcomputer"
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        switch session.platform {
        case "ios": parts.append("iOS")
        case "android": parts.append("Android")
        default: break
        }
        if let version = session.appVersion { parts.append(String(localized: "App \(version)")) }
        if let used = session.lastUsedAt {
            parts.append(String(localized: "zuletzt \(used.formatted(.relative(presentation: .named)))"))
        }
        return parts.joined(separator: " · ")
    }
}

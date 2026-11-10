import SwiftUI

/// Profil → Konto löschen (App Store Review Guideline 5.1.1(v)).
///
/// Easy to find, hard to trigger by accident: the user reads what happens, confirms it with a switch and then once
/// more in a dialog.
struct DeleteAccountView: View {
    @Environment(AuthSession.self) private var auth

    @State private var understood = false
    @State private var confirming = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var webPage: WebPage?

    private var email: String {
        if case .signedIn(let user) = auth.state { return user.email }
        return ""
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .font(.largeTitle)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.Status.overdue)
                        .accessibilityHidden(true)
                    Text("Konto \(email) löschen")
                        .font(.title3.bold())
                    Text("Das Löschen ist endgültig und kann nicht rückgängig gemacht werden.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, Theme.Spacing.xxs)
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(Theme.card)

            Section("Das wird gelöscht") {
                Fact(text: "Dein Konto mit E-Mail-Adresse, Passwort und Profil", systemImage: "person")
                Fact(text: "Deine Fahrzeuge mit allen Einträgen, Terminen und Fotos – auch für alle, mit denen du sie teilst",
                     systemImage: "car.2")
                Fact(text: "Deine Anmeldungen auf allen Geräten", systemImage: "iphone.gen3")
            }
            .listRowBackground(Theme.card)

            Section {
                Fact(text: "Was du an Fahrzeugen anderer erfasst hast, bleibt dort und gehört dann dem Besitzer des Fahrzeugs.",
                     systemImage: "person.2")
            } header: {
                Text("Das bleibt")
            }
            .listRowBackground(Theme.card)

            Section {
                WebPageRow(page: .export, selection: $webPage)
            } footer: {
                Text("Wenn du deine Daten behalten möchtest, exportiere sie vorher in der Web-App als CSV.")
            }
            .listRowBackground(Theme.card)

            Section {
                Toggle("Ich habe verstanden, dass mein Konto und meine Daten endgültig gelöscht werden.",
                       isOn: $understood)
                    .tint(Theme.Status.overdue)
            }
            .listRowBackground(Theme.card)

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.Status.overdue)
                }
                .listRowBackground(Theme.card)
            }

            Section {
                Button(role: .destructive) {
                    confirming = true
                } label: {
                    HStack {
                        Spacer()
                        if isDeleting {
                            ProgressView()
                        } else {
                            Label("Konto endgültig löschen", systemImage: "trash")
                                .font(.headline)
                        }
                        Spacer()
                    }
                }
                .disabled(!understood || isDeleting)
                .accessibilityValue(isDeleting ? Text("Wird ausgeführt") : Text(""))
            }
            .listRowBackground(Theme.card)
        }
        .themedBackground()
        .navigationTitle("Konto löschen")
        .navigationBarTitleDisplayMode(.inline)
        .webPageSheet($webPage, apiBaseURL: auth.api.baseURL)
        .confirmationDialog("Konto wirklich löschen?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Konto und alle Daten löschen", role: .destructive) {
                Task { await delete() }
            }
        } message: {
            Text("Das kann nicht rückgängig gemacht werden.")
        }
    }

    private func delete() async {
        isDeleting = true
        errorMessage = nil
        do {
            try await auth.deleteAccount()
            Haptics.success()
            // The session is now signed out; the app returns to the welcome screen by itself.
        } catch {
            Haptics.warning()
            errorMessage = String(localized: "Das Konto konnte nicht gelöscht werden: \(error.localizedDescription)")
            isDeleting = false
        }
    }
}

private struct Fact: View {
    let text: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.brand)
        }
    }
}

#Preview {
    NavigationStack { DeleteAccountView() }
        .environment(AuthSession())
}

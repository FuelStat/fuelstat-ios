import FuelstatCore
import SwiftUI

/// Asks for consent when `/whoami` reports new terms of use (`terms.required`). The app stays blocked until the user
/// agrees or signs out, like the web app.
struct TermsPromptView: View {
    @Environment(AuthSession.self) private var auth
    let version: String

    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var webPage: WebPage?

    private var versionText: String {
        TermsVersion.date(from: version)?.formatted(date: .long, time: .omitted) ?? version
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Image(systemName: "doc.text")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.brand)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Neue Nutzungsbedingungen")
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.brandDeep)
                        .accessibilityAddTraits(.isHeader)
                    Text("Die Nutzungsbedingungen haben sich geändert (Fassung vom \(versionText)). Bitte lies sie und stimme zu, um Fuelstat weiter zu nutzen.")
                        .foregroundStyle(.secondary)
                }

                Button {
                    webPage = .terms
                } label: {
                    Label("Nutzungsbedingungen lesen", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(SecondaryButtonStyle())

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.Status.overdue)
                }

                PrimaryButton(title: "Zustimmen", isLoading: isWorking) {
                    Task { await accept() }
                }

                Button("Abmelden") {
                    Task { await auth.logout() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.brand)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.xl)
        }
        .background(Theme.background.ignoresSafeArea())
        .interactiveDismissDisabled()
        .webPageSheet($webPage, apiBaseURL: auth.api.baseURL)
    }

    private func accept() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await auth.acceptTerms(version: version)
            Haptics.success()
        } catch APIError.server(code: "invalid_terms_version", _) {
            // The terms changed again in the meantime: load the new version and ask again.
            await auth.refreshUser()
            errorMessage = APIError.server(code: "invalid_terms_version", status: 400).localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// "Passwort vergessen?" on the sign-in screen: the server mails a reset link (`POST /auth/forgot-password`).
struct ForgotPasswordView: View {
    @Environment(AuthSession.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State var email: String
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var sent = false

    private var trimmed: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                if sent {
                    Section {
                        Label {
                            Text("Wenn es ein Konto mit \(trimmed) gibt, ist eine Mail mit einem Link unterwegs. Der Link gilt eine Stunde. Öffne ihn und lege ein neues Passwort fest, dann melde dich hier an.")
                        } icon: {
                            Image(systemName: "envelope.badge")
                                .foregroundStyle(Theme.Status.ok)
                        }
                    }
                    .listRowBackground(Theme.card)
                } else {
                    Section {
                        TextField("name@beispiel.de", text: $email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityLabel("E-Mail")
                    } header: {
                        Text("E-Mail")
                    } footer: {
                        Text("Wir schicken dir einen Link, mit dem du ein neues Passwort festlegen kannst. Danach bist du auf allen Geräten abgemeldet.")
                    }
                    .listRowBackground(Theme.card)

                    ErrorSection(message: errorMessage)
                }
            }
            .themedBackground()
            .navigationTitle("Passwort vergessen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sent ? "Fertig" : "Abbrechen") { dismiss() }
                }
                if !sent {
                    ToolbarItem(placement: .confirmationAction) {
                        if isSending {
                            ProgressView()
                        } else {
                            Button("Senden") { Task { await send() } }
                                .disabled(!trimmed.contains("@"))
                        }
                    }
                }
            }
        }
        .tint(Theme.brand)
    }

    private func send() async {
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            try await auth.api.forgotPassword(email: trimmed)
            sent = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

import FuelstatCore
import SwiftUI

/// Konto → Benutzername.
struct UsernameEditView: View {
    @Environment(AuthSession.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var trimmed: String { username.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                TextField("Benutzername", text: $username)
                    .textContentType(.nickname)
                    .autocorrectionDisabled()
            } footer: {
                Text("Wird anderen angezeigt, mit denen du Fahrzeuge teilst. Leer lassen, um ihn zu entfernen.")
            }
            .listRowBackground(Theme.card)

            ErrorSection(message: errorMessage)
        }
        .themedBackground()
        .navigationTitle("Benutzername")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                SaveButton(isSaving: isSaving) { Task { await save() } }
                    .disabled(trimmed == (auth.user?.username ?? ""))
            }
        }
        .onAppear { username = auth.user?.username ?? "" }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await auth.updateProfile(ProfilePatch(username: .some(trimmed.isEmpty ? nil : trimmed)))
            Haptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Konto → E-Mail. A new address only counts once it is confirmed via the link in the mail.
struct EmailEditView: View {
    @Environment(AuthSession.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var trimmed: String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    var body: some View {
        Form {
            Section {
                TextField("name@beispiel.de", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Neue E-Mail-Adresse")
            } header: {
                Text("Neue E-Mail-Adresse")
            } footer: {
                Text("Wir schicken einen Link an die neue Adresse. Erst wenn du ihn öffnest, gilt sie; bis dahin meldest du dich mit der bisherigen an.")
            }
            .listRowBackground(Theme.card)

            if let user = auth.user, user.pendingEmail != nil {
                Section {
                    EmailConfirmationNotice(user: user)
                }
                .listRowBackground(Theme.card)
            }

            ErrorSection(message: errorMessage)
        }
        .themedBackground()
        .navigationTitle("E-Mail-Adresse")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                SaveButton(isSaving: isSaving) { Task { await save() } }
                    .disabled(!trimmed.contains("@") || trimmed == auth.user?.email)
            }
        }
        .onAppear { email = auth.user?.pendingEmail ?? auth.user?.email ?? "" }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await auth.updateProfile(ProfilePatch(email: trimmed))
            Haptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Konto → Passwort ändern. The API signs out all other devices; this one gets a new token.
struct PasswordChangeView: View {
    @Environment(AuthSession.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var draft = PasswordChangeDraft()
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var done = false

    private var hint: LocalizedStringKey? {
        switch draft.problem {
        case .tooShort where !draft.new.isEmpty: "Mindestens 8 Zeichen."
        case .unchanged: "Das neue Passwort ist dasselbe wie das bisherige."
        case .mismatch where !draft.repeated.isEmpty: "Die beiden Passwörter stimmen nicht überein."
        default: nil
        }
    }

    var body: some View {
        Form {
            Section("Aktuelles Passwort") {
                SecureField("Aktuelles Passwort", text: $draft.current)
                    .textContentType(.password)
            }
            .listRowBackground(Theme.card)

            Section {
                SecureField("Neues Passwort", text: $draft.new)
                    .textContentType(.newPassword)
                SecureField("Neues Passwort wiederholen", text: $draft.repeated)
                    .textContentType(.newPassword)
            } header: {
                Text("Neues Passwort")
            } footer: {
                if let hint {
                    Text(hint).foregroundStyle(Theme.Status.overdue)
                } else {
                    Text("Mindestens 8 Zeichen. Danach bist du auf allen anderen Geräten abgemeldet.")
                }
            }
            .listRowBackground(Theme.card)

            ErrorSection(message: errorMessage)
        }
        .themedBackground()
        .navigationTitle("Passwort ändern")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                SaveButton(isSaving: isSaving) { Task { await save() } }
                    .disabled(!draft.isValid)
            }
        }
        .alert("Passwort geändert", isPresented: $done) {
            Button("OK") { dismiss() }
        } message: {
            Text("Auf allen anderen Geräten musst du dich neu anmelden.")
        }
    }

    private func save() async {
        guard draft.isValid else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await auth.changePassword(current: draft.current, new: draft.new)
            Haptics.success()
            done = true
        } catch {
            Haptics.warning()
            errorMessage = error.localizedDescription
        }
    }
}

/// Shows an error below a form, if there is one.
struct ErrorSection: View {
    let message: String?

    var body: some View {
        if let message {
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.Status.overdue)
            }
            .listRowBackground(Theme.card)
        }
    }
}

/// "Sichern" in the toolbar, replaced by a spinner while saving.
struct SaveButton: View {
    let isSaving: Bool
    let action: () -> Void

    var body: some View {
        if isSaving {
            ProgressView()
        } else {
            Button("Sichern", action: action)
        }
    }
}

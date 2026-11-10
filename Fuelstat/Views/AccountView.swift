import PhotosUI
import SwiftUI

/// Profil → Konto: profile picture, user name, e-mail, password, 2FA and signing out everywhere.
struct AccountView: View {
    @Environment(AuthSession.self) private var auth

    @State private var photoItem: PhotosPickerItem?
    @State private var showingPhotoLibrary = false
    @State private var showingCamera = false
    @State private var confirmingSignOutEverywhere = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let user = auth.user {
                Section {
                    photoHeader(user)
                }
                .listRowBackground(Theme.card)

                if user.needsEmailConfirmation {
                    Section {
                        EmailConfirmationNotice(user: user)
                    }
                    .listRowBackground(Theme.card)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.Status.overdue)
                    }
                    .listRowBackground(Theme.card)
                }

                Section("Profil") {
                    NavigationLink(value: Route.accountUsername) {
                        LabeledContent("Benutzername", value: user.username ?? String(localized: "Nicht gesetzt"))
                    }
                    NavigationLink(value: Route.accountEmail) {
                        LabeledContent("E-Mail", value: user.email)
                    }
                }
                .listRowBackground(Theme.card)

                Section("Sicherheit") {
                    NavigationLink(value: Route.accountPassword) {
                        Label("Passwort ändern", systemImage: "key")
                    }
                    NavigationLink(value: Route.accountTwoFactor) {
                        LabeledContent {
                            Text(user.mfaEnabled == true ? "An" : "Aus")
                        } label: {
                            Label("Zwei-Faktor-Anmeldung", systemImage: "lock.shield")
                        }
                    }
                }
                .listRowBackground(Theme.card)

                Section {
                    Button("Auf allen Geräten abmelden", systemImage: "iphone.slash", role: .destructive) {
                        confirmingSignOutEverywhere = true
                    }
                } header: {
                    Text("Geräte")
                } footer: {
                    Text("Meldet dich überall ab, auch auf diesem iPhone und in der Web-App. Eine Liste der angemeldeten Geräte folgt, sobald der Server sie anbietet.")
                }
                .listRowBackground(Theme.card)
            }
        }
        .themedBackground()
        .navigationTitle("Konto")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isWorking)
        .task { await auth.refreshUser() }
        .refreshable { await auth.refreshUser() }
        .photosPicker(isPresented: $showingPhotoLibrary, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { loadPickedPhoto() }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in run { try await auth.setProfilePhoto(image) } }
                .ignoresSafeArea()
        }
        .confirmationDialog("Auf allen Geräten abmelden?", isPresented: $confirmingSignOutEverywhere,
                            titleVisibility: .visible) {
            Button("Überall abmelden", role: .destructive) {
                run { try await auth.signOutEverywhere() }
            }
        } message: {
            Text("Du musst dich danach überall neu anmelden, auch hier.")
        }
    }

    private func photoHeader(_ user: APIUser) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            ProfileAvatar(user: user, size: 72)
                .overlay {
                    if isWorking { ProgressView() }
                }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(user.displayName)
                    .font(.headline)
                Menu {
                    Button("Foto auswählen", systemImage: "photo.on.rectangle") { showingPhotoLibrary = true }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Foto aufnehmen", systemImage: "camera") { showingCamera = true }
                    }
                    if user.profileImageURL != nil {
                        Button("Foto entfernen", systemImage: "trash", role: .destructive) {
                            run { try await auth.removeProfilePhoto() }
                        }
                    }
                } label: {
                    Text(user.profileImageURL == nil ? "Profilbild hinzufügen" : "Profilbild ändern")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.brand)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xxs)
    }

    private func loadPickedPhoto() {
        guard let item = photoItem else { return }
        photoItem = nil
        run {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                throw APIError.server(code: "invalid_image", status: 0)
            }
            try await auth.setProfilePhoto(image)
        }
    }

    private func run(_ operation: @escaping () async throws -> Void) {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                try await operation()
                Haptics.success()
            } catch {
                Haptics.warning()
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// The profile picture in a circle, or the initial of the name on a tinted background.
struct ProfileAvatar: View {
    @Environment(AuthSession.self) private var auth
    let user: APIUser
    var size: CGFloat = 44

    @State private var image: UIImage?

    var body: some View {
        Circle()
            .fill(Theme.cardTint)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Text(String(user.displayName.prefix(1)).uppercased())
                        .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.brand)
                }
            }
            .clipShape(.circle)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .task(id: user.profileImageURL) {
                guard let url = auth.api.resolve(user.profileImageURL) else {
                    image = nil
                    return
                }
                image = await ImageCache.shared.image(for: url)
            }
    }
}

/// Hint that the e-mail address is not confirmed yet, with a button to send the mail again.
struct EmailConfirmationNotice: View {
    @Environment(AuthSession.self) private var auth
    let user: APIUser

    @State private var isSending = false
    @State private var message: String?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Label {
                if let pending = user.pendingEmail {
                    Text("Bitte bestätige deine neue Adresse \(pending). Bis dahin meldest du dich weiter mit \(user.email) an.")
                } else {
                    Text("Bitte bestätige deine E-Mail-Adresse. Bis dahin kannst du nur ein Fahrzeug und einen Eintrag anlegen.")
                }
            } icon: {
                Image(systemName: "envelope.badge")
                    .foregroundStyle(Theme.Status.soon)
            }
            .font(.subheadline)

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(failed ? Theme.Status.overdue : .secondary)
            }

            Button {
                Task { await resend() }
            } label: {
                if isSending {
                    ProgressView()
                } else {
                    Text("Bestätigungsmail erneut senden")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.brand)
            .disabled(isSending)
            .buttonStyle(.borderless)
        }
        .padding(.vertical, Theme.Spacing.xxs)
    }

    private func resend() async {
        isSending = true
        defer { isSending = false }
        do {
            let address = try await auth.resendVerification() ?? user.pendingEmail ?? user.email
            failed = false
            message = String(localized: "Mail an \(address) ist unterwegs. Öffne den Link darin.")
        } catch APIError.server(code: "already_verified", _) {
            await auth.refreshUser()
        } catch {
            failed = true
            message = error.localizedDescription
        }
    }
}

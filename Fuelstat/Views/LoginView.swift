import FuelstatCore
import SwiftUI

/// Signed out: welcome screen, then sign-in or registration, then the 2FA code if the account needs one.
struct LoginView: View {
    @Environment(AuthSession.self) private var auth

    enum Mode: Hashable {
        case login, register
    }

    @State private var path: [Mode] = []

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView { path = [$0] }
                .navigationDestination(for: Mode.self) { mode in
                    SignInForm(mode: mode)
                }
        }
        .tint(Theme.brand)
    }
}

/// Full-colour brand screen in both modes: navy like the app icon, white text, teal accents.
private struct WelcomeView: View {
    @Environment(AuthSession.self) private var auth
    var onSelect: (LoginView.Mode) -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()
            GaugeIllustration()
                .frame(width: 180, height: 120)
                .accessibilityHidden(true)
            VStack(spacing: Theme.Spacing.xs) {
                Text("Fuelstat")
                    .font(.largeTitle.bold())
                Text("Verbrauch, Kosten und Termine deiner Fahrzeuge – immer dabei.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .foregroundStyle(.white)
            if let notice = auth.signOutNotice {
                Label(notice, systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(Theme.Spacing.s)
                    .background(.white.opacity(0.12), in: .tile)
            }
            Spacer()
            VStack(spacing: Theme.Spacing.s) {
                Button("Anmelden") { onSelect(.login) }
                    .buttonStyle(WelcomeButtonStyle(filled: true))
                Button("Konto erstellen") { onSelect(.register) }
                    .buttonStyle(WelcomeButtonStyle(filled: false))
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.welcomeNavy.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct WelcomeButtonStyle: ButtonStyle {
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(filled ? Theme.welcomeNavy : .white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                if filled {
                    RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous).fill(Theme.welcomeTeal)
                } else {
                    RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                        .strokeBorder(.white.opacity(0.6), lineWidth: 1.5)
                }
            }
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(.tile)
    }
}

/// The gauge motif of the app icon: an arc from green over yellow to orange with a teal needle.
private struct GaugeIllustration: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height * 2)
            let line = size * 0.09
            ZStack {
                Circle()
                    .trim(from: 0.5, to: 1)
                    .stroke(
                        AngularGradient(colors: Theme.welcomeGauge,
                                        center: .center, startAngle: .degrees(180), endAngle: .degrees(360)),
                        style: StrokeStyle(lineWidth: line, lineCap: .round)
                    )
                Capsule()
                    .fill(Theme.welcomeTeal)
                    .frame(width: size * 0.38, height: line * 0.55)
                    .offset(x: size * 0.17)
                    .rotationEffect(.degrees(-35))
                Circle()
                    .fill(Theme.welcomeTeal)
                    .frame(width: line * 1.3, height: line * 1.3)
            }
            .frame(width: size, height: size)
            .position(x: geometry.size.width / 2, y: geometry.size.height)
        }
    }
}

/// Sign-in or registration on a plain background: title, subtitle, labelled fields, primary button.
private struct SignInForm: View {
    @Environment(AuthSession.self) private var auth
    @State var mode: LoginView.Mode

    @State private var email = ""
    @State private var password = ""
    @State private var mfaCode = ""
    @State private var needsMFA = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showingServer = false

    @FocusState private var focused: Field?

    private enum Field: Hashable {
        case email, password
    }

    private var canSubmit: Bool {
        let emailOK = email.contains("@")
        let passwordOK = mode == .register ? password.count >= 8 : !password.isEmpty
        let codeOK = !needsMFA || mfaCode.count == 6
        return emailOK && passwordOK && codeOK && !isWorking
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if needsMFA {
                    mfaStep
                } else {
                    credentialsStep
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.Status.overdue)
                }

                PrimaryButton(title: needsMFA ? "Bestätigen" : (mode == .login ? "Anmelden" : "Konto erstellen"),
                              isLoading: isWorking, action: submit)
                    .disabled(!canSubmit)

                if !needsMFA {
                    Button(mode == .login ? "Noch kein Konto? Registrieren" : "Schon ein Konto? Anmelden") {
                        mode = mode == .login ? .register : .login
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.brand)
                    .frame(maxWidth: .infinity)

                    serverSection
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.m)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: mode) {
            errorMessage = nil
            needsMFA = false
            mfaCode = ""
        }
        .sheet(isPresented: $showingServer) {
            ServerSettingsView()
        }
    }

    private var credentialsStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(mode == .login ? "Anmelden" : "Konto erstellen")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.brandDeep)
                    .accessibilityAddTraits(.isHeader)
                Text(mode == .login
                     ? "Melde dich mit deinem Fuelstat-Konto an."
                     : "Ein Konto für App und Web – deine Daten bleiben auf dem Fuelstat-Server.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            labelledField("E-Mail") {
                TextField("name@beispiel.de", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
                    .accessibilityLabel("E-Mail")
            }
            labelledField("Passwort") {
                SecureField("", text: $password)
                    .textContentType(mode == .register ? .newPassword : .password)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { if canSubmit { submit() } }
                    .accessibilityLabel("Passwort")
            }
            if mode == .register {
                Text("Das Passwort muss mindestens 8 Zeichen lang sein.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var mfaStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Bestätigungscode")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.brandDeep)
                    .accessibilityAddTraits(.isHeader)
                Text("Für dein Konto ist die Zwei-Faktor-Anmeldung aktiv. Gib den Code aus deiner Authenticator-App ein.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            CodeField(code: $mfaCode) {
                if canSubmit { submit() }
            }
            Button("Zurück") {
                needsMFA = false
                mfaCode = ""
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.brand)
        }
    }

    private var serverSection: some View {
        DisclosureGroup("Eigener Server") {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Button {
                    showingServer = true
                } label: {
                    LabeledContent("Server", value: ServerSettings.displayName(of: auth.api.baseURL))
                        .padding(Theme.Spacing.s)
                        .background(Theme.card, in: .tile)
                }
                .foregroundStyle(.primary)
                Text("Nur ändern, wenn du Fuelstat selbst betreibst.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, Theme.Spacing.xs)
        }
        .font(.subheadline)
        .tint(Theme.brand)
    }

    private func labelledField(_ title: LocalizedStringKey, @ViewBuilder field: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.brandDeep)
                .accessibilityHidden(true)
            field()
                .padding(Theme.Spacing.s)
                .frame(minHeight: 48)
                .background(Theme.card, in: .tile)
        }
    }

    private func submit() {
        guard !isWorking else { return }
        focused = nil
        errorMessage = nil
        isWorking = true
        let email = email.trimmingCharacters(in: .whitespaces)
        Task {
            defer { isWorking = false }
            do {
                switch mode {
                case .login:
                    try await auth.login(email: email, password: password, code: needsMFA ? mfaCode : nil)
                case .register:
                    try await auth.register(email: email, password: password)
                }
            } catch let error as APIError where error.code == "mfa_required" {
                if needsMFA {
                    // A code was sent but not accepted.
                    errorMessage = String(localized: "Der Code stimmt nicht. Bitte versuche es erneut.")
                    mfaCode = ""
                    Haptics.warning()
                }
                needsMFA = true
            } catch {
                errorMessage = error.localizedDescription
                if needsMFA { mfaCode = "" }
            }
        }
    }
}

/// Lets users of a self-hosted installation enter their server. The address is checked via `/health` first.
private struct ServerSettingsView: View {
    @Environment(AuthSession.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var isChecking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("tanken.example.de", text: $address)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Serveradresse")
                } header: {
                    Text("Serveradresse")
                } footer: {
                    Text("Adresse deiner Fuelstat-Installation. Die Verbindung muss über HTTPS laufen.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.Status.overdue)
                    }
                }

                if ServerSettings.isCustom {
                    Section {
                        Button("Standardserver verwenden") {
                            auth.useServer(APIClient.defaultBaseURL)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isChecking {
                        ProgressView()
                    } else {
                        Button("Sichern", action: check)
                            .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .onAppear { address = ServerSettings.displayName(of: auth.api.baseURL) }
        }
    }

    private func check() {
        guard let url = ServerAddress.apiBaseURL(from: address) else {
            errorMessage = String(localized: "Bitte gib eine gültige Adresse ein, z. B. tanken.example.de.")
            return
        }
        errorMessage = nil
        isChecking = true
        Task {
            defer { isChecking = false }
            do {
                _ = try await APIClient(baseURL: url).health()
                auth.useServer(url)
                dismiss()
            } catch {
                errorMessage = String(localized: "Unter dieser Adresse antwortet kein Fuelstat-Server.")
            }
        }
    }
}

#Preview {
    LoginView()
        .environment(AuthSession())
}

import FuelstatCore
import SwiftUI

struct LoginView: View {
    @Environment(AuthSession.self) private var auth

    private enum Mode: CaseIterable, Identifiable {
        case login, register
        var id: Self { self }
        var title: LocalizedStringKey { self == .login ? "Anmelden" : "Registrieren" }
    }

    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var mfaCode = ""
    @State private var needsMFA = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showingServer = false

    private var canSubmit: Bool {
        let emailOK = email.contains("@")
        let passwordOK = mode == .register ? password.count >= 8 : !password.isEmpty
        let codeOK = !needsMFA || mfaCode.count == 6
        return emailOK && passwordOK && codeOK && !isWorking
    }

    var body: some View {
        NavigationStack {
            Form {
                if let notice = auth.signOutNotice {
                    Section {
                        Label(notice, systemImage: "info.circle")
                    }
                }

                Section {
                    Picker("Modus", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    TextField("E-Mail", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Passwort", text: $password)
                        .textContentType(mode == .register ? .newPassword : .password)
                    if needsMFA {
                        TextField("6-stelliger Code", text: $mfaCode)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                    }
                } footer: {
                    if needsMFA {
                        Text("Für dein Konto ist die Zwei-Faktor-Anmeldung aktiv. Gib den Code aus deiner Authenticator-App ein.")
                    } else if mode == .register {
                        Text("Das Passwort muss mindestens 8 Zeichen lang sein.")
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if isWorking { ProgressView() } else { Text(mode.title).bold() }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit)
                }

                Section {
                    Button {
                        showingServer = true
                    } label: {
                        LabeledContent("Server", value: ServerSettings.displayName(of: auth.api.baseURL))
                    }
                    .foregroundStyle(.primary)
                } footer: {
                    Text("Nur ändern, wenn du Fuelstat selbst betreibst.")
                }
            }
            .navigationTitle("Fuelstat")
            .onChange(of: mode) {
                errorMessage = nil
                needsMFA = false
                mfaCode = ""
            }
            .sheet(isPresented: $showingServer) {
                ServerSettingsView()
            }
        }
    }

    private func submit() {
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
                needsMFA = true
            } catch {
                errorMessage = error.localizedDescription
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
                            .foregroundStyle(.red)
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

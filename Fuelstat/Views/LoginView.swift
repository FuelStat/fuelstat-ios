import SwiftUI

struct LoginView: View {
    @Environment(AuthSession.self) private var auth

    private enum Mode: String, CaseIterable, Identifiable {
        case login = "Anmelden"
        case register = "Registrieren"
        var id: Self { self }
    }

    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var mfaCode = ""
    @State private var needsMFA = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        let emailOK = email.contains("@")
        let passwordOK = mode == .register ? password.count >= 8 : !password.isEmpty
        let codeOK = !needsMFA || mfaCode.count == 6
        return emailOK && passwordOK && codeOK && !isWorking
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Modus", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
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
                            if isWorking { ProgressView() } else { Text(mode.rawValue).bold() }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .navigationTitle("Fuelstat")
            .onChange(of: mode) {
                errorMessage = nil
                needsMFA = false
                mfaCode = ""
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

#Preview {
    LoginView()
        .environment(AuthSession())
}

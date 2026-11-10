import CoreImage.CIFilterBuiltins
import FuelstatCore
import SwiftUI

/// Konto → Zwei-Faktor-Anmeldung: set up and turn on (`/auth/mfa/setup`, `/enable`) or turn off (`/disable`).
struct TwoFactorView: View {
    @Environment(AuthSession.self) private var auth

    var body: some View {
        Group {
            if auth.user?.mfaEnabled == true {
                DisableTwoFactorForm()
            } else {
                EnableTwoFactorFlow()
            }
        }
        .navigationTitle("Zwei-Faktor-Anmeldung")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EnableTwoFactorFlow: View {
    @Environment(AuthSession.self) private var auth
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var setup: MFASetup?
    @State private var code = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var copied = false
    @State private var showingQRCode = false
    @State private var noAuthenticator = false
    @State private var enabled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if let setup {
                    setupSteps(setup)
                } else {
                    intro
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.Status.overdue)
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.m)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .alert("Zwei-Faktor-Anmeldung ist aktiv", isPresented: $enabled) {
            Button("OK") { dismiss() }
        } message: {
            Text("Bei der nächsten Anmeldung fragt Fuelstat nach einem Code aus deiner Authenticator-App.")
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(Theme.brand)
                .accessibilityHidden(true)
            Text("Schütze dein Konto mit einem zweiten Faktor")
                .font(.title2.bold())
                .foregroundStyle(Theme.brandDeep)
                .accessibilityAddTraits(.isHeader)
            Text("Bei der Anmeldung brauchst du dann neben dem Passwort einen sechsstelligen Code aus einer Authenticator-App, zum Beispiel aus der Passwörter-App von iOS, Google Authenticator oder 1Password.")
                .foregroundStyle(.secondary)
            PrimaryButton(title: "Einrichten", systemImage: "lock.shield", isLoading: isWorking) {
                Task { await startSetup() }
            }
        }
    }

    private func setupSteps(_ setup: MFASetup) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            step(1, "Schlüssel in die Authenticator-App übernehmen") {
                if let url = URL(string: setup.otpauthUrl) {
                    Button {
                        openURL(url) { accepted in noAuthenticator = !accepted }
                    } label: {
                        Label("In Authenticator öffnen", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                if noAuthenticator {
                    Text("Keine App für Authenticator-Links gefunden. Kopiere den Schlüssel und füge ihn in deiner App ein.")
                        .font(.footnote)
                        .foregroundStyle(Theme.Status.overdue)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Oder Schlüssel von Hand eingeben:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(TOTPSecret.grouped(setup.secret))
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .accessibilityLabel(Text("Schlüssel"))
                            .accessibilityValue(Text(setup.secret.map(String.init).joined(separator: " ")))
                        Spacer()
                        Button {
                            UIPasteboard.general.string = setup.secret
                            copied = true
                            Haptics.selection()
                        } label: {
                            Label(copied ? "Kopiert" : "Kopieren", systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.brand)
                    }
                    .padding(Theme.Spacing.s)
                    .background(Theme.card, in: .tile)
                }

                DisclosureGroup("QR-Code für ein anderes Gerät", isExpanded: $showingQRCode) {
                    if let image = QRCode.image(for: setup.otpauthUrl) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 220)
                            .padding(Theme.Spacing.s)
                            .background(.white, in: .tile)
                            .frame(maxWidth: .infinity)
                            .padding(.top, Theme.Spacing.xs)
                            .accessibilityLabel(Text("QR-Code mit dem Schlüssel"))
                    }
                }
                .font(.subheadline)
                .tint(Theme.brand)
            }

            step(2, "Code aus der App eingeben") {
                CodeField(code: $code) {
                    Task { await enable() }
                }
                PrimaryButton(title: "Aktivieren", isLoading: isWorking) {
                    Task { await enable() }
                }
                .disabled(code.count != 6)
            }
        }
    }

    private func step(_ number: Int, _ title: LocalizedStringKey,
                      @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.xs) {
                Text("\(number)")
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.onBrand)
                    .frame(width: 26, height: 26)
                    .background(Theme.brand, in: .circle)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.brandDeep)
                    .accessibilityAddTraits(.isHeader)
            }
            content()
        }
    }

    private func startSetup() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            setup = try await auth.setUpMFA()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func enable() async {
        guard code.count == 6, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await auth.enableMFA(code: code)
            Haptics.success()
            enabled = true
        } catch {
            Haptics.warning()
            code = ""
            errorMessage = error.code == "invalid_mfa_code"
                ? String(localized: "Der Code stimmt nicht. Warte auf den nächsten Code und versuche es erneut.")
                : error.localizedDescription
        }
    }
}

private struct DisableTwoFactorForm: View {
    @Environment(AuthSession.self) private var auth

    @State private var password = ""
    @State private var code = ""
    @State private var askingForCode = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Label {
                    Text("Die Zwei-Faktor-Anmeldung ist aktiv. Bei der Anmeldung fragt Fuelstat nach einem Code aus deiner Authenticator-App.")
                } icon: {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(Theme.Status.ok)
                }
            }
            .listRowBackground(Theme.card)

            if askingForCode {
                Section {
                    CodeField(code: $code) {
                        Task { await disable() }
                    }
                    .listRowInsets(EdgeInsets(top: Theme.Spacing.s, leading: Theme.Spacing.m,
                                              bottom: Theme.Spacing.s, trailing: Theme.Spacing.m))
                } header: {
                    Text("Code aus der Authenticator-App")
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    SecureField("Passwort", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("Abschalten")
                } footer: {
                    Text("Zum Abschalten brauchst du dein Passwort und einen aktuellen Code.")
                }
                .listRowBackground(Theme.card)
            }

            ErrorSection(message: errorMessage)

            Section {
                Button(role: .destructive) {
                    if askingForCode {
                        Task { await disable() }
                    } else {
                        askingForCode = true
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isWorking {
                            ProgressView()
                        } else {
                            Text(askingForCode ? "Zwei-Faktor-Anmeldung abschalten" : "Weiter")
                                .font(.headline)
                        }
                        Spacer()
                    }
                }
                .disabled(isWorking || (askingForCode ? code.count != 6 : password.isEmpty))
            }
            .listRowBackground(Theme.card)
        }
        .themedBackground()
    }

    private func disable() async {
        guard code.count == 6, !password.isEmpty, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await auth.disableMFA(password: password, code: code)
            Haptics.success()
        } catch {
            Haptics.warning()
            code = ""
            if error.code == "invalid_current_password" {
                askingForCode = false
                password = ""
            }
            errorMessage = error.localizedDescription
        }
    }
}

private extension Error {
    var code: String? { (self as? APIError)?.code }
}

/// QR code for the `otpauth://` link, for scanning with another device.
enum QRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

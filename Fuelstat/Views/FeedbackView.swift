import FuelstatCore
import SwiftUI
import UIKit

/// Feedback to the operator of the server (`POST /feedback`), sent with the app and iOS version.
struct FeedbackView: View {
    @Environment(AuthSession.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var category: FeedbackInput.Category = .fehler
    @State private var draft = FeedbackDraft()
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var sent = false
    @FocusState private var editorFocused: Bool

    private let context = FeedbackDraft.context(
        appVersion: AppInfo.version, build: AppInfo.build,
        systemVersion: UIDevice.current.systemVersion, device: AppInfo.deviceModel
    )

    var body: some View {
        Form {
            Section("Worum geht es?") {
                ChipGroup(options: FeedbackInput.Category.allCases.map {
                    .init(value: $0, title: $0.title, systemImage: $0.systemImage)
                }, selection: $category)
                .listRowInsets(EdgeInsets(top: Theme.Spacing.s, leading: Theme.Spacing.m,
                                          bottom: Theme.Spacing.s, trailing: Theme.Spacing.m))
            }
            .listRowBackground(Theme.card)

            Section {
                TextEditor(text: $draft.message)
                    .frame(minHeight: 160)
                    .focused($editorFocused)
                    .accessibilityLabel(Text("Nachricht"))
                    .overlay(alignment: .topLeading) {
                        if draft.message.isEmpty {
                            Text(category.placeholder)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
            } header: {
                Text("Nachricht")
            } footer: {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    if draft.remainingCharacters < 500 {
                        Text("Noch \(draft.remainingCharacters) Zeichen")
                            .foregroundStyle(draft.remainingCharacters < 0 ? Theme.Status.overdue : .secondary)
                    }
                    Text("Wird mit deiner E-Mail-Adresse und \(context) an den Betreiber des Servers geschickt.")
                }
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
                PrimaryButton(title: "Senden", systemImage: "paperplane", isLoading: isSending) {
                    Task { await send() }
                }
                .disabled(!draft.isSendable)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .themedBackground()
        .navigationTitle("Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") { editorFocused = false }
            }
        }
        .alert("Danke für dein Feedback!", isPresented: $sent) {
            Button("OK") { dismiss() }
        } message: {
            Text("Deine Nachricht ist angekommen.")
        }
    }

    private func send() async {
        guard draft.isSendable, !isSending else { return }
        editorFocused = false
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        let input = FeedbackInput(category: category, message: draft.trimmedMessage, page: context)
        do {
            _ = try await auth.call { try await $0.sendFeedback(input, token: $1) }
            Haptics.success()
            sent = true
        } catch {
            Haptics.warning()
            errorMessage = error.localizedDescription
        }
    }
}

private extension FeedbackInput.Category {
    var title: LocalizedStringKey {
        switch self {
        case .fehler: "Fehler"
        case .idee: "Idee"
        case .lob: "Lob"
        case .sonstiges: "Sonstiges"
        }
    }

    var placeholder: LocalizedStringKey {
        switch self {
        case .fehler: "Was ist passiert, und was hast du erwartet?"
        case .idee: "Was würde dir helfen?"
        case .lob: "Was gefällt dir?"
        case .sonstiges: "Deine Nachricht"
        }
    }

    var systemImage: String {
        switch self {
        case .fehler: "ladybug"
        case .idee: "lightbulb"
        case .lob: "hand.thumbsup"
        case .sonstiges: "ellipsis.bubble"
        }
    }
}

/// Version and device of the running app.
enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
    }

    /// Model identifier such as `iPhone17,3`; the simulator reports the simulated model.
    static var deviceModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

#Preview {
    NavigationStack { FeedbackView() }
        .environment(AuthSession())
}

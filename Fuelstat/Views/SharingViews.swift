import SwiftUI

/// Who has access to a vehicle. The owner invites by e-mail, changes roles and removes members; a member can leave.
/// Roles and rights come from the API, which also enforces them.
struct VehicleSharingView: View {
    let store: VehicleStore
    let vehicleID: String

    @Environment(\.dismiss) private var dismiss

    @State private var members: VehicleMembers?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingInvite = false
    @State private var removing: VehicleMembers.Member?
    @State private var confirmingLeave = false

    private var isOwner: Bool { members?.role == VehicleRole.owner.rawValue }

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    FormMessage(text: errorMessage)
                }
                .listRowBackground(Theme.card)
            }

            if let members {
                Section("Zugriff") {
                    if let owner = members.owner {
                        MemberRow(member: owner)
                    }
                    ForEach(members.members) { member in
                        memberRow(member)
                    }
                }
                .listRowBackground(Theme.card)

                if isOwner {
                    if !members.invitations.isEmpty {
                        Section("Offene Einladungen") {
                            ForEach(members.invitations) { invitation in
                                invitationRow(invitation)
                            }
                        }
                        .listRowBackground(Theme.card)
                    }

                    Section {
                        Button("Per E-Mail einladen", systemImage: "person.badge.plus") { showingInvite = true }
                            .foregroundStyle(Theme.brand)
                    } footer: {
                        Text("Die eingeladene Person braucht ein Fuelstat-Konto mit genau dieser, bestätigten E-Mail-Adresse. Die Einladung gilt 14 Tage.")
                    }
                    .listRowBackground(Theme.card)
                } else {
                    Section {
                        Button("Fahrzeug verlassen", systemImage: "rectangle.portrait.and.arrow.right",
                               role: .destructive) { confirmingLeave = true }
                    } footer: {
                        Text("Deine Einträge bleiben beim Fahrzeug.")
                    }
                    .listRowBackground(Theme.card)
                }

                Section {
                    roleExplanation(.editor, "Sieht alles, erfasst Einträge und ändert die eigenen.")
                    roleExplanation(.viewer, "Sieht alles, ändert nichts.")
                } header: {
                    Text("Rollen")
                }
                .listRowBackground(Theme.card)
            }
        }
        .themedBackground()
        .overlay { if isLoading, members == nil { ProgressView() } }
        .navigationTitle("Teilen")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showingInvite, onDismiss: { Task { await load() } }) {
            InviteView(store: store, vehicleID: vehicleID)
        }
        .confirmationDialog("Zugriff entziehen?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }
        ), titleVisibility: .visible, presenting: removing) { member in
            Button("\(member.name) entfernen", role: .destructive) {
                run { try await store.removeMember(member.userID, from: vehicleID) }
            }
        } message: { _ in
            Text("Die Einträge der Person bleiben beim Fahrzeug.")
        }
        .confirmationDialog("Fahrzeug verlassen?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Verlassen", role: .destructive) {
                run(reload: false) {
                    try await store.leave(vehicleID)
                    dismiss()
                }
            }
        } message: {
            Text("Du siehst das Fahrzeug danach nicht mehr. Der Besitzer kann dich erneut einladen.")
        }
    }

    @ViewBuilder
    private func memberRow(_ member: VehicleMembers.Member) -> some View {
        if isOwner {
            HStack(spacing: Theme.Spacing.xs) {
                MemberRow(member: member)
                Menu {
                    roleActions(member)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(Theme.brand)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(Text("Rolle von \(member.name) ändern"))
            }
            .swipeActions(edge: .trailing) {
                Button("Entfernen", systemImage: "person.badge.minus", role: .destructive) { removing = member }
            }
        } else {
            MemberRow(member: member)
        }
    }

    @ViewBuilder
    private func roleActions(_ member: VehicleMembers.Member) -> some View {
        ForEach([VehicleRole.editor, .viewer], id: \.rawValue) { role in
            Button {
                run { try await store.setRole(role, ofMember: member.userID, in: vehicleID) }
            } label: {
                if member.role == role.rawValue {
                    Label(role.label, systemImage: "checkmark")
                } else {
                    Text(verbatim: role.label)
                }
            }
        }
        Button("Entfernen", systemImage: "person.badge.minus", role: .destructive) { removing = member }
    }

    private func invitationRow(_ invitation: VehicleMembers.Invitation) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: invitation.email).font(.body.weight(.medium))
                Text(verbatim: invitationSubtitle(invitation))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Zurückziehen", role: .destructive) {
                run { try await store.revokeInvitation(invitation.id, of: vehicleID) }
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
        }
        .accessibilityElement(children: .combine)
    }

    private func invitationSubtitle(_ invitation: VehicleMembers.Invitation) -> String {
        var parts = [VehicleRole(rawValue: invitation.role)?.label ?? invitation.role]
        if let expires = invitation.expiresAt {
            parts.append(String(localized: "gültig bis \(expires.formatted(date: .abbreviated, time: .omitted))"))
        }
        return parts.joined(separator: " · ")
    }

    private func roleExplanation(_ role: VehicleRole, _ text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: role.label).font(.body.weight(.medium))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        defer { isLoading = false }
        do {
            members = try await store.members(of: vehicleID)
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func run(reload: Bool = true, _ action: @escaping () async throws -> Void) {
        errorMessage = nil
        Task {
            do {
                try await action()
                if reload { await load() }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct MemberRow: View {
    let member: VehicleMembers.Member

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: member.role == VehicleRole.owner.rawValue ? "person.crop.circle.fill" : "person.crop.circle")
                .font(.title2)
                .foregroundStyle(Theme.brand)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: member.name).font(.body.weight(.medium))
                if let email = member.email, email != member.name {
                    Text(verbatim: email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(verbatim: VehicleRole(rawValue: member.role)?.label ?? member.role)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Invites an account by e-mail as editor or viewer.
private struct InviteView: View {
    let store: VehicleStore
    let vehicleID: String

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var role: VehicleRole = .editor
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Bool?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("E-Mail-Adresse")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("name@beispiel.de", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: true)
                            .accessibilityLabel("E-Mail-Adresse")
                    }
                    .padding(Theme.Spacing.s)
                    .background(Theme.card, in: .tile)

                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Rolle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ChipGroup(options: [
                            .init(value: VehicleRole.editor, title: "Mitfahrer", systemImage: "pencil"),
                            .init(value: VehicleRole.viewer, title: "Nur ansehen", systemImage: "eye"),
                        ], selection: $role)
                        Text(role == .editor
                             ? "Sieht alles, erfasst Einträge und ändert die eigenen."
                             : "Sieht alles, ändert nichts.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage { FormMessage(text: errorMessage) }
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.vertical, Theme.Spacing.m)
            }
            .entryFormChrome(title: "Einladen", saveTitle: "Einladung senden", isSaving: isSending,
                             canSave: email.contains("@") && !isSending,
                             onDone: { focusedField = nil }, onCancel: { dismiss() }, onSave: send)
            .onAppear { focusedField = true }
        }
    }

    private func send() {
        errorMessage = nil
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await store.invite(to: vehicleID, email: email.trimmingCharacters(in: .whitespaces), role: role)
                Haptics.success()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Invitations to vehicles of other accounts: accept or decline.
struct InvitationsView: View {
    let store: VehicleStore

    @State private var invitations: [PendingInvitation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var working: String?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    FormMessage(text: errorMessage)
                }
                .listRowBackground(Theme.card)
            }
            ForEach(invitations) { invitation in
                Section {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(verbatim: invitation.vehicleName).font(.headline)
                        Text(verbatim: subtitle(invitation))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    Button("Annehmen", systemImage: "checkmark.circle") { answer(invitation, accept: true) }
                        .foregroundStyle(Theme.brand)
                        .disabled(working != nil)
                    Button("Ablehnen", systemImage: "xmark.circle", role: .destructive) {
                        answer(invitation, accept: false)
                    }
                    .disabled(working != nil)
                }
                .listRowBackground(Theme.card)
            }
        }
        .themedBackground()
        .overlay {
            if isLoading, invitations.isEmpty {
                ProgressView()
            } else if invitations.isEmpty, errorMessage == nil {
                ContentUnavailableView("Keine Einladungen", systemImage: "envelope.open",
                                       description: Text("Wenn jemand ein Fahrzeug mit dir teilt, erscheint die Einladung hier."))
            }
        }
        .navigationTitle("Einladungen")
        .refreshable { await load() }
        .task { await load() }
    }

    private func subtitle(_ invitation: PendingInvitation) -> String {
        var parts: [String] = []
        if let name = invitation.invitedByName { parts.append(String(localized: "von \(name)")) }
        parts.append(VehicleRole(rawValue: invitation.role)?.label ?? invitation.role)
        if let expires = invitation.expiresAt {
            parts.append(String(localized: "gültig bis \(expires.formatted(date: .abbreviated, time: .omitted))"))
        }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        defer { isLoading = false }
        do {
            invitations = try await store.invitations()
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func answer(_ invitation: PendingInvitation, accept: Bool) {
        errorMessage = nil
        working = invitation.id
        Task {
            defer { working = nil }
            do {
                try await store.answer(invitation, accept: accept)
                if accept { Haptics.success() }
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

import FuelstatCore
import SwiftUI
import UIKit

/// Profil → Termine: the due dates of all vehicles, most urgent first, and the settings for reminders on this
/// iPhone. Due dates and their status come from the API.
struct AllRemindersView: View {
    let store: VehicleStore

    @State private var entries: [Entry] = []
    @State private var isLoading = true
    @State private var isEnabled = ReminderNotifications.isEnabled
    @State private var leadDays = ReminderNotifications.leadDays
    @State private var plannedCount = 0
    @State private var permissionDenied = false
    @State private var completing: Entry?

    private struct Entry: Identifiable {
        let vehicle: RemoteVehicle
        let reminder: RemoteReminder
        var id: String { vehicle.id + reminder.id }
    }

    var body: some View {
        List {
            Section {
                Toggle("Auf diesem iPhone erinnern", isOn: $isEnabled)
                    .tint(Theme.brand)
                if isEnabled {
                    Picker("Vorlauf", selection: $leadDays) {
                        ForEach(ReminderSchedule.leadDayOptions, id: \.self) { days in
                            Text(days == 1 ? "1 Tag vorher" : "\(days) Tage vorher").tag(days)
                        }
                    }
                    .tint(Theme.brand)
                }
                if permissionDenied {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Mitteilungen sind für Fuelstat ausgeschaltet.")
                            .font(.subheadline)
                        Button("Einstellungen öffnen") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(Theme.brand)
                    }
                }
            } header: {
                Text("Erinnerungen")
            } footer: {
                if isEnabled, !permissionDenied {
                    Text("\(plannedCount) Erinnerungen geplant, jeweils morgens um \(ReminderSchedule.hour) Uhr. Sie werden neu geplant, sobald die App die Termine lädt.")
                } else {
                    Text("Fuelstat erinnert dich vor TÜV, Wartung, Versicherung und Steuer – ohne Konto bei einem Mitteilungsdienst, nur auf diesem Gerät.")
                }
            }
            .listRowBackground(Theme.card)

            Section {
                NavigationLink("E-Mail-Benachrichtigungen") { MailNotificationsView() }
            }
            .listRowBackground(Theme.card)

            Section("Alle Fahrzeuge") {
                ForEach(entries) { entry in
                    if entry.vehicle.role.canRecord {
                        Button { completing = entry } label: { row(entry) }
                            .buttonStyle(.plain)
                            .accessibilityHint(Text("Trägt den Termin als erledigt ein"))
                    } else {
                        row(entry)
                    }
                }
                if entries.isEmpty, !isLoading {
                    Text("Keine Termine. Sie ergeben sich aus Erstzulassung und Ausgaben wie TÜV oder Wartung.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Theme.card)
        }
        .themedBackground()
        .overlay { if isLoading, entries.isEmpty { ProgressView() } }
        .navigationTitle("Termine")
        .refreshable { await load() }
        .task(id: store.entryChanges) { await load() }
        .onChange(of: isEnabled) { enabledChanged() }
        .onChange(of: leadDays) {
            ReminderNotifications.leadDays = leadDays
            Task { await load() }
        }
        .sheet(item: $completing) { entry in
            ExpenseFormView(store: store, vehicleID: entry.vehicle.id, category: entry.reminder.category)
        }
    }

    private func row(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            if store.vehicles.count > 1 {
                Text(verbatim: entry.vehicle.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.brandDeep)
            }
            ReminderRow(reminder: entry.reminder)
        }
        .accessibilityElement(children: .combine)
    }

    /// Loading the dates also replans the notifications (see `VehicleStore.reminders`).
    private func load() async {
        defer { isLoading = false }
        entries = await store.allReminders().map { Entry(vehicle: $0.vehicle, reminder: $0.reminder) }
        plannedCount = await ReminderNotifications.plannedCount()
    }

    /// Permission is asked for here, when the user switches reminders on – never at launch.
    private func enabledChanged() {
        Task {
            if isEnabled {
                let granted = await ReminderNotifications.requestPermission()
                permissionDenied = !granted
                ReminderNotifications.isEnabled = granted
                if !granted {
                    isEnabled = false
                    return
                }
                await load()
            } else if ReminderNotifications.isEnabled {
                ReminderNotifications.isEnabled = false
                ReminderNotifications.removeAll()
                plannedCount = 0
            }
        }
    }
}

/// Profil → Termine → E-Mail: which occasions the server mails about (`/notifications/preferences`). The mail
/// server and the sending are the server's job; the app only switches the channels. A different mail server is
/// entered in the web app.
struct MailNotificationsView: View {
    @Environment(AuthSession.self) private var auth

    @State private var preferences: NotificationPreferences?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isSaving = false

    private func title(_ occasion: NotificationPreferences.Occasion) -> LocalizedStringKey {
        switch occasion {
        case .reminders: "Termine"
        case .odometer: "Kilometerstand nachtragen"
        case .report: "Monatsbericht"
        case .inactive: "Lange kein Eintrag"
        }
    }

    private func explanation(_ occasion: NotificationPreferences.Occasion) -> LocalizedStringKey {
        switch occasion {
        case .reminders: "TÜV, Wartung, Versicherung und Steuer – vorher und noch einmal, wenn überfällig"
        case .odometer: "Wenn bei einer Tankfüllung der Kilometerstand fehlt"
        case .report: "Am Monatsanfang: Kosten, Strecke und Verbrauch je Fahrzeug"
        case .inactive: "Wenn für ein Fahrzeug 30 Tage nichts erfasst wurde"
        }
    }

    var body: some View {
        List {
            if let preferences {
                Section {
                    ForEach(NotificationPreferences.Occasion.allCases) { occasion in
                        Toggle(isOn: Binding(
                            get: { self.preferences?.isEmailOn(occasion) ?? false },
                            set: { change(.email(occasion, $0)) }
                        )) {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                Text(title(occasion))
                                Text(explanation(occasion)).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .tint(Theme.brand)
                        .disabled(!preferences.emailAvailable || isSaving)
                    }
                } header: {
                    Text("Per E-Mail")
                } footer: {
                    if !preferences.emailAvailable {
                        Text("Auf diesem Server ist noch kein Mailversand eingerichtet. Einen eigenen Mailserver trägst du in der Web-App ein.")
                    } else {
                        Text("Die Mails gehen an die Adresse deines Kontos. Erinnerungen auf diesem iPhone stellst du unter „Termine“ ein.")
                    }
                }
                .listRowBackground(Theme.card)

                Section {
                    Picker("Vorlauf für Termine", selection: Binding(
                        get: { self.preferences?.reminderDays ?? 30 },
                        set: { change(.reminderDays($0)) }
                    )) {
                        ForEach(leadDayOptions(including: preferences.reminderDays), id: \.self) { days in
                            Text(days == 1 ? "1 Tag vorher" : "\(days) Tage vorher").tag(days)
                        }
                    }
                    .tint(Theme.brand)
                    .disabled(isSaving)
                } footer: {
                    Text("Gilt für die Mails zu Terminen.")
                }
                .listRowBackground(Theme.card)
            }

            ErrorSection(message: errorMessage)
        }
        .themedBackground()
        .overlay { if isLoading, preferences == nil { ProgressView() } }
        .navigationTitle("E-Mail")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func leadDayOptions(including current: Int) -> [Int] {
        let options = [1, 3, 7, 14, 30, 60, 90, 180]
        return options.contains(current) ? options : (options + [current]).sorted()
    }

    private func load() async {
        defer { isLoading = false }
        do {
            preferences = try await auth.call { try await $0.notificationPreferences(token: $1) }
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Sends one change; the answer is the new state, so the switches always show what the server stored.
    private func change(_ update: NotificationPreferencesUpdate) {
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                preferences = try await auth.call { try await $0.updateNotificationPreferences(update, token: $1) }
            } catch {
                errorMessage = error.localizedDescription
                await load()
            }
        }
    }
}

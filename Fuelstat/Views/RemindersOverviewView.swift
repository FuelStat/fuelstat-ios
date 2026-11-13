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

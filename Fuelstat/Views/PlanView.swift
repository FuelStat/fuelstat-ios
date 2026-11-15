import FuelstatCore
import SwiftUI

/// Profil → Tarif: the booked plan, how long it runs and what it allows. All values come from `/whoami`; the app
/// decides nothing and offers no purchase (FuelStat/fuelstat#102).
struct PlanView: View {
    @Environment(AuthSession.self) private var auth

    static func name(of plan: String) -> String {
        switch plan {
        case "plus": String(localized: "Plus")
        case "fleet": String(localized: "Flotte")
        default: String(localized: "Free")
        }
    }

    var body: some View {
        List {
            if let plan = auth.user?.plan {
                Section {
                    LabeledContent("Dein Tarif", value: Self.name(of: plan.plan))
                    if plan.effectivePlan != plan.plan {
                        LabeledContent("Gilt gerade", value: Self.name(of: plan.effectivePlan))
                    }
                    if let until = plan.planUntil {
                        LabeledContent("Läuft bis", value: until.formatted(date: .long, time: .omitted))
                    }
                } footer: {
                    if plan.hasExpired {
                        Text("Dein gebuchter Tarif ist abgelaufen, es gelten die Rechte von Free. Deine Daten bleiben erhalten.")
                    } else if !plan.limitsEnabled {
                        Text("Auf diesem Server gelten keine Tarifgrenzen: Alle Funktionen von Plus stehen allen Konten offen.")
                    }
                }
                .listRowBackground(Theme.card)

                Section("Das ist in deinem Tarif enthalten") {
                    ForEach(rows(plan)) { row in
                        LabeledContent {
                            Text(verbatim: row.value)
                                .foregroundStyle(row.isAvailable ? Theme.brandDeep : .secondary)
                        } label: {
                            Text(row.title)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .listRowBackground(Theme.card)
            } else {
                ContentUnavailableView("Kein Tarif", systemImage: "star.circle",
                                       description: Text("Dieser Server kennt keine Tarife."))
            }
        }
        .themedBackground()
        .navigationTitle("Tarif")
        .navigationBarTitleDisplayMode(.inline)
        .task { await auth.refreshUser() }
    }

    private struct Row: Identifiable {
        let id = UUID()
        let title: LocalizedStringKey
        let value: String
        let isAvailable: Bool
    }

    /// The rights the API sends, in a fixed order; rights it does not send are left out.
    private func rows(_ plan: PlanInfo) -> [Row] {
        var rows: [Row] = []
        func limit(_ key: String, _ title: LocalizedStringKey, unlimitedText: String = String(localized: "unbegrenzt")) {
            guard let value = plan.limit(key) else { return }
            switch value {
            case .none: rows.append(Row(title: title, value: unlimitedText, isAvailable: true))
            case .some(0): rows.append(Row(title: title, value: String(localized: "nicht enthalten"), isAvailable: false))
            case .some(let number): rows.append(Row(title: title, value: String(number), isAvailable: true))
            }
        }
        func flag(_ key: String, _ title: LocalizedStringKey) {
            guard let value = plan.isEnabled(key) else { return }
            rows.append(Row(title: title, value: value ? String(localized: "enthalten") : String(localized: "nicht enthalten"),
                            isAvailable: value))
        }
        limit("maxVehicles", "Fahrzeuge")
        limit("maxArchivedVehicles", "Archivierte Fahrzeuge")
        limit("customCategories", "Eigene Kategorien")
        flag("premiumCategories", "Weitere Ausgabenkategorien")
        limit("tripCategories", "Zwecke im Fahrtenbuch", unlimitedText: String(localized: "alle"))
        flag("tripExport", "Fahrtenbuch exportieren")
        flag("sharing", "Fahrzeuge teilen")
        flag("comparison", "Fahrzeugvergleich")
        flag("pdfReport", "PDF-Bericht")
        flag("pushReminders", "Push-Erinnerungen")
        flag("fleet", "Flottenverwaltung")
        return rows
    }
}

import AppIntents
import Foundation

/// "Was ist als Nächstes fällig?" – the most urgent due date as calculated by the API (`/reminders`).
struct NextReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Was ist fällig?"
    static var description = IntentDescription("Nennt die dringendste Fälligkeit eines Fahrzeugs, zum Beispiel TÜV, Wartung oder Versicherung.",
                                               categoryName: "Abfragen")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Fahrzeug")
    var vehicle: VehicleEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Nächste Fälligkeit für \(\.$vehicle)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let reminders = try await IntentAPI.call { try await $0.reminders(vehicleID: vehicle.id, token: $1) }
        guard let next = RemoteReminder.byUrgency(reminders).first else {
            let text = String(localized: "Für \(vehicle.name) sind keine Termine eingetragen.")
            return .result(value: text, dialog: IntentDialog(stringLiteral: text))
        }
        let text = String(localized: "\(vehicle.name): \(next.title) \(Self.when(next))")
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }

    private static func when(_ reminder: RemoteReminder) -> String {
        if let days = reminder.days {
            let date = reminder.dueDate.map { $0.formatted(date: .long, time: .omitted) }
            switch days {
            case ..<0: return String(localized: "ist seit \(-days) Tagen überfällig.")
            case 0: return String(localized: "ist heute fällig.")
            case 1: return String(localized: "ist morgen fällig.")
            default:
                if let date { return String(localized: "ist in \(days) Tagen fällig, am \(date).") }
                return String(localized: "ist in \(days) Tagen fällig.")
            }
        }
        if let km = reminder.dueKm {
            return String(localized: "ist bei \(Fmt.kilometres(km)) fällig.")
        }
        return reminder.status == .overdue ? String(localized: "ist überfällig.") : String(localized: "steht an.")
    }
}

/// "Wie ist mein Verbrauch?" – the average consumption the API calculated (`/stats`).
struct AverageConsumptionIntent: AppIntent {
    static var title: LocalizedStringResource = "Durchschnittsverbrauch"
    static var description = IntentDescription("Nennt den Durchschnittsverbrauch eines Fahrzeugs pro 100 km.",
                                               categoryName: "Abfragen")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Fahrzeug")
    var vehicle: VehicleEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Durchschnittsverbrauch von \(\.$vehicle)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let stats = try await IntentAPI.call { try await $0.stats(vehicleID: vehicle.id, token: $1) }
        guard let average = stats.averageConsumption else {
            throw IntentError.noConsumption(vehicle: vehicle.name)
        }
        let unit = vehicle.fuelType.tankCapacityUnit
        let text = String(localized: "\(vehicle.name) verbraucht im Schnitt \(Fmt.number(average, digits: 1)) \(unit) auf 100 km.")
        return .result(value: average, dialog: IntentDialog(stringLiteral: text))
    }
}

/// Ready-made shortcuts for Siri and the Shortcuts app. Every phrase names the app, as Siri requires.
struct FuelstatShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .teal

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddFuelEntryIntent(),
            phrases: [
                "Tanken in \(.applicationName) erfassen",
                "Tankvorgang in \(.applicationName) eintragen",
                "Mit \(.applicationName) Tanken erfassen",
                "Ich habe getankt in \(.applicationName)",
                "Tankquittung in \(.applicationName) erfassen",
                "\(\.$vehicle) getankt in \(.applicationName)",
            ],
            shortTitle: "Tanken erfassen",
            systemImageName: "fuelpump"
        )
        AppShortcut(
            intent: AddChargingEntryIntent(),
            phrases: [
                "Laden in \(.applicationName) erfassen",
                "Ladevorgang in \(.applicationName) eintragen",
                "Ich habe geladen in \(.applicationName)",
                "\(\.$vehicle) geladen in \(.applicationName)",
            ],
            shortTitle: "Laden erfassen",
            systemImageName: "bolt.car"
        )
        // Avoid "Termin": Siri hands such questions to the Calendar app.
        AppShortcut(
            intent: NextReminderIntent(),
            phrases: [
                "Was ist bei \(.applicationName) fällig",
                "Was ist in \(.applicationName) fällig",
                "Was steht bei \(.applicationName) an",
                "Fälligkeiten in \(.applicationName)",
                "Nächste Fälligkeit in \(.applicationName)",
                "Wann ist der TÜV laut \(.applicationName)",
                "Was ist bei \(\.$vehicle) in \(.applicationName) fällig",
                "Fälligkeiten von \(\.$vehicle) in \(.applicationName)",
            ],
            shortTitle: "Was ist fällig?",
            systemImageName: "calendar.badge.clock"
        )
        AppShortcut(
            intent: AverageConsumptionIntent(),
            phrases: [
                "Verbrauch in \(.applicationName)",
                "Verbrauch bei \(.applicationName)",
                "Wie ist mein Verbrauch in \(.applicationName)",
                "Wie viel verbrauche ich laut \(.applicationName)",
                "Durchschnittsverbrauch in \(.applicationName)",
                "Zeig meinen Verbrauch in \(.applicationName)",
                "Verbrauch von \(\.$vehicle) in \(.applicationName)",
                "Wie viel verbraucht \(\.$vehicle) laut \(.applicationName)",
            ],
            shortTitle: "Verbrauch",
            systemImageName: "gauge.with.dots.needle.33percent"
        )
        AppShortcut(
            intent: OpenEntryIntent(),
            phrases: [
                "Eintrag in \(.applicationName) erfassen",
                "Neuer Eintrag in \(.applicationName)",
            ],
            shortTitle: "Eintrag öffnen",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: OpenVehicleIntent(),
            phrases: [
                "\(\.$target) in \(.applicationName) öffnen",
                "Fahrzeug in \(.applicationName) öffnen",
            ],
            shortTitle: "Fahrzeug öffnen",
            systemImageName: "car.side"
        )
    }
}

import AppIntents
import Foundation
import FuelstatCore

/// Siri / Shortcuts: "Tanken erfassen" without opening the app.
struct AddFuelEntryIntent: AppIntent {
    static var title: LocalizedStringResource = "Tanken erfassen"
    static var description = IntentDescription("Speichert einen Tankvorgang in Fuelstat. Verbrauch und Kosten berechnet der Server.",
                                               categoryName: "Erfassen")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Fahrzeug")
    var vehicle: VehicleEntity

    @Parameter(title: "Menge", description: "Getankte Menge in Litern (bei Gas in Kilogramm), z. B. 42,5",
               requestValueDialog: "Wie viel hast du getankt?")
    var amount: String

    @Parameter(title: "Betrag", description: "Gesamtbetrag in Euro, z. B. 75,30",
               requestValueDialog: "Wie viel hat es gekostet?")
    var total: String

    @Parameter(title: "Kilometerstand", description: "Optional; hilft bei der Verbrauchsberechnung")
    var odometer: Int?

    @Parameter(title: "Vollgetankt", default: true)
    var isFull: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$amount) für \(\.$total) € bei \(\.$vehicle) erfassen") {
            \.$odometer
            \.$isFull
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let amount = try EntryRecorder.number(amount, for: $amount,
                                             retry: "Das habe ich nicht verstanden. Wie viele Liter waren es, zum Beispiel 42,5?")
        let total = try EntryRecorder.number(total, for: $total,
                                            retry: "Das habe ich nicht verstanden. Wie viel Euro waren es, zum Beispiel 75,30?")
        let message = try await EntryRecorder.save(vehicle: vehicle, charging: false, amount: amount, total: total,
                                                   odometer: odometer, isFull: isFull)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// Siri / Shortcuts: "Laden erfassen" without opening the app.
struct AddChargingEntryIntent: AppIntent {
    static var title: LocalizedStringResource = "Laden erfassen"
    static var description = IntentDescription("Speichert einen Ladevorgang in Fuelstat. Verbrauch und Kosten berechnet der Server.",
                                               categoryName: "Erfassen")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Fahrzeug")
    var vehicle: VehicleEntity

    @Parameter(title: "Energie", description: "Geladene Energie in kWh, z. B. 38,5",
               requestValueDialog: "Wie viele Kilowattstunden hast du geladen?")
    var amount: String

    @Parameter(title: "Betrag", description: "Gesamtbetrag in Euro, z. B. 75,30",
               requestValueDialog: "Wie viel hat es gekostet?")
    var total: String

    @Parameter(title: "Kilometerstand", description: "Optional; hilft bei der Verbrauchsberechnung")
    var odometer: Int?

    @Parameter(title: "Voll geladen", default: true)
    var isFull: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$amount) kWh für \(\.$total) € bei \(\.$vehicle) erfassen") {
            \.$odometer
            \.$isFull
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let amount = try EntryRecorder.number(amount, for: $amount,
                                             retry: "Das habe ich nicht verstanden. Wie viele Kilowattstunden waren es, zum Beispiel 38,5?")
        let total = try EntryRecorder.number(total, for: $total,
                                            retry: "Das habe ich nicht verstanden. Wie viel Euro waren es, zum Beispiel 12,40?")
        let message = try await EntryRecorder.save(vehicle: vehicle, charging: true, amount: amount, total: total,
                                                   odometer: odometer, isFull: isFull)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// Opens the quick-entry sheet in the app, e.g. from the Action button or a Control Center shortcut.
struct OpenEntryIntent: AppIntent {
    static var title: LocalizedStringResource = "Eintrag in Fuelstat erfassen"
    static var description = IntentDescription("Öffnet Fuelstat mit der Eingabemaske für Tanken oder Laden.",
                                               categoryName: "Erfassen")
    static var openAppWhenRun = true

    @Parameter(title: "Art")
    var kind: EntryKindAppEnum?

    @Parameter(title: "Fahrzeug")
    var vehicle: VehicleEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.pending = .addEntry(kind?.entryKind, vehicleID: vehicle?.id)
        return .result()
    }
}

/// Opens a vehicle in the app (also used when a vehicle is picked in Spotlight or Shortcuts).
struct OpenVehicleIntent: OpenIntent {
    static var title: LocalizedStringResource = "Fahrzeug öffnen"
    static var description = IntentDescription("Öffnet ein Fahrzeug in Fuelstat.")

    @Parameter(title: "Fahrzeug")
    var target: VehicleEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.pending = .openVehicle(target.id)
        return .result()
    }
}

/// Saves a fill-up or charging session through the same API call as the entry sheet.
enum EntryRecorder {
    /// Reads a spoken or typed number ("42,5", "75 Euro 30"). If that fails, Siri asks again with an example
    /// instead of repeating the same question.
    static func number(_ text: String, for parameter: IntentParameter<String>,
                       retry: LocalizedStringResource) throws -> Double {
        guard let value = SpokenNumber.parse(text), value > 0 else {
            throw parameter.needsValueError(IntentDialog(retry))
        }
        return value
    }

    static func save(vehicle: VehicleEntity, charging: Bool, amount: Double, total: Double, odometer: Int?,
                     isFull: Bool) async throws -> String {
        let units = vehicle.fuelType.fillupUnits
        guard let unit = charging ? units.first(where: { $0 == "kwh" }) : units.first(where: { $0 != "kwh" }) else {
            throw IntentError.wrongEntryKind(vehicle: vehicle.name, useCharging: !charging)
        }
        guard amount.isFinite, amount > 0 else { throw IntentError.invalidAmount }
        guard total.isFinite, total > 0 else { throw IntentError.invalidTotal }

        let input = FillupInput(vehicleId: vehicle.id, unit: unit, amount: amount, totalCostEur: total,
                                odometerKm: odometer, station: nil, filledAt: .now, isFull: isFull,
                                skipPrevious: false)
        let created = try await IntentAPI.call { try await $0.createFillup(input, token: $1) }
        VehicleStore.storedLastVehicleID = vehicle.id
        await IntentRouter.shared.entrySaved()
        WidgetRefresh.reload()

        let unitLabel = unit == "kwh" ? "kWh" : (unit == "kg" ? "kg" : "L")
        var lines = [String(localized: "\(Fmt.number(amount, digits: 2)) \(unitLabel) für \(Fmt.currency(total)) bei \(vehicle.name) gespeichert.")]
        lines += created.warnings.compactMap(\.message)
        return lines.joined(separator: "\n")
    }
}

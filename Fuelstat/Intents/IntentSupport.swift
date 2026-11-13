import AppIntents
import Foundation
import Observation

/// API access for intents. They run in the app process and use the sign-in the app stored in the Keychain,
/// renewing the device session when needed. Nothing is calculated here, all figures come from the API.
enum IntentAPI {
    static func call<T>(_ operation: (APIClient, String) async throws -> T) async throws -> T {
        do {
            return try await SignedInAPI.call(.configured, operation)
        } catch APIError.unauthorized {
            throw IntentError.notSignedIn
        } catch let error as APIError {
            throw IntentError.api(error.localizedDescription)
        }
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case notSignedIn
    case invalidAmount
    case invalidTotal
    case wrongEntryKind(vehicle: String, useCharging: Bool)
    case noConsumption(vehicle: String)
    case api(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notSignedIn:
            "Bitte öffne Fuelstat und melde dich an."
        case .invalidAmount:
            "Die Menge muss größer als null sein."
        case .invalidTotal:
            "Der Betrag muss größer als null sein."
        case .wrongEntryKind(let vehicle, let useCharging):
            useCharging
                ? "\(vehicle) wird geladen, nicht getankt. Nutze „Laden erfassen“."
                : "\(vehicle) kann nicht geladen werden. Nutze „Tanken erfassen“."
        case .noConsumption(let vehicle):
            "Für \(vehicle) gibt es noch keinen Durchschnittsverbrauch. Dafür braucht es zwei volle Tankvorgänge mit Kilometerstand."
        case .api(let message):
            "\(message)"
        }
    }
}

/// Requests from intents that open the app, picked up by the tab view once the user is signed in.
@MainActor
@Observable
final class IntentRouter {
    enum Request: Equatable {
        case addEntry(EntryKind?, vehicleID: String?)
        case openVehicle(String)
    }

    static let shared = IntentRouter()

    var pending: Request?
    /// Changes when an intent saved an entry in the background, so open screens reload.
    private(set) var savedEntries = 0

    func entrySaved() {
        savedEntries += 1
    }
}

/// Fuel or charging, as a choice in Shortcuts.
enum EntryKindAppEnum: String, AppEnum {
    case fuel
    case charge

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Art des Eintrags")
    static var caseDisplayRepresentations: [EntryKindAppEnum: DisplayRepresentation] = [
        .fuel: DisplayRepresentation(title: "Tanken", image: .init(systemName: "fuelpump")),
        .charge: DisplayRepresentation(title: "Laden", image: .init(systemName: "bolt.car")),
    ]

    var entryKind: EntryKind {
        switch self {
        case .fuel: .fuel
        case .charge: .charge
        }
    }
}

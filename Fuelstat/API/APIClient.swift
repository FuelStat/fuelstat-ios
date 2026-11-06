import Foundation

enum APIError: LocalizedError, Equatable {
    case unauthorized
    case server(code: String, status: Int)
    case invalidResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Deine Anmeldung ist abgelaufen. Bitte melde dich erneut an."
        case .server(let code, _):
            switch code {
            case "invalid_credentials": "E-Mail oder Passwort ist falsch."
            case "email_already_exists": "Für diese E-Mail gibt es bereits ein Konto."
            case "invalid_mfa_code": "Der Bestätigungscode ist falsch."
            case "too_many_attempts": "Zu viele Versuche. Bitte warte kurz."
            case "registration_disabled": "Die Registrierung ist derzeit geschlossen."
            case "plan_required": "Dein Tarif erlaubt keine weiteren Fahrzeuge."
            case "missing_name": "Bitte gib einen Namen ein."
            case "invalid_year": "Das Baujahr ist ungültig."
            case "invalid_licensePlate": "Das Kennzeichen ist ungültig (max. 15 Zeichen)."
            case "invalid_vin": "Die FIN ist ungültig (max. 17 Zeichen)."
            case "invalid_firstRegistration": "Das Datum der Erstzulassung ist ungültig."
            case "invalid_odometerKm": "Der Kilometerstand ist ungültig."
            case "invalid_tankCapacity": "Der Tankinhalt ist ungültig."
            case "invalid_batteryCapacity": "Die Akkukapazität ist ungültig."
            default: "Serverfehler (\(code))."
            }
        case .invalidResponse:
            "Unerwartete Antwort vom Server."
        case .network(let message):
            "Keine Verbindung zum Server: \(message)"
        }
    }

    /// The API error code, e.g. `mfa_required`.
    var code: String? {
        if case .server(let code, _) = self { return code }
        return nil
    }
}

/// Minimal client for the Fuelstat REST API (https://tanken.1emc.de/api/v1).
struct APIClient {
    static let defaultBaseURL = URL(string: "https://tanken.1emc.de/api/v1")!

    var baseURL: URL = defaultBaseURL
    var session: URLSession = .shared

    func login(email: String, password: String, code: String?) async throws -> AuthResponse {
        var body = ["email": email, "password": password]
        if let code, !code.isEmpty { body["code"] = code }
        return try await send("auth/login", method: "POST", body: body, token: nil)
    }

    func register(email: String, password: String) async throws -> AuthResponse {
        try await send("auth/register", method: "POST", body: ["email": email, "password": password], token: nil)
    }

    func whoami(token: String) async throws -> APIUser {
        try await send("whoami", method: "GET", body: nil as [String: String]?, token: token)
    }

    func revoke(token: String) async throws {
        let _: EmptyResponse = try await send(
            "auth/tokens/revoke", method: "POST", body: ["token": token, "reason": "logout"], token: token
        )
    }

    func vehicles(token: String) async throws -> [RemoteVehicle] {
        try await send("vehicles", method: "GET", body: nil as [String: String]?, token: token)
    }

    func createVehicle(_ request: VehicleCreateRequest, token: String) async throws -> RemoteVehicle {
        try await send("vehicles", method: "POST", body: request, token: token)
    }

    func vehicle(id: String, token: String) async throws -> RemoteVehicle {
        try await send("vehicles/\(id)", method: "GET", body: nil as [String: String]?, token: token)
    }

    // MARK: - Transport

    private struct EmptyResponse: Decodable {}

    private func send<Body: Encodable, Response: Decodable>(
        _ path: String, method: String, body: Body?, token: String?
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        guard (200..<300).contains(http.statusCode) else {
            let code = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error
            if http.statusCode == 401, token != nil, code != "mfa_required" {
                throw APIError.unauthorized
            }
            throw APIError.server(code: code ?? "http_\(http.statusCode)", status: http.statusCode)
        }

        if Response.self == EmptyResponse.self { return EmptyResponse() as! Response }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }
}

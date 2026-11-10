import Foundation
import FuelstatCore

enum APIError: LocalizedError, Equatable {
    case unauthorized
    case server(code: String, status: Int)
    /// A plan limit was reached (`plan_required`), e.g. the number of vehicles.
    case planRequired(feature: String?, limit: Int?, plan: String?)
    case invalidResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            String(localized: "Deine Anmeldung ist abgelaufen. Bitte melde dich erneut an.")
        case .planRequired(let feature, let limit, let plan):
            Self.planMessage(feature: feature, limit: limit, plan: plan)
        case .server(let code, _):
            switch code {
            case "invalid_credentials": String(localized: "E-Mail oder Passwort ist falsch.")
            case "invalid_current_password": String(localized: "Das Passwort ist falsch.")
            case "password_too_short": String(localized: "Das Passwort muss mindestens 8 Zeichen lang sein.")
            case "invalid_email": String(localized: "Bitte gib eine gültige E-Mail-Adresse ein.")
            case "mail_not_configured": String(localized: "Auf diesem Server ist kein Mailversand eingerichtet.")
            case "smtp_failed": String(localized: "Die Mail konnte nicht verschickt werden. Bitte versuche es später erneut.")
            case "resend_too_soon": String(localized: "Bitte warte eine Minute, bevor du die Mail erneut anforderst.")
            case "already_verified": String(localized: "Deine E-Mail-Adresse ist bereits bestätigt.")
            case "mfa_already_enabled": String(localized: "Die Zwei-Faktor-Anmeldung ist bereits aktiv.")
            case "mfa_not_enabled": String(localized: "Die Zwei-Faktor-Anmeldung ist nicht aktiv.")
            case "mfa_not_set_up": String(localized: "Bitte richte die Zwei-Faktor-Anmeldung zuerst neu ein.")
            case "invalid_terms_version":
                String(localized: "Die Nutzungsbedingungen wurden gerade geändert. Bitte lies die neue Fassung.")
            case "nothing_to_update": String(localized: "Es gibt nichts zu ändern.")
            case "email_already_exists": String(localized: "Für diese E-Mail gibt es bereits ein Konto.")
            case "invalid_mfa_code": String(localized: "Der Bestätigungscode ist falsch.")
            case "too_many_attempts": String(localized: "Zu viele Versuche. Bitte warte kurz.")
            case "registration_disabled": String(localized: "Die Registrierung ist derzeit geschlossen.")
            case "missing_name": String(localized: "Bitte gib einen Namen ein.")
            case "invalid_year": String(localized: "Das Baujahr ist ungültig.")
            case "invalid_licensePlate": String(localized: "Das Kennzeichen ist ungültig (max. 15 Zeichen).")
            case "invalid_vin": String(localized: "Die FIN ist ungültig (max. 17 Zeichen).")
            case "invalid_firstRegistration": String(localized: "Das Datum der Erstzulassung ist ungültig.")
            case "invalid_odometerKm": String(localized: "Der Kilometerstand ist ungültig.")
            case "invalid_tankCapacity": String(localized: "Der Tankinhalt ist ungültig.")
            case "invalid_batteryCapacity": String(localized: "Die Akkukapazität ist ungültig.")
            case "vehicle_not_found": String(localized: "Das Fahrzeug gibt es nicht mehr.")
            case "missing_file", "invalid_image": String(localized: "Das Bild konnte nicht verarbeitet werden.")
            case "http_413": String(localized: "Das Bild ist zu groß.")
            case "http_429", "too_many_requests": String(localized: "Zu viele Anfragen. Bitte warte kurz.")
            case "invalid_amount": String(localized: "Die Menge ist ungültig.")
            case "invalid_totalCostEur": String(localized: "Der Betrag ist ungültig.")
            case "invalid_filledAt": String(localized: "Das Datum ist ungültig.")
            case "invalid_unit": String(localized: "Die Einheit passt nicht zum Fahrzeug.")
            case "stations_not_configured":
                String(localized: "Die Tankstellensuche ist auf diesem Server nicht eingerichtet.")
            case "stations_unavailable": String(localized: "Tankerkönig ist gerade nicht erreichbar.")
            case "email_not_verified":
                String(localized: "Bitte bestätige zuerst deine E-Mail-Adresse. Den Link dazu haben wir dir per Mail geschickt.")
            case "invalid_message": String(localized: "Die Nachricht muss zwischen 3 und 5000 Zeichen lang sein.")
            case "invalid_category": String(localized: "Bitte wähle eine Art aus.")
            case "forbidden": String(localized: "Dazu fehlen dir die Rechte.")
            case "user_not_found", "account_not_found": String(localized: "Das Konto gibt es nicht mehr.")
            default: String(localized: "Serverfehler (\(code)).")
            }
        case .invalidResponse:
            String(localized: "Unerwartete Antwort vom Server.")
        case .network(let message):
            String(localized: "Keine Verbindung zum Server: \(message)")
        }
    }

    /// The API error code, e.g. `mfa_required`.
    var code: String? {
        switch self {
        case .server(let code, _): code
        case .planRequired: "plan_required"
        default: nil
        }
    }

    private static func planMessage(feature: String?, limit: Int?, plan: String?) -> String {
        let planName = plan.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        if feature == "maxVehicles", let limit {
            if let planName {
                return String(localized: "Mit deinem Tarif \(planName) sind höchstens \(limit) Fahrzeuge möglich. Für mehr Fahrzeuge brauchst du einen größeren Tarif.")
            }
            return String(localized: "Dein Tarif erlaubt höchstens \(limit) Fahrzeuge.")
        }
        return String(localized: "Diese Funktion ist in deinem Tarif nicht enthalten.")
    }
}

/// Client for the Fuelstat REST API, following `docs/openapi.1.0.0.yaml` in FuelStat/fuelstat.
struct APIClient {
    static let defaultBaseURL = URL(string: "https://tanken.1emc.de/api/v1")!

    /// API base, e.g. `https://tanken.1emc.de/api/v1`.
    var baseURL: URL = defaultBaseURL
    var session: URLSession = .shared

    // MARK: - Server

    func health() async throws -> HealthResponse {
        try await send("health", token: nil)
    }

    /// Absolute address for an image path from an API response (they are relative, e.g. `/api/v1/files/…`).
    func resolve(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    // MARK: - Auth

    func login(email: String, password: String, code: String?) async throws -> AuthResponse {
        var body = ["email": email, "password": password]
        if let code, !code.isEmpty { body["code"] = code }
        return try await send("auth/login", method: "POST", body: body, token: nil)
    }

    func register(email: String, password: String) async throws -> AuthResponse {
        try await send("auth/register", method: "POST", body: ["email": email, "password": password], token: nil)
    }

    func whoami(token: String) async throws -> APIUser {
        try await send("whoami", token: token)
    }

    /// Asks for a password reset link. The API answers the same whether the account exists or not.
    func forgotPassword(email: String) async throws {
        let _: EmptyResponse = try await send("auth/forgot-password", method: "POST", body: ["email": email], token: nil)
    }

    /// Changes the password. The API revokes all tokens, including this one, and returns a new one.
    func changePassword(current: String, new: String, token: String) async throws -> String {
        let response: TokenResponse = try await send(
            "auth/password", method: "POST", body: ["currentPassword": current, "newPassword": new], token: token
        )
        return response.token
    }

    func resendVerification(token: String) async throws -> VerificationSent {
        try await send("auth/resend-verification", method: "POST", token: token)
    }

    func acceptTerms(version: String, token: String) async throws {
        let _: EmptyResponse = try await send("auth/accept-terms", method: "POST", body: ["version": version],
                                              token: token)
    }

    func updateProfile(userID: String, _ patch: ProfilePatch, token: String) async throws -> APIUser {
        try await send("auth/users/\(userID)", method: "PATCH", body: patch, token: token)
    }

    /// Uploads a JPEG as profile picture; set it with `updateProfile` afterwards.
    func uploadProfileImage(jpeg: Data, token: String) async throws -> UploadedMedia {
        try await upload(jpeg: jpeg, to: "media/upload", token: token)
    }

    /// Signs out everywhere: every token issued so far stops working, this device's included.
    func revokeAll(userID: String, token: String) async throws {
        let _: EmptyResponse = try await send("auth/users/\(userID)/revoke-all", method: "POST",
                                              body: ["reason": "app_revoke_all"], token: token)
    }

    // MARK: - Two-factor authentication

    func mfaSetup(token: String) async throws -> MFASetup {
        try await send("auth/mfa/setup", method: "POST", token: token)
    }

    func mfaEnable(code: String, token: String) async throws {
        let _: EmptyResponse = try await send("auth/mfa/enable", method: "POST", body: ["code": code], token: token)
    }

    func mfaDisable(password: String, code: String, token: String) async throws {
        let _: EmptyResponse = try await send("auth/mfa/disable", method: "POST",
                                              body: ["password": password, "code": code], token: token)
    }

    /// Exchanges a valid token for a new one with 7 more days, up to 90 days after the last password sign-in.
    func refresh(token: String) async throws -> String {
        let response: TokenResponse = try await send("auth/refresh", method: "POST", token: token)
        return response.token
    }

    func revoke(token: String) async throws {
        let _: EmptyResponse = try await send(
            "auth/tokens/revoke", method: "POST", body: ["token": token, "reason": "logout"], token: token
        )
    }

    /// Deletes the account with all own vehicles, entries and images. Entries on vehicles shared by others are
    /// handed over to their owners. All tokens of the account stop working.
    func deleteAccount(userID: String, token: String) async throws {
        let _: EmptyResponse = try await send("auth/users/\(userID)", method: "DELETE", token: token)
    }

    // MARK: - Feedback

    func sendFeedback(_ input: FeedbackInput, token: String) async throws -> FeedbackResponse {
        try await send("feedback", method: "POST", body: input, token: token)
    }

    // MARK: - Vehicles

    func vehicles(token: String) async throws -> [RemoteVehicle] {
        try await send("vehicles", token: token)
    }

    func vehicle(id: String, token: String) async throws -> RemoteVehicle {
        try await send("vehicles/\(id)", token: token)
    }

    func createVehicle(_ input: VehicleInput, token: String) async throws -> RemoteVehicle {
        var input = input
        input.sendsNulls = false
        return try await send("vehicles", method: "POST", body: input, token: token)
    }

    func updateVehicle(id: String, _ input: VehicleInput, token: String) async throws -> RemoteVehicle {
        var input = input
        input.sendsNulls = true
        return try await send("vehicles/\(id)", method: "PATCH", body: input, token: token)
    }

    func setVehicleImage(id: String, imageURL: String?, token: String) async throws -> RemoteVehicle {
        try await send("vehicles/\(id)", method: "PATCH", body: VehicleImagePatch(imageUrl: imageURL), token: token)
    }

    func deleteVehicle(id: String, token: String) async throws {
        let _: EmptyResponse = try await send("vehicles/\(id)", method: "DELETE", token: token)
    }

    func stats(vehicleID: String, token: String) async throws -> VehicleStats {
        try await send("vehicles/\(vehicleID)/stats", token: token)
    }

    func fillups(vehicleID: String, limit: Int, token: String) async throws -> [RemoteFillup] {
        try await send("vehicles/\(vehicleID)/fillups", query: [URLQueryItem(name: "limit", value: String(limit))],
                       token: token)
    }

    /// Fill-ups, newest first. `offset` pages through older ones.
    func fillups(vehicleID: String, limit: Int, offset: Int, token: String) async throws -> [RemoteFillup] {
        try await send("vehicles/\(vehicleID)/fillups", query: [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ], token: token)
    }

    func deleteFillup(id: String, token: String) async throws {
        let _: EmptyResponse = try await send("fillups/\(id)", method: "DELETE", token: token)
    }

    /// Due dates (TÜV, service, insurance, tax) with their status, as calculated by the API.
    func reminders(vehicleID: String, token: String) async throws -> [RemoteReminder] {
        try await send("vehicles/\(vehicleID)/reminders", token: token)
    }

    func createFillup(_ input: FillupInput, token: String) async throws -> FillupCreated {
        try await send("fillups", method: "POST", body: input, token: token)
    }

    /// Fuel stations near a location with current prices (Tankerkönig via the Fuelstat API).
    func stations(latitude: Double, longitude: Double, radiusKm: Int, type: String, token: String) async throws
        -> [RemoteStation] {
        let response: StationsResponse = try await send("stations", query: [
            URLQueryItem(name: "lat", value: String(format: "%.5f", latitude)),
            URLQueryItem(name: "lng", value: String(format: "%.5f", longitude)),
            URLQueryItem(name: "radius", value: String(radiusKm)),
            URLQueryItem(name: "type", value: type),
        ], token: token)
        return response.stations
    }

    /// Uploads a JPEG as vehicle photo. The server scales it down, strips metadata and stores it as WebP.
    func uploadVehicleImage(vehicleID: String, jpeg: Data, token: String) async throws -> RemoteMedia {
        try await upload(jpeg: jpeg, to: "vehicles/\(vehicleID)/media/upload", token: token)
    }

    private func upload<Response: Decodable>(jpeg: Data, to path: String, token: String) async throws -> Response {
        let boundary = "fuelstat-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(jpeg)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = makeRequest(path, method: "POST", query: [], token: token)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await perform(request, token: token)
    }

    // MARK: - Transport

    private struct EmptyResponse: Decodable {}
    private struct NoBody: Encodable {}

    private func send<Response: Decodable>(
        _ path: String, method: String = "GET", query: [URLQueryItem] = [], token: String?
    ) async throws -> Response {
        try await send(path, method: method, query: query, body: nil as NoBody?, token: token)
    }

    private func send<Body: Encodable, Response: Decodable>(
        _ path: String, method: String = "GET", query: [URLQueryItem] = [], body: Body?, token: String?
    ) async throws -> Response {
        var request = makeRequest(path, method: method, query: query, token: token)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        return try await perform(request, token: token)
    }

    private func makeRequest(_ path: String, method: String, query: [URLQueryItem], token: String?) -> URLRequest {
        var url = baseURL.appendingPathComponent(path)
        if !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = query
            url = components.url ?? url
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform<Response: Decodable>(_ request: URLRequest, token: String?) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        guard (200..<300).contains(http.statusCode) else {
            let info = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
            let code = info?.error
            // These 401s mean a wrong password or code in the request, not an expired sign-in.
            let inputErrors: Set<String> = ["mfa_required", "invalid_mfa_code", "invalid_current_password"]
            if http.statusCode == 401, token != nil, !inputErrors.contains(code ?? "") {
                throw APIError.unauthorized
            }
            if code == "plan_required" {
                throw APIError.planRequired(feature: info?.feature, limit: info?.limit, plan: info?.plan)
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

extension APIClient {
    /// Client for the server the user chose (stored in UserDefaults), or the hosted service.
    static var configured: APIClient {
        APIClient(baseURL: ServerSettings.baseURL)
    }
}

/// The server address the user chose on the sign-in screen.
enum ServerSettings {
    private static let key = "api.baseURL"

    static var baseURL: URL {
        UserDefaults.standard.string(forKey: key).flatMap(URL.init(string:)) ?? APIClient.defaultBaseURL
    }

    static var isCustom: Bool { baseURL != APIClient.defaultBaseURL }

    static func save(_ url: URL) {
        if url == APIClient.defaultBaseURL {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(url.absoluteString, forKey: key)
        }
    }

    static func displayName(of url: URL) -> String { ServerAddress.displayName(of: url) }
}

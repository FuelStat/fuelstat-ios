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
            case "fillup_edit_window_expired":
                String(localized: "Tank- und Ladevorgänge lassen sich nur 14 Tage lang ändern. Den Kilometerstand kannst du weiterhin nachtragen.")
            case "fillup_not_found", "entry_not_found", "trip_not_found":
                String(localized: "Den Eintrag gibt es nicht mehr.")
            case "read_only": String(localized: "Du darfst dieses Fahrzeug nur ansehen.")
            case "entry_not_editable": String(localized: "Diesen Eintrag darf nur ändern, wer ihn erfasst hat, oder der Besitzer.")
            case "owner_only": String(localized: "Das darf nur der Besitzer des Fahrzeugs.")
            case "unknown_category", "missing_category": String(localized: "Bitte wähle eine Kategorie.")
            case "invalid_amountEur": String(localized: "Der Betrag ist ungültig.")
            case "invalid_occurredAt", "invalid_startedAt", "invalid_endedAt": String(localized: "Das Datum ist ungültig.")
            case "invalid_odometerEnd": String(localized: "Der Kilometerstand am Ende ist ungültig.")
            case "invalid_odometerStart":
                String(localized: "Der Kilometerstand am Start ist ungültig oder höher als am Ende.")
            case "invalid_distanceKm": String(localized: "Die Strecke ist ungültig.")
            case "invalid_purpose": String(localized: "Bitte wähle einen Zweck.")
            case "name_too_long": String(localized: "Der Name ist zu lang.")
            case "name_taken": String(localized: "Eine Kategorie mit diesem Namen gibt es schon.")
            case "invalid_icon", "invalid_color", "invalid_group": String(localized: "Symbol, Farbe oder Gruppe ist ungültig.")
            case "category_limit_reached": String(localized: "Mehr eigene Kategorien erlaubt dein Tarif nicht.")
            case "category_in_use":
                String(localized: "Die Kategorie wird noch verwendet. Wähle eine Kategorie, in die die Ausgaben verschoben werden.")
            case "invalid_moveTo": String(localized: "In diese Kategorie lassen sich die Ausgaben nicht verschieben.")
            case "category_not_found": String(localized: "Die Kategorie gibt es nicht mehr.")
            case "cannot_invite_self": String(localized: "Du kannst dich nicht selbst einladen.")
            case "already_member": String(localized: "Dieses Konto hat bereits Zugriff auf das Fahrzeug.")
            case "member_limit_reached": String(localized: "Mehr Mitglieder sind für ein Fahrzeug nicht möglich.")
            case "too_many_invitations": String(localized: "Du hast heute schon sehr viele Einladungen verschickt. Bitte versuche es morgen wieder.")
            case "invitation_not_found": String(localized: "Die Einladung gibt es nicht mehr.")
            case "invitation_expired": String(localized: "Die Einladung ist abgelaufen.")
            case "member_not_found": String(localized: "Dieses Mitglied hat keinen Zugriff mehr.")
            case "owner_cannot_leave": String(localized: "Als Besitzer kannst du das Fahrzeug nicht verlassen.")
            case "invalid_role": String(localized: "Die Rolle ist ungültig.")
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
        switch feature {
        case "sharing": return String(localized: "Fahrzeuge teilen ist in deinem Tarif nicht enthalten.")
        case "tripExport": return String(localized: "Der Export des Fahrtenbuchs ist in deinem Tarif nicht enthalten.")
        case "tripCategories": return String(localized: "Diesen Zweck gibt es in deinem Tarif nicht.")
        case "premiumCategories": return String(localized: "Diese Kategorie ist in deinem Tarif nicht enthalten.")
        case "customCategories": return String(localized: "Eigene Kategorien sind in deinem Tarif nicht enthalten.")
        default: return String(localized: "Diese Funktion ist in deinem Tarif nicht enthalten.")
        }
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

    /// All vehicles of the account (owned first), fetched page by page.
    func vehicles(token: String) async throws -> [RemoteVehicle] {
        try await allPages("vehicles", token: token)
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

    /// The latest fill-ups, newest first (at most `Page.maxPerPage`).
    func fillups(vehicleID: String, limit: Int, token: String) async throws -> [RemoteFillup] {
        try await fillups(vehicleID: vehicleID, page: 1, perPage: limit, token: token).data
    }

    /// One page of fill-ups, newest first. `page` starts at 1.
    func fillups(vehicleID: String, page: Int, perPage: Int, token: String) async throws -> Page<RemoteFillup> {
        try await send("vehicles/\(vehicleID)/fillups", query: pageQuery(page: page, perPage: perPage), token: token)
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

    func updateFillup(id: String, _ patch: FillupPatch, token: String) async throws -> SavedEntry {
        try await send("fillups/\(id)", method: "PATCH", body: patch, token: token)
    }

    /// Adds the odometer reading to a fill-up; the API allows this at any time.
    func setFillupOdometer(id: String, km: Int, token: String) async throws -> SavedEntry {
        try await send("fillups/\(id)", method: "PATCH", body: OdometerPatch(odometerKm: km), token: token)
    }

    // MARK: - Entry list

    /// One page of the entry list: fill-ups, charging sessions, expenses, odometer notes and trips, newest first.
    func timeline(vehicleID: String, page: Int, perPage: Int, kinds: [TimelineItem.Kind], search: String?,
                  token: String) async throws -> TimelinePage {
        var query = pageQuery(page: page, perPage: perPage)
        if !kinds.isEmpty {
            query.append(URLQueryItem(name: "type", value: kinds.map(\.rawValue).joined(separator: ",")))
        }
        if let search, !search.isEmpty { query.append(URLQueryItem(name: "q", value: search)) }
        return try await send("vehicles/\(vehicleID)/timeline", query: query, token: token)
    }

    // MARK: - Expenses and categories

    func categories(token: String) async throws -> CategoriesResponse {
        try await send("categories", token: token)
    }

    func createCategory(_ input: CategoryInput, token: String) async throws {
        let _: EmptyResponse = try await send("categories", method: "POST", body: input, token: token)
    }

    func updateCategory(id: String, _ input: CategoryInput, token: String) async throws {
        let _: EmptyResponse = try await send("categories/\(id)", method: "PATCH", body: input, token: token)
    }

    /// Deletes an own category. Expenses that use it are moved to `moveTo`; without it the API refuses.
    func deleteCategory(id: String, moveTo: String?, token: String) async throws {
        let query = moveTo.map { [URLQueryItem(name: "moveTo", value: $0)] } ?? []
        let _: EmptyResponse = try await send("categories/\(id)", method: "DELETE", query: query, token: token)
    }

    func expense(id: String, token: String) async throws -> RemoteExpense {
        try await send("entries/\(id)", token: token)
    }

    func createExpense(_ input: ExpenseInput, token: String) async throws -> SavedEntry {
        var input = input
        input.sendsNulls = false
        return try await send("entries", method: "POST", body: input, token: token)
    }

    func updateExpense(id: String, _ input: ExpenseInput, token: String) async throws -> SavedEntry {
        var input = input
        input.sendsNulls = true
        return try await send("entries/\(id)", method: "PATCH", body: input, token: token)
    }

    func deleteExpense(id: String, token: String) async throws {
        let _: EmptyResponse = try await send("entries/\(id)", method: "DELETE", token: token)
    }

    // MARK: - Trips

    func trips(vehicleID: String, year: Int?, purpose: String?, page: Int, perPage: Int, token: String) async throws
        -> TripsPage {
        var query = pageQuery(page: page, perPage: perPage)
        if let year { query.append(URLQueryItem(name: "year", value: String(year))) }
        if let purpose { query.append(URLQueryItem(name: "purpose", value: purpose)) }
        return try await send("vehicles/\(vehicleID)/trips", query: query, token: token)
    }

    func tripSummary(vehicleID: String, year: Int?, token: String) async throws -> TripSummary {
        try await send("vehicles/\(vehicleID)/trips/summary", query: yearQuery(year), token: token)
    }

    /// The trip log as a CSV file, as the API writes it.
    func tripsCSV(vehicleID: String, year: Int?, token: String) async throws -> Data {
        var request = makeRequest("vehicles/\(vehicleID)/trips/export", method: "GET", query: yearQuery(year),
                                  token: token)
        request.setValue("text/csv", forHTTPHeaderField: "Accept")
        return try await data(for: request, token: token)
    }

    func trip(id: String, token: String) async throws -> RemoteTrip {
        try await send("trips/\(id)", token: token)
    }

    func createTrip(_ input: TripInput, token: String) async throws -> SavedEntry {
        var input = input
        input.sendsNulls = false
        return try await send("trips", method: "POST", body: input, token: token)
    }

    func updateTrip(id: String, _ input: TripInput, token: String) async throws -> SavedEntry {
        var input = input
        input.sendsNulls = true
        return try await send("trips/\(id)", method: "PATCH", body: input, token: token)
    }

    func deleteTrip(id: String, token: String) async throws {
        let _: EmptyResponse = try await send("trips/\(id)", method: "DELETE", token: token)
    }

    private func yearQuery(_ year: Int?) -> [URLQueryItem] {
        year.map { [URLQueryItem(name: "year", value: String($0))] } ?? []
    }

    // MARK: - Sharing

    func members(vehicleID: String, token: String) async throws -> VehicleMembers {
        try await send("vehicles/\(vehicleID)/members", token: token)
    }

    func invite(vehicleID: String, email: String, role: String, token: String) async throws {
        let _: EmptyResponse = try await send("vehicles/\(vehicleID)/invitations", method: "POST",
                                              body: MemberRoleInput(email: email, role: role), token: token)
    }

    func revokeInvitation(vehicleID: String, invitationID: String, token: String) async throws {
        let _: EmptyResponse = try await send("vehicles/\(vehicleID)/invitations/\(invitationID)", method: "DELETE",
                                              token: token)
    }

    func setMemberRole(vehicleID: String, userID: String, role: String, token: String) async throws {
        let _: EmptyResponse = try await send("vehicles/\(vehicleID)/members/\(userID)", method: "PATCH",
                                              body: MemberRoleInput(email: nil, role: role), token: token)
    }

    /// Removes a member; `me` leaves a vehicle that was shared with the user.
    func removeMember(vehicleID: String, userID: String, token: String) async throws {
        let _: EmptyResponse = try await send("vehicles/\(vehicleID)/members/\(userID)", method: "DELETE",
                                              token: token)
    }

    /// Open invitations to vehicles of other accounts.
    func invitations(token: String) async throws -> [PendingInvitation] {
        try await allPages("invitations", token: token)
    }

    func answerInvitation(id: String, accept: Bool, token: String) async throws {
        let _: EmptyResponse = try await send("invitations/\(id)/\(accept ? "accept" : "decline")", method: "POST",
                                              token: token)
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

    // MARK: - Pagination

    private func pageQuery(page: Int, perPage: Int) -> [URLQueryItem] {
        [
            URLQueryItem(name: "page", value: String(max(page, 1))),
            URLQueryItem(name: "per_page", value: String(min(max(perPage, 1), Page<RemoteFillup>.maxPerPage))),
        ]
    }

    /// Loads every page of a list endpoint (FuelStat/fuelstat#160).
    private func allPages<Item: Decodable>(_ path: String, token: String) async throws -> [Item] {
        var items: [Item] = []
        var page = 1
        while true {
            let result: Page<Item> = try await send(
                path, query: pageQuery(page: page, perPage: Page<Item>.maxPerPage), token: token
            )
            items += result.data
            // Stop on an empty page as well, so a misbehaving server cannot cause an endless loop.
            guard result.pagination.hasMore, !result.data.isEmpty else { return items }
            page += 1
        }
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
        let data = try await data(for: request, token: token)
        if Response.self == EmptyResponse.self { return EmptyResponse() as! Response }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }

    /// Sends the request and returns the body of a successful answer; errors become `APIError`.
    private func data(for request: URLRequest, token: String?) async throws -> Data {
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
        return data
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

    /// The app reads UserDefaults; widgets cannot, so they read the copy in the shared Keychain group.
    static var baseURL: URL {
        (UserDefaults.standard.string(forKey: key) ?? KeychainStore.loadServer()).flatMap(URL.init(string:))
            ?? APIClient.defaultBaseURL
    }

    static var isCustom: Bool { baseURL != APIClient.defaultBaseURL }

    static func save(_ url: URL) {
        if url == APIClient.defaultBaseURL {
            UserDefaults.standard.removeObject(forKey: key)
            KeychainStore.saveServer(nil)
        } else {
            UserDefaults.standard.set(url.absoluteString, forKey: key)
            KeychainStore.saveServer(url.absoluteString)
        }
    }

    /// Copies a custom server chosen before the widgets existed into the Keychain.
    static func shareWithWidgets() {
        if let address = UserDefaults.standard.string(forKey: key), KeychainStore.loadServer() == nil {
            KeychainStore.saveServer(address)
        }
    }

    static func displayName(of url: URL) -> String { ServerAddress.displayName(of: url) }
}

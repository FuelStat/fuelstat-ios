import FuelstatCore
import Foundation

// CSV import: `POST /vehicles/:id/import` (FuelStat/fuelstat#38). The API saves each request as one transaction,
// skips duplicates and warns about implausible odometer readings; the app shows what it answers.

/// A row the API rejected (400 `invalid_rows`): nothing of that request was imported.
struct ImportRowIssue: Decodable, Equatable {
    /// `fillup` or `entry`
    let type: String
    /// Position in `fillups` or `entries` of that request.
    let index: Int
    /// Error code of the row, e.g. `invalid_odometerKm`.
    let error: String

    enum CodingKeys: String, CodingKey { case type, index, error }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = c.text(.type) ?? ""
        index = c.number(.index).map { Int($0) } ?? 0
        error = c.text(.error) ?? ""
    }
}

struct InvalidRowsResponse: Decodable {
    let rows: [ImportRowIssue]
}

/// Request body; the key `dryRun` is only sent for the check.
struct ImportRequest: Encodable {
    let fillups: [ImportFillup]
    let entries: [ImportEntry]
    var dryRun: Bool?

    enum CodingKeys: String, CodingKey { case fillups, entries, dryRun }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fillups, forKey: .fillups)
        try c.encode(entries, forKey: .entries)
        try c.encodeIfPresent(dryRun, forKey: .dryRun)
    }
}

/// Answer of the import (201) or of the dry run (200).
struct ImportResponse: Decodable {
    struct Count: Decodable {
        let fillups: Int
        let entries: Int

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            fillups = c.number(.fillups).map { Int($0) } ?? 0
            entries = c.number(.entries).map { Int($0) } ?? 0
        }

        init(fillups: Int = 0, entries: Int = 0) {
            self.fillups = fillups
            self.entries = entries
        }

        enum CodingKeys: String, CodingKey { case fillups, entries }
    }

    /// A row of the request by position: a skipped duplicate or an implausible odometer reading.
    struct Hint: Decodable {
        let index: Int
        let message: String?

        enum CodingKeys: String, CodingKey { case index, message }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            index = c.number(.index).map { Int($0) } ?? 0
            message = c.text(.message)
        }
    }

    let imported: Count
    let skipped: Count
    let duplicates: [Hint]
    let warnings: [Hint]

    enum CodingKeys: String, CodingKey { case imported, skipped, duplicates, warnings }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        imported = (try? c.decodeIfPresent(Count.self, forKey: .imported)) ?? Count()
        skipped = (try? c.decodeIfPresent(Count.self, forKey: .skipped)) ?? Count()
        duplicates = (try? c.decodeIfPresent([Hint].self, forKey: .duplicates)) ?? []
        warnings = (try? c.decodeIfPresent([Hint].self, forKey: .warnings)) ?? []
    }
}

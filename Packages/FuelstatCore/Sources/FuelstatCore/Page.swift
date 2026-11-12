import Foundation

/// One page of a list from the API (FuelStat/fuelstat#160): `{ "data": [...], "pagination": {...} }`.
///
/// Servers before that change sent a bare array; it is read as a single, complete page so a
/// self-hosted server that has not been updated yet keeps working.
public struct Page<Item: Decodable>: Decodable {
    public struct Pagination: Decodable, Equatable, Sendable {
        public let currentPage: Int
        public let perPage: Int
        public let total: Int
        public let totalPages: Int
        public let hasMore: Bool

        public init(currentPage: Int, perPage: Int, total: Int, totalPages: Int, hasMore: Bool) {
            self.currentPage = currentPage
            self.perPage = perPage
            self.total = total
            self.totalPages = totalPages
            self.hasMore = hasMore
        }

        enum CodingKeys: String, CodingKey {
            case currentPage = "current_page"
            case perPage = "per_page"
            case total
            case totalPages = "total_pages"
            case hasMore = "has_more"
        }
    }

    public let data: [Item]
    public let pagination: Pagination

    public init(data: [Item], pagination: Pagination) {
        self.data = data
        self.pagination = pagination
    }

    enum CodingKeys: String, CodingKey { case data, pagination }

    public init(from decoder: Decoder) throws {
        if let list = try? [Item](from: decoder) {
            data = list
            pagination = Pagination(currentPage: 1, perPage: list.count, total: list.count,
                                    totalPages: 1, hasMore: false)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        data = try c.decode([Item].self, forKey: .data)
        pagination = try c.decode(Pagination.self, forKey: .pagination)
    }

    /// Largest page size the API accepts; larger requests are capped by the server.
    public static var maxPerPage: Int { 100 }
}

extension Page: Sendable where Item: Sendable {}

import Foundation
import Testing
@testable import FuelstatCore

struct PageTests {
    private struct Item: Decodable, Equatable { let id: Int }

    @Test func decodesEnvelope() throws {
        let json = Data("""
        {"data":[{"id":1},{"id":2}],
         "pagination":{"current_page":2,"per_page":2,"total":5,"total_pages":3,"has_more":true}}
        """.utf8)
        let page = try JSONDecoder().decode(Page<Item>.self, from: json)
        #expect(page.data == [Item(id: 1), Item(id: 2)])
        #expect(page.pagination == .init(currentPage: 2, perPage: 2, total: 5, totalPages: 3, hasMore: true))
    }

    @Test func lastPageHasNoMore() throws {
        let json = Data("""
        {"data":[],"pagination":{"current_page":4,"per_page":2,"total":5,"total_pages":3,"has_more":false}}
        """.utf8)
        let page = try JSONDecoder().decode(Page<Item>.self, from: json)
        #expect(page.data.isEmpty)
        #expect(!page.pagination.hasMore)
        #expect(page.pagination.total == 5)
    }

    @Test func bareArrayFromOlderServerIsOneCompletePage() throws {
        let page = try JSONDecoder().decode(Page<Item>.self, from: Data(#"[{"id":7}]"#.utf8))
        #expect(page.data == [Item(id: 7)])
        #expect(!page.pagination.hasMore)
        #expect(page.pagination.total == 1)
    }

    @Test func missingPaginationIsAnError() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Page<Item>.self, from: Data(#"{"data":[]}"#.utf8))
        }
    }
}

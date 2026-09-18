import Testing
import Foundation
@testable import OpenBoard

@Suite("Top 100 lists")
struct TopListTests {
    @Test func keepsUSOverTheBoardListsOnly() throws {
        let page = try JSONDecoder().decode(APIPage<APITopListDefinition>.self, from: try fixture("sample_top_lists"))
        let ids = Set(USCFMapper.topListDefinitions(page.items).map(\.id))
        #expect(ids == ["QuickUnder13", "Regular50Plus", "Regular8", "RegularOverall", "WomensRegular", "WomensRegular8"])
    }

    @Test func labelsAndOrdering() throws {
        let page = try JSONDecoder().decode(APIPage<APITopListDefinition>.self, from: try fixture("sample_top_lists"))
        let defs = Dictionary(uniqueKeysWithValues: USCFMapper.topListDefinitions(page.items).map { ($0.id, $0) })
        #expect(defs["Regular8"]?.badgeLabel == "Age 8")
        #expect(defs["WomensRegular8"]?.badgeLabel == "Girls Age 8")
        #expect(defs["WomensRegular8"]?.ageGroup == "Age 8")
        #expect(defs["RegularOverall"]?.badgeLabel == "US Top 100")
        #expect(defs["WomensRegular"]?.badgeLabel == "Top Women")
        #expect(defs["QuickUnder13"]?.ageGroup == "Under Age 13")
        let order = ["Regular8", "RegularOverall", "Regular50Plus"].compactMap { defs[$0]?.sortKey }
        #expect(order == order.sorted())
    }

    @Test func mapsListEntries() throws {
        let api = try JSONDecoder().decode(APITopList.self, from: try fixture("sample_top_list_regular8"))
        let definition = TopListDefinition(id: "Regular8", name: "Age 8", rating: .regular,
                                           minAge: 8, maxAge: 8, isWomen: false)
        let list = USCFMapper.topList(api, definition: definition)
        #expect(list.entries.count == 5)
        #expect(list.entries.first?.rank == 1)
        #expect(list.entries.first?.id == "31502851")
        #expect(list.reportDate != nil)
    }

    @Test @MainActor func indexFindsEveryListAPlayerIsOn() async throws {
        let container = try TestContainer.inMemory()
        let service = CachedRatingsService(upstream: MockRatingsService(), container: container)
        let index = TopListsIndex()
        await index.load(from: service)

        // Ava is #48 on Age 8 and #12 on Girls Age 8: best (lowest) rank first.
        let ava = index.ranks(for: "90000010")
        #expect(ava.map(\.rank) == [12, 48])
        #expect(index.best(for: "90000010")?.definition.badgeLabel == "Girls Age 8")
        #expect(index.best(for: "not-on-any-list") == nil)
        // Quick/Blitz lists are browse-only, never badges.
        #expect(index.ranks(for: MockRatingsService.samplePlayerID).allSatisfy { $0.definition.rating == .regular })
    }

    @Test func pagingCollectsEveryPage() async throws {
        // 250 items served 100 at a time: pages at offsets 0, 100, 200, then stop.
        let items = try await LiveRatingsService.collectPages(pageSize: 100) { offset, size in
            let count = max(0, min(size, 250 - offset))
            return APIPage(items: Array(offset..<(offset + count)), hasNextPage: offset + count < 250,
                           offset: offset, pageSize: size)
        }
        #expect(items == Array(0..<250))
    }
}

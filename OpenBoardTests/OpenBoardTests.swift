import Testing
import Foundation
@testable import OpenBoard

// MARK: - Fixtures

private func fixture(_ name: String) throws -> Data {
    let bundle = Bundle(for: BundleToken.self)
    guard let url = bundle.url(forResource: name, withExtension: "json") else {
        throw NSError(domain: "fixture", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "missing fixture \(name)"])
    }
    return try Data(contentsOf: url)
}

private final class BundleToken {}

private func fixtureText(_ name: String, _ ext: String) throws -> String {
    let bundle = Bundle(for: BundleToken.self)
    guard let url = bundle.url(forResource: name, withExtension: ext) else {
        throw NSError(domain: "fixture", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "missing fixture \(name).\(ext)"])
    }
    return try String(contentsOf: url, encoding: .utf8)
}

// MARK: - Decoding real API payloads

@Suite("USCF API decoding")
struct DecodingTests {
    @Test func decodesMemberProfile() throws {
        let member = try JSONDecoder().decode(APIMember.self, from: fixture("sample_member"))
        #expect(member.id == "90000001")
        #expect(member.firstName == "ALEX")
        #expect(member.rank == 58_224)
        #expect(member.stateRank == 2_204)

        let ratings = USCFMapper.ratings(from: member.ratings)
        #expect(ratings.regular?.value == 383)
        #expect(ratings.regular?.floor == 131)
        #expect(ratings.regular?.games == 5)
        #expect(ratings.quick?.value == 379)
        #expect(ratings.blitz?.value == nil)
    }

    @Test func decodesMemberSectionsIntoEventResults() throws {
        let page = try JSONDecoder().decode(APIPage<APIMemberSection>.self,
                                            from: fixture("sample_member_sections"))
        let events = USCFMapper.eventResults(from: page.items)
        #expect(!events.isEmpty)

        let event = try #require(events.first { $0.id == "900000000001" })
        #expect(event.regular?.pre == 322)
        #expect(event.regular?.post == 420)
        #expect(event.quick?.pre == 319)
        #expect(event.quick?.post == 415)
        #expect(event.regular?.delta == 98)
    }

    @Test func decodesStandingsWithRounds() throws {
        let page = try JSONDecoder().decode(APIPage<APIStanding>.self,
                                            from: fixture("sample_standings"))
        #expect(!page.items.isEmpty)
        let standings = page.items.map { USCFMapper.standing($0, roundCount: 4) }
        let first = try #require(standings.first)
        #expect(first.rank == 1)
        #expect(first.points == "4.0")
        #expect(first.rounds.count == 4)
        #expect(first.rounds.allSatisfy { ["W", "L", "D", "B", "–"].contains($0.symbol) })
    }

    @Test func decodesSearchResults() throws {
        let page = try JSONDecoder().decode(APIPage<APIMember>.self,
                                            from: fixture("sample_search"))
        let summaries = page.items.map(USCFMapper.summary)
        #expect(!summaries.isEmpty)
        // USCF stores names in ALL CAPS; mapper should title-case them.
        #expect(summaries.allSatisfy { $0.name != $0.name.uppercased() || $0.name.count <= 2 })
    }

    @Test func computesPercentilesFromMaxRanks() throws {
        let ranks = try JSONDecoder().decode([APIMaxRank].self, from: fixture("sample_max-ranks"))
        let member = try JSONDecoder().decode(APIMember.self, from: fixture("sample_member"))
        let player = USCFMapper.player(member: member, sections: [], maxRanks: ranks)

        let overall = try #require(player.ranking?.overall)
        #expect(overall.total == 76_379)
        #expect(overall.computedPercentile == 24)

        let state = try #require(player.ranking?.state)
        #expect(state.total == 2_711)
        #expect(state.computedPercentile == 19)
    }
}

// MARK: - Class titles

@Suite("USCF class titles")
struct ClassTitleTests {
    @Test(arguments: [
        (2500, ClassTitle.seniorMaster),
        (2400, .seniorMaster),
        (2399, .nationalMaster),
        (2200, .nationalMaster),
        (2000, .expert),
        (1800, .classA),
        (1600, .classB),
        (1400, .classC),
        (1200, .classD),
        (1000, .classE),
        (800, .classF),
        (600, .classG),
        (400, .classH),
        (383, .classI),
        (200, .classI),
        (199, .classJ),
        (0, .classJ),
    ])
    func titleForRating(rating: Int, expected: ClassTitle) {
        #expect(ClassTitle(rating: rating) == expected)
    }
}

// MARK: - Delta math & formatting

@Suite("Delta math")
struct DeltaTests {
    @Test func positiveDelta() {
        #expect(PrePost(pre: 322, post: 420, games: 12).delta == 98)
    }

    @Test func negativeDelta() {
        #expect(PrePost(pre: 374, post: 313, games: 20).delta == -61)
    }

    @Test func missingSideYieldsNil() {
        #expect(PrePost(pre: nil, post: 823, games: 4).delta == nil)
        #expect(PrePost(pre: 322, post: nil, games: nil).delta == nil)
    }

    @Test func clockDigitsZeroPad() {
        #expect(383.clockDigits == "0383")
        #expect(1500.clockDigits == "1500")
        #expect(7.clockDigits == "0007")
    }

    @Test func historySeriesIsChronological() {
        let events = USCFMapper.eventResults(from: [])
        #expect(USCFMapper.history(from: events).isEmpty)

        let player = MockRatingsService.samplePlayer
        #expect(player.ratingHistory.last == 420)
        #expect(player.peakRegular == 420)
    }
}

// MARK: - Cache TTL

@Suite("Cache TTL")
struct CacheTests {
    @MainActor
    private func makeStore() throws -> CacheStore {
        let schema = Schema([WatchedPlayer.self, CachedPayload.self, RecentSearch.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return CacheStore(modelContainer: container)
    }

    @Test @MainActor func freshWithinTTL() async throws {
        let store = try makeStore()
        await store.write(MockRatingsService.samplePlayer, key: "player-x")
        let entry = try #require(await store.read(Player.self, key: "player-x"))
        #expect(entry.isFresh)
        #expect(entry.value.id == MockRatingsService.samplePlayerID)
    }

    @Test @MainActor func staleBeyondTTL() async throws {
        let store = try makeStore()
        await store.write(MockRatingsService.samplePlayer, key: "player-y")
        // A zero TTL makes any stored entry stale immediately.
        let entry = try #require(await store.read(Player.self, key: "player-y", ttl: 0))
        #expect(!entry.isFresh)
    }

    @Test @MainActor func missingKeyReturnsNil() async throws {
        let store = try makeStore()
        let entry = await store.read(Player.self, key: "never-written")
        #expect(entry == nil)
    }

    @Test @MainActor func staleServedWhenUpstreamFails() async throws {
        struct FailingService: RatingsProviding {
            func player(id: String) async throws -> Player { throw RatingsError.offline(underlying: "test") }
            func search(_ query: String) async throws -> [PlayerSummary] { [] }
            func event(id: String) async throws -> ChessEvent { throw RatingsError.offline(underlying: "test") }
            func topListDefinitions() async throws -> [TopListDefinition] { [] }
            func topList(_ definition: TopListDefinition) async throws -> TopList {
                throw RatingsError.offline(underlying: "test")
            }
        }
        let schema = Schema([WatchedPlayer.self, CachedPayload.self, RecentSearch.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let service = CachedRatingsService(upstream: FailingService(), container: container)

        // Seed the cache, then verify the failing upstream still yields the copy.
        let id = MockRatingsService.samplePlayerID
        await service.cache.write(MockRatingsService.samplePlayer, key: "player-\(id)")
        let player = try await service.player(id: id)
        #expect(player.id == id)
        #expect(player.ratings.regular?.value == 383)
    }
}

import SwiftData

// MARK: - Per-round rating estimates

@Suite("Round rating estimates")
struct RoundEstimateTests {
    /// The Sep 13 2026 quad (section 8): Tristan 3/3, +110 Regular.
    private let quad = EventSection(name: "Section 8", players: [
        Standing(id: "T", rank: 1, name: "Tristan Larosa", points: "3.0",
                 regular: PrePost(pre: 517, post: 627),
                 rounds: [RoundOutcome(round: 1, symbol: "W", opponentRank: 4),
                          RoundOutcome(round: 2, symbol: "W", opponentRank: 3),
                          RoundOutcome(round: 3, symbol: "W", opponentRank: 2)]),
        Standing(id: "L", rank: 2, name: "Lily Le", points: "2.0",
                 regular: PrePost(pre: 530, post: 564),
                 rounds: [RoundOutcome(round: 1, symbol: "W", opponentRank: 3),
                          RoundOutcome(round: 2, symbol: "W", opponentRank: 4),
                          RoundOutcome(round: 3, symbol: "L", opponentRank: 1)]),
        Standing(id: "M", rank: 3, name: "Mikaela Pavlov", points: "1.0",
                 regular: PrePost(pre: 420, post: 422),
                 rounds: [RoundOutcome(round: 1, symbol: "L", opponentRank: 2),
                          RoundOutcome(round: 2, symbol: "L", opponentRank: 1),
                          RoundOutcome(round: 3, symbol: "W", opponentRank: 4)]),
        Standing(id: "A", rank: 4, name: "Aditya Venkatesh", points: "0.0",
                 regular: PrePost(pre: 589, post: 478),
                 rounds: [RoundOutcome(round: 1, symbol: "L", opponentRank: 1),
                          RoundOutcome(round: 2, symbol: "L", opponentRank: 2),
                          RoundOutcome(round: 3, symbol: "L", opponentRank: 3)]),
    ])

    @Test func roundsAddUpToOfficialChange() {
        let estimates = RoundRatingEstimator.estimate(quad)
        #expect(estimates.system == .regular)
        for player in quad.players {
            let rounds = estimates.byMember[player.id] ?? [:]
            #expect(rounds.count == 3)
            #expect(rounds.values.reduce(0, +) == player.regular?.delta)
        }
    }

    @Test func winsGainAndLossesLose() {
        let estimates = RoundRatingEstimator.estimate(quad)
        #expect(estimates.byMember["T"]!.values.allSatisfy { $0 > 0 })
        #expect(estimates.byMember["A"]!.values.allSatisfy { $0 < 0 })
    }

    @Test func upsetLossCostsMoreThanExpectedLoss() {
        // Lily (530) lost to lower-rated Tristan (517); Mikaela (420) lost to higher-rated Tristan.
        let estimates = RoundRatingEstimator.estimate(quad)
        let lily = estimates.change(for: "L", round: 3)!
        let mikaela = estimates.change(for: "M", round: 2)!
        #expect(lily < mikaela)
    }

    @Test func byesAndNewPlayersAreSkipped() {
        let section = EventSection(name: "S", players: [
            Standing(id: "N", rank: 1, name: "New Player", points: "1.5",
                     regular: PrePost(pre: nil, post: 800),
                     rounds: [RoundOutcome(round: 1, symbol: "W", opponentRank: 2)]),
            Standing(id: "E", rank: 2, name: "Established", points: "0.5",
                     regular: PrePost(pre: 900, post: 880),
                     rounds: [RoundOutcome(round: 1, symbol: "L", opponentRank: 1),
                              RoundOutcome(round: 2, symbol: "B")]),
        ])
        let estimates = RoundRatingEstimator.estimate(section)
        #expect(estimates.byMember["N"] == nil)            // no pre-rating, no event change
        #expect(estimates.change(for: "E", round: 1) == -20) // only rated game carries it all
        #expect(estimates.change(for: "E", round: 2) == nil) // bye
    }

    @Test func bonusDrivenChangeStillSumsExactly() {
        // Net-negative surprise but a positive event change (bonus points).
        let raw = RoundRatingEstimator.split(delta: 40, surprises: [0.3, -0.5, 0.1])
        let rounded = RoundRatingEstimator.roundPreservingSum(raw, total: 40)
        #expect(rounded.reduce(0, +) == 40)
    }
}

// MARK: - Upcoming tournaments (US Chess website pages saved 2026-09-18)

@Suite("Upcoming tournaments parsing")
struct UpcomingTournamentTests {
    private func ymd(_ date: Date?) -> String? {
        date.map { Calendar.current.dateComponents([.year, .month, .day], from: $0) }
            .map { String(format: "%04d-%02d-%02d", $0.year!, $0.month!, $0.day!) }
    }

    @Test func parsesSearchResults() throws {
        let listings = TournamentParser.listings(from: try fixtureText("upcoming_search", "html"))
        #expect(listings.count == 3)

        let dca = try #require(listings.first { $0.id.hasPrefix("/dca-somerset") })
        #expect(dca.name == "DCA Somerset County Scholastic (K-8 Grades) September 20th, 2026")
        #expect(dca.location == "Somerville, New Jersey")
        #expect(dca.organizer == "Dash Chess Academy")
        #expect(ymd(dca.startDate) == "2026-09-20")
        #expect(!dca.isRecurring)
        #expect(TournamentKind.scholastic.matches(dca))

        let weekly = try #require(listings.first { $0.id.contains("weekly-uscf") })
        #expect(weekly.isRecurring)
        #expect(ymd(weekly.endDate) == "2050-12-31")
    }

    @Test func readsLastPageFromPager() throws {
        #expect(TournamentParser.lastPageIndex(in: try fixtureText("upcoming_search", "html")) == 3)
        #expect(TournamentParser.lastPageIndex(in: "<div>no pager</div>") == 0)
    }

    @Test func sortsDatedFirstAndDropsEndedAndDuplicates() {
        func listing(_ id: String, start: Int, end: Int? = nil, recurring: Bool = false) -> TournamentListing {
            TournamentListing(id: id, name: id, location: "", organizer: "", summary: "", banner: "",
                              startDate: MockTournamentsService.date(start),
                              endDate: MockTournamentsService.date(end ?? start), isRecurring: recurring)
        }
        let sorted = TournamentParser.dedupedAndSorted([
            listing("weekly", start: -300, end: 3000, recurring: true),
            listing("later", start: 10),
            listing("ended", start: -5),
            listing("soon", start: 1),
            listing("soon", start: 1),
        ])
        #expect(sorted.map(\.id) == ["soon", "later", "weekly"])
    }

    @Test func parsesAnnouncementJSON() throws {
        let detail = try TournamentParser.detail(id: "/dca", json: try fixture("tla_node"))
        #expect(detail.venueName == "Knights of Columbus, Somerville")
        #expect(detail.addressLine == "495 E Main St, Somerville, NJ 08876")
        #expect(detail.latitude == 40.564642)
        #expect(detail.organizerName == "Dash Chess Academy")
        #expect(detail.registrationURL?.host() == "forms.gle") // the organizer's Google Form
        #expect(detail.announcement.contains("Tournament Format: Swiss"))
        #expect(detail.announcement.contains("• "))
        #expect(!detail.announcement.contains("<"))
    }

    @Test func parsesPlanAheadCalendar() throws {
        let events = TournamentParser.majorEvents(from: try fixtureText("plan_ahead", "html"))
        let masters = try #require(events.first { $0.name.hasPrefix("US Masters") })
        #expect(masters.year == 2026)
        #expect(masters.dates == "November 25-29")
        #expect(masters.city == "Charlotte")
        #expect(masters.state == "NC")
        #expect(masters.searchName == "US Masters")
        #expect(ymd(masters.startDate) == "2026-11-25")

        let worldOpen = try #require(events.first { $0.name == "World Open" })
        #expect(worldOpen.year == 2027)
        #expect(ymd(worldOpen.startDate) == "2027-06-30") // "June 30-July 4"
        #expect(events.contains { $0.isNationalChampionship && $0.state == "PA" })
    }

    @Test func weekendWindowEndsOnSunday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let friday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))!
        let range = UpcomingWindow.weekend.range(from: friday, calendar: calendar)!
        #expect(calendar.component(.weekday, from: range.upperBound) == 1) // Sunday
        #expect(calendar.dateComponents([.day], from: range.lowerBound, to: range.upperBound).day == 2)
    }
}

// MARK: - Top 100 lists

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
        let schema = Schema([WatchedPlayer.self, CachedPayload.self, RecentSearch.self])
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
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

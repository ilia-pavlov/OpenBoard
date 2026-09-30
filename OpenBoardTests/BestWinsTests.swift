import Testing
import Foundation
@testable import OpenBoard

@Suite("Best wins")
struct BestWinsTests {
    @Test func keepsOnlyRegularAndDualWins() throws {
        let page = try JSONDecoder().decode(APIPage<APIMemberGame>.self, from: fixture("sample_member_games"))
        let wins = page.items.compactMap(USCFMapper.regularWin)
        #expect(wins.map(\.opponentID) == ["90000005", "90000020"]) // quick, online, loss, draw dropped
        #expect(wins[0].opponentName == "Owen Price")
        #expect(wins[0].eventName == "Sample Scholastic Open 2026")
        #expect(wins[1].sectionKey == SectionKey(eventID: "900000000002", section: 2))
    }

    @Test func ranksByOpponentRatingOnePerOpponent() {
        let a = SectionKey(eventID: "E1", section: 1)
        let b = SectionKey(eventID: "E2", section: 1)
        let wins = [
            win("ann", a, daysAgo: 100), win("bob", a, daysAgo: 100), win("cal", a, daysAgo: 100),
            win("ann", b, daysAgo: 10), win("dee", b, daysAgo: 10), win("eve", b, daysAgo: 10),
        ]
        let ratings: [SectionKey: [String: Int]] = [
            a: ["me": 900, "ann": 1200, "bob": 1100, "cal": 700],
            b: ["me": 1000, "ann": 1250, "dee": 1100], // eve unrated then: skipped
        ]
        let best = BestWins.rank(wins, playerID: "me", preRatings: ratings, limit: 3)
        #expect(best.map(\.opponentID) == ["ann", "dee", "bob"]) // tie at 1100: newer win first
        #expect(best[0].opponentRating == 1250)                  // ann's higher of two ratings
        #expect(best[0].ratingGap == 250)
        #expect(best[0].eventID == "E2")
    }

    @Test func skipsSectionsThatFailedToLoad() {
        let wins = [win("ann", SectionKey(eventID: "E1", section: 1), daysAgo: 1)]
        #expect(BestWins.rank(wins, playerID: "me", preRatings: [:], limit: 3).isEmpty)
    }

    @Test func scansStrongestSectionsFirst() {
        let wins = [
            win("a", SectionKey(eventID: "OLD", section: 1), daysAgo: 300),
            win("b", SectionKey(eventID: "PEAK", section: 1), daysAgo: 100),
            win("c", SectionKey(eventID: "NEW", section: 2), daysAgo: 5),
            win("d", SectionKey(eventID: "UNKNOWN", section: 1), daysAgo: 1),
        ]
        let order = BestWins.scanOrder(wins, playerRatings: ["OLD": 400, "PEAK": 1500, "NEW": 1400])
        #expect(order.map(\.eventID) == ["PEAK", "NEW", "OLD", "UNKNOWN"])
    }

    @Test func stopsOnlyWhenNoBetterWinIsPlausible() {
        let best = [1900, 1850, 1800].map { rating in
            NotableWin(opponentID: "\(rating)",
                       opponentName: "",
                       opponentRating: rating,
                       playerRating: nil,
                       eventID: "E",
                       eventName: "",
                       section: 1,
                       date: nil)
        }
        #expect(BestWins.canStop(best: best, limit: 3, nextPlayerRating: 999))       // 999 + 800 < 1800
        #expect(!BestWins.canStop(best: best, limit: 3, nextPlayerRating: 1000))     // an 800-point upset could tie
        #expect(!BestWins.canStop(best: best, limit: 3, nextPlayerRating: nil))      // unknown: must check
        #expect(!BestWins.canStop(best: Array(best.prefix(2)), limit: 3, nextPlayerRating: 100)) // not full yet
    }

    @Test @MainActor func mockScanReportsProgressAndFinishes() async throws {
        let service = CachedRatingsService(upstream: MockRatingsService(), container: try TestContainer.inMemory())
        var steps: [BestWinsProgress] = []
        for try await step in service.bestWinsScan(memberID: MockRatingsService.samplePlayerID) {
            steps.append(step)
        }
        let last = try #require(steps.last)
        #expect(last.isFinished)
        #expect(last.gameCount == 5)
        #expect(last.eventsChecked == last.eventsTotal)
        #expect(!last.wins.isEmpty)
        #expect(last.wins.map(\.opponentRating) == last.wins.map(\.opponentRating).sorted(by: >))
        #expect(steps.first?.eventsChecked == 0) // progress shows before any section loads
    }

    @Test @MainActor func scanStopsOnceNoBetterWinIsPlausible() async throws {
        let upstream = ScriptedUpstream()
        let service = CachedRatingsService(upstream: upstream,
                                           container: try TestContainer.inMemory(),
                                           scanSpacing: .zero)
        let last = try await finalStep(of: service.bestWinsScan(memberID: ScriptedUpstream.playerID))

        #expect(last.isFinished)
        #expect(last.wins.map(\.opponentID) == ["A", "B", "C"])
        #expect(last.eventsTotal == 5)
        #expect(last.eventsChecked == 3)                 // S4 (player 600) can't beat 1500
        #expect(await upstream.standingsRequests == 3)
    }

    @Test @MainActor func rescanReusesCachedSections() async throws {
        let upstream = ScriptedUpstream()
        let service = CachedRatingsService(upstream: upstream,
                                           container: try TestContainer.inMemory(),
                                           scanSpacing: .zero)
        let first = try await finalStep(of: service.bestWinsScan(memberID: ScriptedUpstream.playerID))
        let second = try await finalStep(of: service.bestWinsScan(memberID: ScriptedUpstream.playerID))

        #expect(second.wins == first.wins)
        #expect(await upstream.standingsRequests == 3)   // nothing fetched the second time
    }

    /// A paused card shows what earlier scans found without any requests, and
    /// never reports the scan as finished.
    @Test @MainActor func cachedOnlyScanMakesNoRequests() async throws {
        let upstream = ScriptedUpstream()
        let service = CachedRatingsService(upstream: upstream,
                                           container: try TestContainer.inMemory(),
                                           scanSpacing: .zero)
        let full = try await finalStep(of: service.bestWinsScan(memberID: ScriptedUpstream.playerID))
        let saved = try await finalStep(of: service.bestWinsScan(memberID: ScriptedUpstream.playerID,
                                                                 cachedOnly: true))

        #expect(saved.wins == full.wins)
        #expect(!saved.isFinished)
        #expect(await upstream.standingsRequests == 3) // only the full scan's
    }

    @Test @MainActor func cachedOnlyScanWithNothingSavedIsEmpty() async throws {
        let service = CachedRatingsService(upstream: ScriptedUpstream(),
                                           container: try TestContainer.inMemory(),
                                           scanSpacing: .zero)
        var steps = 0
        for try await _ in service.bestWinsScan(memberID: ScriptedUpstream.playerID, cachedOnly: true) { steps += 1 }
        #expect(steps == 0)
    }

    private func finalStep(of scan: AsyncThrowingStream<BestWinsProgress, Error>) async throws -> BestWinsProgress {
        var last: BestWinsProgress?
        for try await step in scan { last = step }
        return try #require(last)
    }

    private func win(_ opponent: String, _ key: SectionKey, daysAgo: Int) -> RatedWin {
        RatedWin(opponentID: opponent,
                 opponentName: opponent.capitalized,
                 eventID: key.eventID,
                 eventName: "Event \(key.eventID)",
                 section: key.section,
                 date: Date.now.addingTimeInterval(-Double(daysAgo) * 86_400))
    }
}

/// Five sections, strongest first by the player's own rating (1500 → 500), one
/// win each; counts standings requests. After A, B and C the third-best win is
/// 1500, and S4's player (600) would need a 900-point upset to beat it.
private actor ScriptedUpstream: RatingsProviding {
    static let playerID = MockRatingsService.samplePlayerID

    private(set) var standingsRequests = 0

    private let sections: [(event: String, player: Int, opponent: String, rating: Int)] = [
        ("S1", 1500, "A", 1600),
        ("S2", 1400, "B", 1550),
        ("S3", 1300, "C", 1500),
        ("S4", 600, "D", 1300),
        ("S5", 500, "E", 1200),
    ]

    func player(id: String) async throws -> Player {
        var player = MockRatingsService.samplePlayer
        player.events = sections.map { section in
            EventResult(id: section.event,
                        name: section.event,
                        date: nil,
                        score: nil,
                        regular: PrePost(pre: section.player, post: nil, games: nil),
                        quick: nil)
        }
        return player
    }

    func regularWins(memberID: String) async throws -> RatedWins {
        RatedWins(gameCount: 10, wins: sections.map { section in
            RatedWin(opponentID: section.opponent,
                     opponentName: section.opponent,
                     eventID: section.event,
                     eventName: section.event,
                     section: 1,
                     date: nil)
        })
    }

    func regularPreRatings(eventID: String, section: Int) async throws -> [String: Int] {
        standingsRequests += 1
        guard let match = sections.first(where: { $0.event == eventID }) else { return [:] }
        return [Self.playerID: match.player, match.opponent: match.rating]
    }

    func search(_ query: String) async throws -> [PlayerSummary] { [] }
    func event(id: String) async throws -> ChessEvent { throw RatingsError.notFound }
    func topListDefinitions() async throws -> [TopListDefinition] { [] }
    func topList(_ definition: TopListDefinition) async throws -> TopList { throw RatingsError.notFound }
}

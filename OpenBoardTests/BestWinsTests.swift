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

    @Test @MainActor func mockServiceProducesBestWins() async throws {
        let service = CachedRatingsService(upstream: MockRatingsService(), container: try TestContainer.inMemory())
        let best = try await service.bestWins(memberID: MockRatingsService.samplePlayerID)
        #expect(!best.isEmpty)
        #expect(best.map(\.opponentRating) == best.map(\.opponentRating).sorted(by: >))
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

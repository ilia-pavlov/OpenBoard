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
            NotableWin(opponentID: "\(rating)", opponentName: "", opponentRating: rating, playerRating: nil,
                       eventID: "E", eventName: "", section: 1, date: nil)
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

    private func win(_ opponent: String, _ key: SectionKey, daysAgo: Int) -> RatedWin {
        RatedWin(opponentID: opponent,
                 opponentName: opponent.capitalized,
                 eventID: key.eventID,
                 eventName: "Event \(key.eventID)",
                 section: key.section,
                 date: Date.now.addingTimeInterval(-Double(daysAgo) * 86_400))
    }
}

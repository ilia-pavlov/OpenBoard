import Testing
import Foundation
@testable import OpenBoard

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

import Foundation

/// Estimates how much each rated game moved a player's rating.
///
/// US Chess only publishes a player's total change for the whole event, so
/// per-round numbers are an estimate: each game gets the Elo "surprise"
/// (actual score − expected score from pre-event ratings), and the official
/// event change is split across games in that proportion. Rounded values
/// always add up exactly to the official change.
enum RoundRatingEstimator {
    struct Estimates: Sendable, Hashable {
        /// Which rating the estimates are for (Regular unless the section is quick-only).
        var system: RatingSystem
        /// member ID → round number → estimated change.
        var byMember: [String: [Int: Int]]

        func change(for memberID: String, round: Int) -> Int? {
            byMember[memberID]?[round]
        }
    }

    /// Fallback K-factor when the event change can't be split proportionally
    /// (e.g. bonus points outweigh the games, or results cancel out).
    private static let fallbackK = 32.0
    /// Proportional splits steeper than this are treated as bonus-driven.
    private static let maxK = 400.0

    static func estimate(_ section: EventSection) -> Estimates {
        let system: RatingSystem = section.players.contains { $0.regular?.post != nil } ? .regular : .quick
        let byRank = Dictionary(section.players.map { ($0.rank, $0) }, uniquingKeysWith: { first, _ in first })

        func rating(_ standing: Standing) -> Int? {
            let result = system == .regular ? standing.regular : standing.quick
            return result?.pre ?? result?.post // new players: their first published rating
        }

        var byMember: [String: [Int: Int]] = [:]
        for player in section.players {
            let result = system == .regular ? player.regular : player.quick
            guard let delta = result?.delta, let own = rating(player) else { continue }

            // (round, actual − expected) for each rated game against a rated opponent.
            let games: [(round: Int, surprise: Double)] = player.rounds.compactMap { outcome in
                guard let score = score(outcome.symbol),
                      let opponent = outcome.opponentRank.flatMap({ byRank[$0] }),
                      let theirs = rating(opponent) else { return nil }
                let expected = 1 / (1 + pow(10, Double(theirs - own) / 400))
                return (outcome.round, score - expected)
            }
            guard !games.isEmpty else { continue }

            let raw = split(delta: delta, surprises: games.map(\.surprise))
            let rounded = roundPreservingSum(raw, total: delta)
            byMember[player.id] = Dictionary(uniqueKeysWithValues: zip(games.map(\.round), rounded))
        }
        return Estimates(system: system, byMember: byMember)
    }

    static func score(_ symbol: String) -> Double? {
        switch symbol {
        case "W": 1
        case "D": 0.5
        case "L": 0
        default: nil // byes, forfeits, unplayed
        }
    }

    /// Unrounded per-game changes that sum to `delta`.
    static func split(delta: Int, surprises: [Double]) -> [Double] {
        let total = Double(delta)
        let sum = surprises.reduce(0, +)
        // Proportional when the games explain the change: same sign, meaningful size.
        if delta != 0, abs(sum) >= 0.25, (total > 0) == (sum > 0), abs(total / sum) <= maxK {
            let k = total / sum
            return surprises.map { $0 * k }
        }
        // Otherwise: a standard K per game, with the remainder (bonus points,
        // cancelling results) spread evenly.
        let remainder = (total - fallbackK * sum) / Double(surprises.count)
        return surprises.map { fallbackK * $0 + remainder }
    }

    /// Rounds each value to an integer so they still add up to `total`
    /// (largest-remainder method).
    static func roundPreservingSum(_ values: [Double], total: Int) -> [Int] {
        var result = values.map { Int($0.rounded(.down)) }
        var missing = total - result.reduce(0, +)
        let byRemainder = values.indices.sorted {
            (values[$0] - values[$0].rounded(.down)) > (values[$1] - values[$1].rounded(.down))
        }
        var i = 0
        while missing > 0, !byRemainder.isEmpty {
            result[byRemainder[i % byRemainder.count]] += 1
            missing -= 1
            i += 1
        }
        return result
    }
}

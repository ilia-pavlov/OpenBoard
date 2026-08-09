import Foundation

// MARK: - Player

/// The stable domain contract. UI codes against these types only;
/// API field-name drift is absorbed in the decoding layer (USCFAPITypes.swift).
struct Player: Identifiable, Codable, Sendable, Hashable {
    let id: String            // 8-digit USCF member ID
    var name: String
    var state: String?        // "NJ"
    var ratings: Ratings
    var ranking: Ranking?
    var events: [EventResult]
    /// Chronological regular-rating series (oldest → newest) for the sparkline.
    var ratingHistory: [Int] = []

    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    var peakRegular: Int? {
        let candidates = ratingHistory + [ratings.regular?.value].compactMap { $0 }
        return candidates.max()
    }

    /// Best-available regular rating: the published value, or — for new/provisional
    /// players whose supplement hasn't posted yet — the most recent event's post rating.
    var currentRegular: Int? { ratings.regular?.value ?? events.first?.regular?.post }
    var currentQuick: Int? { ratings.quick?.value ?? events.first?.quick?.post }
}

struct Ratings: Codable, Sendable, Hashable {
    var regular: Rating?
    var quick: Rating?
    var blitz: Rating?
    var onlineRegular: Rating?
    var onlineQuick: Rating?
    var onlineBlitz: Rating?
}

struct Rating: Codable, Sendable, Hashable {
    var value: Int?
    var floor: Int?
    var games: Int?

    var isProvisional: Bool { (games ?? 0) < 26 }
    var isRated: Bool { value != nil }
}

// MARK: - Ranking

struct Ranking: Codable, Sendable, Hashable {
    var overall: RankSlot?
    var state: RankSlot?
    var stateName: String?
}

struct RankSlot: Codable, Sendable, Hashable {
    var rank: Int
    var total: Int
    var percentile: Int?

    /// Percentile of players at-or-below this rank (spec: 58,224 of 76,379 → 24).
    var computedPercentile: Int {
        percentile ?? Int((Double(total - rank) / Double(max(total, 1)) * 100).rounded())
    }
}

// MARK: - Events

struct EventResult: Identifiable, Codable, Sendable, Hashable {
    let id: String            // event ID when known, else UUID string
    var name: String
    var date: Date?
    var score: String?        // "3.0/5"
    var regular: PrePost?
    var quick: PrePost?
}

struct PrePost: Codable, Sendable, Hashable {
    var pre: Int?
    var post: Int?
    var games: Int?

    var delta: Int? {
        guard let pre, let post else { return nil }
        return post - pre
    }
}

// MARK: - Tournament

struct ChessEvent: Identifiable, Codable, Sendable, Hashable {
    let id: String
    var name: String
    var date: Date?
    var sections: [EventSection]
}

struct EventSection: Identifiable, Codable, Sendable, Hashable {
    var id: String { name }
    var name: String
    var players: [Standing]
}

struct Standing: Identifiable, Codable, Sendable, Hashable {
    let id: String            // member ID
    var rank: Int
    var name: String
    var state: String?
    var points: String        // "3.0"
    var regular: PrePost?
    var quick: PrePost?
    /// Round-by-round results, when the backend provides them (iPad shows these).
    var rounds: [RoundOutcome] = []
}

struct RoundOutcome: Codable, Sendable, Hashable {
    var round: Int
    var symbol: String        // "W" / "L" / "D" / "B" (bye) / "–"
    var color: String?        // "White" / "Black"
    var opponentRank: Int?
    var opponentName: String? // nil for byes
}

// MARK: - Search

struct PlayerSummary: Identifiable, Codable, Sendable, Hashable {
    let id: String
    var name: String
    var state: String?
    var regular: Int?
}

extension PlayerSummary {
    init(_ player: Player) {
        self.init(id: player.id, name: player.name, state: player.state,
                  regular: player.ratings.regular?.value)
    }
}

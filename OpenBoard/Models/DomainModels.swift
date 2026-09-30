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

    /// True when at least one event carries a post rating for `system` (chart-worthy).
    func hasHistory(_ system: RatingSystem) -> Bool {
        events.contains { $0.result(for: system)?.post != nil }
    }
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

extension EventResult {
    func result(for system: RatingSystem) -> PrePost? {
        switch system {
        case .regular: regular
        case .quick: quick
        }
    }
}

/// Rating systems with per-event pre/post history (blitz has none in the API).
enum RatingSystem: String, CaseIterable, Identifiable, Codable, Sendable, Hashable {
    case regular, quick
    var id: String { rawValue }

    var title: String {
        switch self {
        case .regular: String(localized: "Regular")
        case .quick: String(localized: "Quick")
        }
    }
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

    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
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

// MARK: - Best wins

/// One section of a rated event, e.g. section 2 of event 202312050922.
struct SectionKey: Codable, Sendable, Hashable {
    var eventID: String
    var section: Int
}

/// A rated Regular win (dual-rated games included), before the opponent's
/// rating is known: the games list doesn't carry ratings, the standings do.
struct RatedWin: Codable, Sendable, Hashable {
    var opponentID: String
    var opponentName: String
    var eventID: String
    var eventName: String
    var section: Int
    var date: Date?

    var sectionKey: SectionKey { SectionKey(eventID: eventID, section: section) }
}

/// A player's Regular games: how many, and which were wins.
struct RatedWins: Codable, Sendable, Hashable {
    var gameCount: Int
    var wins: [RatedWin]
}

/// Where a best-wins scan has got to; the card redraws on each step.
struct BestWinsProgress: Sendable, Hashable {
    var wins: [NotableWin]
    var gameCount: Int
    var eventsChecked: Int
    var eventsTotal: Int
    var isFinished: Bool
}

/// A win with both players' Regular ratings going into that event.
struct NotableWin: Identifiable, Codable, Sendable, Hashable {
    var id: String { "\(eventID)-\(section)-\(opponentID)" }
    var opponentID: String
    var opponentName: String
    var opponentRating: Int
    /// The player's own pre-event rating; nil while they were unrated.
    var playerRating: Int?
    var eventID: String
    var eventName: String
    var section: Int
    var date: Date?

    /// How far above the player the opponent was rated (negative = below).
    var ratingGap: Int? { playerRating.map { opponentRating - $0 } }
}

enum BestWins {
    /// The highest-rated opponents beaten, one entry per opponent (their best
    /// rating when beaten more than once), newest first among equal ratings.
    /// Wins over opponents unrated at the time are skipped.
    static func rank(_ wins: [RatedWin],
                     playerID: String,
                     preRatings: [SectionKey: [String: Int]],
                     limit: Int) -> [NotableWin] {
        var best: [String: NotableWin] = [:]
        for win in wins {
            guard let ratings = preRatings[win.sectionKey],
                  let opponentRating = ratings[win.opponentID] else { continue }
            let candidate = NotableWin(opponentID: win.opponentID,
                                       opponentName: win.opponentName,
                                       opponentRating: opponentRating,
                                       playerRating: ratings[playerID],
                                       eventID: win.eventID,
                                       eventName: win.eventName,
                                       section: win.section,
                                       date: win.date)
            if let current = best[win.opponentID], !isBetter(candidate, than: current) { continue }
            best[win.opponentID] = candidate
        }
        return Array(best.values.sorted(by: isBetter).prefix(limit))
    }

    /// Beating someone this far above your own rating is vanishingly rare
    /// (an expected score around 1%), so it bounds where a better win can be.
    static let maxUpset = 800

    /// Sections to check, strongest first: by the player's own pre-event rating,
    /// newest first among equals. Sections with no known rating go last, since
    /// they can't be ruled out early.
    static func scanOrder(_ wins: [RatedWin], playerRatings: [String: Int]) -> [SectionKey] {
        var newest: [SectionKey: Date] = [:]
        for win in wins {
            newest[win.sectionKey] = max(newest[win.sectionKey] ?? .distantPast, win.date ?? .distantPast)
        }
        return newest.keys.sorted { a, b in
            switch (playerRatings[a.eventID], playerRatings[b.eventID]) {
            case let (x?, y?) where x != y: return x > y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return newest[a]! > newest[b]!
            }
        }
    }

    /// True once `best` is full and a player rated `nextPlayerRating` would need
    /// an upset beyond `maxUpset` to beat anyone better than its last entry.
    /// Sections come strongest first, so every later one is ruled out too.
    static func canStop(best: [NotableWin], limit: Int, nextPlayerRating: Int?) -> Bool {
        guard best.count >= limit, let floor = best.last?.opponentRating,
              let nextPlayerRating else { return false }
        return nextPlayerRating + maxUpset < floor
    }

    private static func isBetter(_ a: NotableWin, than b: NotableWin) -> Bool {
        if a.opponentRating != b.opponentRating { return a.opponentRating > b.opponentRating }
        return (a.date ?? .distantPast) > (b.date ?? .distantPast)
    }
}

import Foundation

/// Offline/demo/test data source. Uses entirely SYNTHETIC sample players and
/// events — no real US Chess member or event IDs are baked into the app.
/// The shipping app defaults to live data; this exists for previews, UI tests,
/// and the `-mock` (zero-network) demo mode.
struct MockRatingsService: RatingsProviding {

    /// Synthetic identifiers, used by demo/screenshot routing too.
    static let samplePlayerID = "90000001"
    static let sampleEventID = "900000000001"

    func player(id: String) async throws -> Player {
        try await Task.sleep(for: .milliseconds(250)) // let skeletons shimmer
        if let player = Self.players[id] { return player }
        throw RatingsError.notFound
    }

    func search(_ query: String) async throws -> [PlayerSummary] {
        try await Task.sleep(for: .milliseconds(200))
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.count == 8, q.allSatisfy(\.isNumber) {
            return Self.players[q].map { [PlayerSummary($0)] } ?? []
        }
        return Self.roster
            .filter { q.isEmpty || $0.name.lowercased().contains(q) }
            .sorted { ($0.regular ?? 0) > ($1.regular ?? 0) }
    }

    func event(id: String) async throws -> ChessEvent {
        try await Task.sleep(for: .milliseconds(250))
        guard id == Self.sampleEvent.id else { throw RatingsError.notFound }
        return Self.sampleEvent
    }

    // MARK: - Seed: synthetic primary player

    static let samplePlayer = Player(
        id: samplePlayerID,
        name: "Alex Rivera",
        state: "NJ",
        ratings: Ratings(
            regular: Rating(value: 383, floor: 131, games: 5),
            quick: Rating(value: 379, floor: 131, games: 5),
            blitz: Rating(value: nil, floor: nil, games: 0),
            onlineRegular: Rating(value: nil, floor: nil, games: 0),
            onlineQuick: Rating(value: nil, floor: nil, games: 0),
            onlineBlitz: Rating(value: nil, floor: nil, games: 0)
        ),
        ranking: Ranking(
            overall: RankSlot(rank: 58_224, total: 76_379, percentile: 24),
            state: RankSlot(rank: 2_204, total: 2_711, percentile: 19),
            stateName: "New Jersey"
        ),
        events: [
            EventResult(id: sampleEventID, name: "Sample Scholastic Open 2026",
                        date: date(2026, 8, 6), score: "3.0/5",
                        regular: PrePost(pre: 322, post: 420, games: 12),
                        quick: PrePost(pre: 319, post: 415, games: 12)),
            EventResult(id: "900000000002", name: "Spring Scholastic Championship",
                        date: date(2026, 6, 14), score: "2.0/5",
                        regular: PrePost(pre: 341, post: 322, games: nil)),
            EventResult(id: "900000000003", name: "Winter K-8 Open",
                        date: date(2026, 4, 27), score: "3.5/5",
                        regular: PrePost(pre: 298, post: 341, games: nil),
                        quick: PrePost(pre: 301, post: 319, games: nil)),
            EventResult(id: "900000000004", name: "February Quads",
                        date: date(2026, 2, 21), score: "2.0/3",
                        regular: PrePost(pre: 240, post: 298, games: nil)),
            EventResult(id: "900000000005", name: "New Year Scholastic",
                        date: date(2026, 1, 10), score: "1.5/4",
                        regular: PrePost(pre: 255, post: 240, games: nil),
                        quick: PrePost(pre: 301, post: 301, games: nil)),
            EventResult(id: "900000000006", name: "Fall Rookie Swiss",
                        date: date(2025, 11, 15), score: "2.0/4",
                        regular: PrePost(pre: 210, post: 255, games: nil)),
        ],
        ratingHistory: [210, 255, 240, 298, 341, 322, 420]
    )

    static let players: [String: Player] = {
        var all: [String: Player] = [samplePlayer.id: samplePlayer]
        for standing in sampleEvent.sections[0].players where standing.id != samplePlayer.id {
            all[standing.id] = Player(
                id: standing.id,
                name: standing.name,
                state: standing.state,
                ratings: Ratings(
                    regular: Rating(value: standing.regular?.post,
                                    floor: nil,
                                    games: standing.regular?.games),
                    quick: Rating(value: standing.quick?.post,
                                  floor: nil,
                                  games: standing.quick?.games)
                ),
                ranking: nil,
                events: [
                    EventResult(id: sampleEvent.id, name: sampleEvent.name,
                                date: sampleEvent.date, score: "\(standing.points)/5",
                                regular: standing.regular, quick: standing.quick)
                ],
                ratingHistory: [standing.regular?.pre, standing.regular?.post].compactMap { $0 }
            )
        }
        return all
    }()

    static var roster: [PlayerSummary] {
        players.values.map(PlayerSummary.init)
    }

    // MARK: - Seed: synthetic tournament

    /// Compact round-outcome constructor for the mock crosstable.
    private static func rd(_ n: Int, _ s: String, _ c: String, _ rank: Int, _ name: String) -> RoundOutcome {
        RoundOutcome(round: n, symbol: s, color: c, opponentRank: rank, opponentName: name)
    }

    static let sampleEvent = ChessEvent(
        id: sampleEventID,
        name: "Sample Scholastic Open 2026",
        date: date(2026, 8, 6),
        sections: [
            EventSection(name: "Section 1 SS G/30 d5", players: [
                Standing(id: "90000010", rank: 1, name: "Ava Sterling", state: nil, points: "4.0",
                         regular: PrePost(pre: nil, post: 823, games: 4),
                         quick: PrePost(pre: nil, post: 818, games: 4),
                         rounds: [rd(1, "W", "Black", 6, "Ivy Nguyen"), rd(2, "W", "White", 5, "Owen Price"),
                                  rd(3, "W", "Black", 4, "Liam Carter"), rd(4, "W", "White", 3, "Maya Brooks"),
                                  rd(5, "L", "Black", 2, "Alex Rivera")]),
                Standing(id: samplePlayerID, rank: 2, name: "Alex Rivera", state: "NJ", points: "3.0",
                         regular: PrePost(pre: 322, post: 420, games: 12),
                         quick: PrePost(pre: 319, post: 415, games: 12),
                         rounds: [rd(1, "W", "White", 5, "Owen Price"), rd(2, "W", "Black", 6, "Ivy Nguyen"),
                                  rd(3, "L", "White", 3, "Maya Brooks"), rd(4, "L", "Black", 4, "Liam Carter"),
                                  rd(5, "W", "White", 1, "Ava Sterling")]),
                Standing(id: "90000011", rank: 3, name: "Maya Brooks", state: nil, points: "2.0",
                         regular: PrePost(pre: 305, post: 312, games: nil),
                         quick: PrePost(pre: 288, post: 297, games: nil),
                         rounds: [rd(1, "W", "White", 6, "Ivy Nguyen"), rd(2, "W", "Black", 5, "Owen Price"),
                                  rd(3, "W", "Black", 2, "Alex Rivera"), rd(4, "L", "Black", 1, "Ava Sterling"),
                                  rd(5, "L", "White", 4, "Liam Carter")]),
                Standing(id: "90000012", rank: 4, name: "Liam Carter", state: nil, points: "1.5",
                         regular: PrePost(pre: 293, post: 287, games: 21),
                         quick: PrePost(pre: 288, post: 283, games: 21),
                         rounds: [rd(1, "W", "Black", 6, "Ivy Nguyen"), rd(2, "D", "White", 5, "Owen Price"),
                                  rd(3, "W", "White", 1, "Ava Sterling"), rd(4, "W", "White", 2, "Alex Rivera"),
                                  rd(5, "W", "Black", 3, "Maya Brooks")]),
                Standing(id: "90000013", rank: 5, name: "Owen Price", state: "NJ", points: "1.0",
                         regular: PrePost(pre: 374, post: 313, games: 20),
                         quick: PrePost(pre: 366, post: 304, games: 20),
                         rounds: [rd(1, "L", "Black", 2, "Alex Rivera"), rd(2, "W", "White", 6, "Ivy Nguyen"),
                                  rd(3, "L", "White", 3, "Maya Brooks"), rd(4, "D", "Black", 4, "Liam Carter"),
                                  rd(5, "L", "White", 1, "Ava Sterling")]),
                Standing(id: "90000014", rank: 6, name: "Ivy Nguyen", state: "NJ", points: "1.0",
                         regular: PrePost(pre: 106, post: 105, games: 7),
                         quick: PrePost(pre: 105, post: 105, games: 7),
                         rounds: [rd(1, "L", "White", 1, "Ava Sterling"), rd(2, "L", "Black", 3, "Maya Brooks"),
                                  rd(3, "W", "Black", 5, "Owen Price"), rd(4, "L", "White", 4, "Liam Carter"),
                                  rd(5, "B", "", 0, "")]),
            ]),
        ]
    )

    private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var comps = DateComponents(year: y, month: m, day: d, hour: 12)
        comps.timeZone = TimeZone(identifier: "America/New_York")
        return Calendar(identifier: .gregorian).date(from: comps)!
    }
}

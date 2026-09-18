import Foundation

// MARK: - Wire types for ratings-api.uschess.org (US Chess MUIR backend, by Leago)
//
// MUIR ("Member Uploads, Information, and Reporting") is US Chess's official
// platform. It publicly serves an OpenAPI/Swagger spec but is not a formally
// documented/supported public API, so treat it as subject to change.
//   Spec:      https://ratings-api.uschess.org/swagger/v1/swagger.json
//   Reference: https://github.com/mikeb26/uschess-go (unofficial Go client)
// Shapes verified against live responses + the spec on 2026-08-08.
// If US Chess renames fields, fix it HERE — the domain models must not change.

struct APIPage<T: Decodable & Sendable>: Decodable, Sendable {
    var items: [T]
    var hasNextPage: Bool?
    var offset: Int?
    var pageSize: Int?
}

struct APIMember: Decodable, Sendable {
    var id: String
    var firstName: String?
    var lastName: String?
    var stateRep: String?
    var jurisdiction: String?
    var rank: Int?
    var stateRank: Int?
    var ratings: [APIMemberRating]?
}

struct APIMemberRating: Decodable, Sendable {
    var ratingSystem: String?   // "R" "Q" "B" "OR" "OQ" "OB"
    var rating: Int?
    var gamesPlayed: Int?
    var isProvisional: Bool?
    var floor: Int?
}

struct APIMemberSection: Decodable, Sendable {
    var sectionNumber: Int?
    var sectionName: String?
    var startDate: String?
    var endDate: String?
    var ratingRecords: [APIRatingRecord]?
    var event: APIEventRef?
}

struct APIRatingRecord: Decodable, Sendable {
    var preRating: Int?
    var postRating: Int?
    var ratingSource: String?   // "R" / "Q" on member sections
    var ratingSystem: String?   // "R" / "Q" on standings
    var postProvisionalGameCount: Int?

    var system: String? { ratingSource ?? ratingSystem }
}

struct APIEventRef: Decodable, Sendable {
    var id: String?
    var name: String?
    var startDate: String?
    var stateCode: String?
}

struct APIRatedEvent: Decodable, Sendable {
    var id: String
    var name: String?
    var startDate: String?
    var endDate: String?
    var sections: [APISectionRef]?
}

struct APISectionRef: Decodable, Sendable {
    var number: Int
    var name: String?
}

struct APIStanding: Decodable, Sendable {
    var ordinal: Int?
    var memberId: String?
    var firstName: String?
    var lastName: String?
    var stateRep: String?
    var score: Double?
    var ratings: [APIRatingRecord]?
    var roundOutcomes: [APIRoundOutcome]?
}

struct APIRoundOutcome: Decodable, Sendable {
    var roundNumber: Int?
    var outcome: String?        // "Win" / "Loss" / "Draw" / "Bye" / …
    var color: String?
    var opponentOrdinal: Int?
    var opponentFirstName: String?
    var opponentLastName: String?
}

struct APIMaxRank: Decodable, Sendable {
    var ratingSource: String?
    var maxRank: Int?
    var jurisdiction: String?   // nil = national
}

struct APITopListDefinition: Decodable, Sendable {
    var id: String
    var name: String?
    var ratingSource: String?
    var minAge: Int?
    var maxAge: Int?
    var gender: String?
    var fideUsaOnly: Bool?
}

struct APITopList: Decodable, Sendable {
    struct Player: Decodable, Sendable {
        var ordinal: Int?
        var rating: Int?
        var id: String?
        var firstName: String?
        var lastName: String?
        var stateRep: String?
    }
    var topPlayerReportDefinitionId: String?
    var reportDate: String?
    var topPlayers: [Player]?
}

// MARK: - Mapping to domain

enum USCFMapper {
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/New_York")
        return f
    }()

    static func date(_ s: String?) -> Date? {
        s.flatMap { dateFormatter.date(from: $0) }
    }

    static func ratings(from api: [APIMemberRating]?) -> Ratings {
        var r = Ratings()
        for entry in api ?? [] {
            let rating = Rating(value: entry.rating, floor: entry.floor, games: entry.gamesPlayed)
            switch entry.ratingSystem {
            case "R": r.regular = rating
            case "Q": r.quick = rating
            case "B": r.blitz = rating
            case "OR": r.onlineRegular = rating
            case "OQ": r.onlineQuick = rating
            case "OB": r.onlineBlitz = rating
            default: break
            }
        }
        return r
    }

    static func name(first: String?, last: String?) -> String {
        [first, last].compactMap { $0 }.joined(separator: " ")
            .capitalizedIfShouty()
    }

    static func player(member: APIMember,
                       sections: [APIMemberSection],
                       maxRanks: [APIMaxRank]) -> Player {
        let ratings = ratings(from: member.ratings)
        let state = member.stateRep ?? member.jurisdiction

        var ranking: Ranking?
        let nationalTotal = maxRanks.first { $0.jurisdiction == nil && $0.ratingSource == "R" }?.maxRank
        let stateTotal = maxRanks.first { $0.jurisdiction == state && $0.ratingSource == "R" }?.maxRank
        if member.rank != nil || member.stateRank != nil {
            ranking = Ranking(
                overall: member.rank.map { RankSlot(rank: $0, total: nationalTotal ?? 0) },
                state: member.stateRank.map { RankSlot(rank: $0, total: stateTotal ?? 0) },
                stateName: state
            )
        }

        let events = eventResults(from: sections)
        return Player(
            id: member.id,
            name: name(first: member.firstName, last: member.lastName),
            state: state,
            ratings: ratings,
            ranking: ranking,
            events: events,
            ratingHistory: history(from: events)
        )
    }

    static func eventResults(from sections: [APIMemberSection]) -> [EventResult] {
        sections.map { section in
            let records = section.ratingRecords ?? []
            func prePost(_ system: String) -> PrePost? {
                records.first { $0.system == system }.map {
                    PrePost(pre: $0.preRating, post: $0.postRating, games: $0.postProvisionalGameCount)
                }
            }
            return EventResult(
                id: section.event?.id ?? UUID().uuidString,
                name: section.event?.name?.capitalizedIfShouty() ?? section.sectionName ?? "Rated Event",
                date: date(section.event?.startDate ?? section.startDate),
                score: nil, // per-player score is only exposed on crosstable standings
                regular: prePost("R"),
                quick: prePost("Q")
            )
        }
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Oldest pre-rating followed by each post-rating, oldest → newest.
    static func history(from events: [EventResult]) -> [Int] {
        let chronological = events.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        var series: [Int] = []
        if let firstPre = chronological.first?.regular?.pre { series.append(firstPre) }
        series.append(contentsOf: chronological.compactMap { $0.regular?.post })
        return series
    }

    /// Regular/Quick/Blitz over-the-board lists for US players; online and
    /// correspondence lists and "any federation" duplicates are skipped.
    static func topListDefinitions(_ api: [APITopListDefinition]) -> [TopListDefinition] {
        api.compactMap { d in
            guard d.fideUsaOnly != false,
                  let rating = d.ratingSource.flatMap(TopListRating.init(rawValue:)) else { return nil }
            return TopListDefinition(id: d.id, name: d.name ?? d.id, rating: rating,
                                     minAge: d.minAge, maxAge: d.maxAge, isWomen: d.gender == "Female")
        }
    }

    static func topList(_ api: APITopList, definition: TopListDefinition) -> TopList {
        TopList(
            definition: definition,
            reportDate: date(api.reportDate),
            entries: (api.topPlayers ?? []).compactMap { p in
                guard let id = p.id, let rank = p.ordinal, let rating = p.rating else { return nil }
                return TopListEntry(id: id, rank: rank, name: name(first: p.firstName, last: p.lastName),
                                    state: p.stateRep, rating: rating)
            }
        )
    }

    static func summary(member: APIMember) -> PlayerSummary {
        PlayerSummary(
            id: member.id,
            name: name(first: member.firstName, last: member.lastName),
            state: member.stateRep ?? member.jurisdiction,
            regular: member.ratings?.first { $0.ratingSystem == "R" }?.rating
        )
    }

    static func standing(_ api: APIStanding, roundCount: Int?) -> Standing {
        func prePost(_ system: String) -> PrePost? {
            api.ratings?.first { $0.system == system }.map {
                PrePost(pre: $0.preRating, post: $0.postRating, games: $0.postProvisionalGameCount)
            }
        }
        let score = api.score ?? 0
        let points = score.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.1f", score) : String(score)
        return Standing(
            id: api.memberId ?? UUID().uuidString,
            rank: api.ordinal ?? 0,
            name: name(first: api.firstName, last: api.lastName),
            state: api.stateRep,
            points: points,
            regular: prePost("R"),
            quick: prePost("Q"),
            rounds: (api.roundOutcomes ?? []).compactMap { r in
                guard let n = r.roundNumber else { return nil }
                let symbol: String = switch r.outcome {
                case "Win": "W"
                case "Loss": "L"
                case "Draw": "D"
                case "Bye", "FullPointBye", "HalfPointBye": "B"
                default: "–"
                }
                let opponent = name(first: r.opponentFirstName, last: r.opponentLastName)
                return RoundOutcome(round: n, symbol: symbol, color: r.color,
                                    opponentRank: r.opponentOrdinal,
                                    opponentName: opponent.isEmpty ? nil : opponent)
            }.sorted { $0.round < $1.round }
        )
    }
}

extension String {
    /// USCF stores many names in ALL CAPS ("MAGNUS CARLSEN"); title-case those,
    /// leave mixed-case names untouched.
    func capitalizedIfShouty() -> String {
        guard self == uppercased(), !isEmpty else { return self }
        return lowercased().split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

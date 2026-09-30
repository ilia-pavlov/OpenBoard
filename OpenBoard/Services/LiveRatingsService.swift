import Foundation

/// Talks directly to ratings-api.uschess.org. All endpoint knowledge lives here
/// and in USCFAPITypes.swift; swap the base URL or parsing without touching UI.
actor LiveRatingsService: RatingsProviding {
    private let session: URLSession
    private let decoder = JSONDecoder()

    /// In-flight request de-duplication: identical URLs share one network call.
    private var inflight: [URL: Task<Data, Error>] = [:]
    private var cachedMaxRanks: [APIMaxRank]?

    /// Seconds to wait before each retry of a rate-limited (429) request; the
    /// last entry is never waited on.
    private let rateLimitBackoff: [Double]

    /// Tests pass a stub `URLProtocol` and no backoff; the app uses the defaults.
    init(protocolClasses: [AnyClass] = [], rateLimitBackoff: [Double] = LiveRatingsService.defaultBackoff) {
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = [
            "User-Agent": AppEnvironment.userAgent,
            "Accept": "application/json",
        ]
        config.timeoutIntervalForRequest = 20
        if !protocolClasses.isEmpty { config.protocolClasses = protocolClasses }
        session = URLSession(configuration: config)
        self.rateLimitBackoff = rateLimitBackoff
    }

    // MARK: RatingsProviding

    func player(id: String) async throws -> Player {
        async let member: APIMember = get(USChess.fill(USChess.Ratings.member, ["memberID": id]))
        async let sections = allSections(memberID: id)
        async let ranks = maxRanks()
        return try await USCFMapper.player(member: member,
                                           sections: sections,
                                           maxRanks: ranks)
    }

    /// Every rated section the player has, newest first. The API caps pages at
    /// 100, and active juniors can have hundreds, so keep paging until done —
    /// otherwise Rating History starts partway through their career.
    private func allSections(memberID id: String) async throws -> [APIMemberSection] {
        try await Self.collectPages(pageSize: 100) { offset, size in
            try await self.get(USChess.fill(USChess.Ratings.memberSections, ["memberID": id]),
                     query: [USChess.Params.size: String(size), USChess.Params.offset: String(offset)])
        }
    }

    /// Fetches pages until the API says there are no more (capped at `maxPages`).
    static func collectPages<T: Decodable & Sendable>(
        pageSize: Int, maxPages: Int = 20,
        fetch: @Sendable (_ offset: Int, _ size: Int) async throws -> APIPage<T>
    ) async throws -> [T] {
        var all: [T] = []
        for pageIndex in 0..<maxPages {
            let page = try await fetch(pageIndex * pageSize, pageSize)
            all += page.items
            guard page.hasNextPage == true, !page.items.isEmpty else { break }
        }
        return all
    }

    func search(_ query: String) async throws -> [PlayerSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.count == 8, trimmed.allSatisfy(\.isNumber) {
            let member: APIMember = try await get(USChess.fill(USChess.Ratings.member, ["memberID": trimmed]))
            return [USCFMapper.summary(member: member)]
        }
        // The API's fuzzy name search is the `Fuzzy` query parameter; pagination
        // uses `Offset`/`Size`. An unrecognized param (e.g. `search`) is silently
        // ignored and the endpoint returns the default top-rated list.
        let page: APIPage<APIMember> = try await get(USChess.Ratings.memberSearch,
                                                              query: [USChess.Params.fuzzy: trimmed, USChess.Params.size: "40"])
        return page.items.map(USCFMapper.summary)
    }

    func event(id: String) async throws -> ChessEvent {
        let event: APIRatedEvent = try await get(USChess.fill(USChess.Ratings.ratedEvent, ["eventID": id]))
        let refs = (event.sections ?? []).sorted { $0.number < $1.number }

        let sections: [EventSection] = try await withThrowingTaskGroup(of: (Int, EventSection).self) { group in
            for ref in refs {
                group.addTask {
                    let standings = try await self.standings(eventID: id, section: ref.number)
                    return (ref.number, EventSection(name: ref.name ?? "Section \(ref.number)",
                                                     players: standings))
                }
            }
            var collected: [(Int, EventSection)] = []
            for try await item in group { collected.append(item) }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }

        return ChessEvent(id: event.id,
                          name: event.name?.capitalizedIfShouty() ?? "Event \(id)",
                          date: USCFMapper.date(event.endDate ?? event.startDate),
                          sections: sections)
    }

    func regularWins(memberID id: String) async throws -> RatedWins {
        // RatingSource=R returns regular and dual-rated games. Very active players
        // have well over 1,000 games, hence the higher page cap.
        let games: [APIMemberGame] = try await Self.collectPages(pageSize: 100, maxPages: 50) { offset, size in
            try await self.get(USChess.fill(USChess.Ratings.memberGames, ["memberID": id]),
                               query: [USChess.Params.ratingSource: "R",
                                       USChess.Params.size: String(size),
                                       USChess.Params.offset: String(offset)])
        }
        return RatedWins(gameCount: games.count, wins: games.compactMap(USCFMapper.regularWin))
    }

    func regularPreRatings(eventID: String, section: Int) async throws -> [String: Int] {
        let players = try await standings(eventID: eventID, section: section)
        return players.reduce(into: [:]) { map, standing in
            if let pre = standing.regular?.pre { map[standing.id] = pre }
        }
    }

    // MARK: - Internals

    private func standings(eventID: String, section: Int) async throws -> [Standing] {
        var all: [APIStanding] = []
        var offset = 0
        for _ in 0..<5 { // safety cap: 500 players per section
            let page: APIPage<APIStanding> = try await get(
                USChess.fill(USChess.Ratings.sectionStandings, ["eventID": eventID, "section": String(section)]),
                query: [USChess.Params.size: "100", USChess.Params.offset: String(offset)])
            all.append(contentsOf: page.items)
            guard page.hasNextPage == true else { break }
            offset += page.items.count
        }
        let roundCount = all.map { $0.roundOutcomes?.count ?? 0 }.max()
        return all.map { USCFMapper.standing($0, roundCount: roundCount) }
    }

    func topListDefinitions() async throws -> [TopListDefinition] {
        let page: APIPage<APITopListDefinition> = try await get(USChess.Ratings.topListCatalog,
                                                                        query: [USChess.Params.size: "200"])
        return USCFMapper.topListDefinitions(page.items)
    }

    func topList(_ definition: TopListDefinition) async throws -> TopList {
        let list: APITopList = try await get(USChess.fill(USChess.Ratings.topList, ["listID": definition.id]))
        return USCFMapper.topList(list, definition: definition)
    }

    private func maxRanks() async throws -> [APIMaxRank] {
        if let cachedMaxRanks { return cachedMaxRanks }
        let ranks: [APIMaxRank] = try await get(USChess.Ratings.maxRanks)
        cachedMaxRanks = ranks
        return ranks
    }

    private func get<T: Decodable & Sendable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        guard var components = URLComponents(url: AppEnvironment.baseURL.appending(path: path),
                                             resolvingAgainstBaseURL: false) else {
            throw RatingsError.badURL
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw RatingsError.badURL }

        let data = try await fetchData(url)
        return try decoder.decode(T.self, from: data)
    }

    /// Adds up to about a minute, the API's rate-limit window.
    static let defaultBackoff: [Double] = [4, 10, 20, 30, 0]

    private func fetchData(_ url: URL) async throws -> Data {
        if let existing = inflight[url] {
            return try await existing.value
        }
        let task = Task<Data, Error> { [session, rateLimitBackoff] in
            // The API allows roughly 100 requests a minute and then answers 429 for
            // about 40 seconds. Wait it out rather than failing the screen.
            for (attempt, backoff) in rateLimitBackoff.enumerated() {
                do {
                    let (data, response) = try await session.data(from: url)
                    if let http = response as? HTTPURLResponse {
                        if http.statusCode == 404 { throw RatingsError.notFound }
                        if http.statusCode == 429 {
                            guard attempt < rateLimitBackoff.count - 1 else { throw RatingsError.rateLimited }
                            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(Double.init)
                            try await Task.sleep(for: .seconds(retryAfter ?? backoff))
                            continue
                        }
                        guard (200..<300).contains(http.statusCode) else {
                            throw RatingsError.httpStatus(http.statusCode)
                        }
                    }
                    return data
                } catch let error as RatingsError {
                    throw error
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw RatingsError.offline(underlying: error.localizedDescription)
                }
            }
            throw RatingsError.rateLimited
        }
        inflight[url] = task
        defer { inflight[url] = nil }
        return try await task.value
    }
}

import Foundation

/// Talks directly to ratings-api.uschess.org. All endpoint knowledge lives here
/// and in USCFAPITypes.swift; swap the base URL or parsing without touching UI.
actor LiveRatingsService: RatingsProviding {
    private let session: URLSession
    private let decoder = JSONDecoder()

    /// In-flight request de-duplication: identical URLs share one network call.
    private var inflight: [URL: Task<Data, Error>] = [:]
    private var cachedMaxRanks: [APIMaxRank]?

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = [
            "User-Agent": AppEnvironment.userAgent,
            "Accept": "application/json",
        ]
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    // MARK: RatingsProviding

    func player(id: String) async throws -> Player {
        async let member: APIMember = get("members/\(id)")
        async let sections: APIPage<APIMemberSection> = get("members/\(id)/sections", query: ["Size": "50"])
        async let ranks = maxRanks()
        return try await USCFMapper.player(member: member,
                                           sections: sections.items,
                                           maxRanks: ranks)
    }

    func search(_ query: String) async throws -> [PlayerSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.count == 8, trimmed.allSatisfy(\.isNumber) {
            let member: APIMember = try await get("members/\(trimmed)")
            return [USCFMapper.summary(member: member)]
        }
        // The API's fuzzy name search is the `Fuzzy` query parameter; pagination
        // uses `Offset`/`Size`. An unrecognized param (e.g. `search`) is silently
        // ignored and the endpoint returns the default top-rated list.
        let page: APIPage<APIMember> = try await get("members", query: ["Fuzzy": trimmed, "Size": "40"])
        return page.items.map(USCFMapper.summary)
    }

    func event(id: String) async throws -> ChessEvent {
        let event: APIRatedEvent = try await get("rated-events/\(id)")
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

    // MARK: - Internals

    private func standings(eventID: String, section: Int) async throws -> [Standing] {
        var all: [APIStanding] = []
        var offset = 0
        for _ in 0..<5 { // safety cap: 500 players per section
            let page: APIPage<APIStanding> = try await get(
                "rated-events/\(eventID)/sections/\(section)/standings",
                query: ["Size": "100", "Offset": String(offset)])
            all.append(contentsOf: page.items)
            guard page.hasNextPage == true else { break }
            offset += page.items.count
        }
        let roundCount = all.map { $0.roundOutcomes?.count ?? 0 }.max()
        return all.map { USCFMapper.standing($0, roundCount: roundCount) }
    }

    private func maxRanks() async throws -> [APIMaxRank] {
        if let cachedMaxRanks { return cachedMaxRanks }
        let ranks: [APIMaxRank] = try await get("members/max-ranks")
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

    private func fetchData(_ url: URL) async throws -> Data {
        if let existing = inflight[url] {
            return try await existing.value
        }
        let task = Task<Data, Error> { [session] in
            do {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 404 { throw RatingsError.notFound }
                    guard (200..<300).contains(http.statusCode) else {
                        throw RatingsError.httpStatus(http.statusCode)
                    }
                }
                return data
            } catch let error as RatingsError {
                throw error
            } catch {
                throw RatingsError.offline(underlying: error.localizedDescription)
            }
        }
        inflight[url] = task
        defer { inflight[url] = nil }
        return try await task.value
    }
}

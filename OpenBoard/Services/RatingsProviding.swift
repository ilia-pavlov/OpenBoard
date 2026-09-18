import Foundation

protocol RatingsProviding: Sendable {
    func player(id: String) async throws -> Player
    func search(_ query: String) async throws -> [PlayerSummary]
    func event(id: String) async throws -> ChessEvent
    /// Every Top 100 list US Chess publishes (monthly).
    func topListDefinitions() async throws -> [TopListDefinition]
    func topList(_ definition: TopListDefinition) async throws -> TopList
}

enum RatingsError: LocalizedError {
    case badURL
    case httpStatus(Int)
    case notFound
    case offline(underlying: String)

    var errorDescription: String? {
        switch self {
        case .badURL: "Invalid request."
        case .httpStatus(let code): "US Chess responded with an error (\(code))."
        case .notFound: "No record found."
        case .offline(let s): "Couldn't reach US Chess. \(s)"
        }
    }
}

/// Flip `dataSource` to switch the whole app between live and mock data.
enum AppEnvironment {
    enum DataSource { case live, mock }

    /// The one flag. The API probe on 2026-08-08 confirmed ratings-api.uschess.org
    /// is live and stable, so live is the default. `-mock` launch argument
    /// (used by UI tests and previews) forces mock.
    static var dataSource: DataSource {
        ProcessInfo.processInfo.arguments.contains("-mock") ? .mock : .live
    }

    static let baseURL = URL(string: "https://ratings-api.uschess.org/api/v1")!
    static let userAgent = "OpenBoard-iOS/1.0"
    static let cacheTTL: TimeInterval = 5 * 60

    /// Screenshot/demo helper: `-screen event`, `-screen profile`, …
    static var requestedScreen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screen"), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    /// Optional argument for the requested screen, e.g. a member ID for `-screen profile`.
    static var requestedScreenArg: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screenArg"), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    /// Demo/screenshot helper: pre-expand the followed player's crosstable row.
    static var autoExpandHighlight: Bool {
        ProcessInfo.processInfo.arguments.contains("-expandHighlight")
    }

    /// Demo/screenshot helper: seed the watchlist with synthetic sample players so
    /// My Card / Watching render populated. Never used by the shipping app.
    static var demoSeed: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoSeed")
    }
}

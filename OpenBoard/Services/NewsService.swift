import Foundation

/// News comes from the US Chess website's RSS feeds (10 newest articles per
/// feed, full text inside). An article's clean body comes from the site's JSON
/// view of the page (`?_format=json`), the same trick announcements use.
protocol NewsProviding: Sendable {
    func articles(_ topic: NewsTopic) async throws -> [NewsArticle]
    /// The article body as inline Markdown (see `TournamentParser.markdown(fromHTML:)`).
    func body(of article: NewsArticle) async throws -> String
}

struct LiveNewsService: NewsProviding {
    func articles(_ topic: NewsTopic) async throws -> [NewsArticle] {
        NewsParser.articles(fromRSS: try await fetch(topic.feedURL))
    }

    func body(of article: NewsArticle) async throws -> String {
        guard var components = URLComponents(url: article.link, resolvingAgainstBaseURL: false) else {
            throw RatingsError.badURL
        }
        components.queryItems = [URLQueryItem(name: "_format", value: "json")]
        guard let url = components.url else { throw RatingsError.badURL }
        struct Node: Decodable {
            struct Value: Decodable { let value: String? }
            let body: [Value]?
        }
        let html = try JSONDecoder().decode(Node.self, from: try await fetch(url)).body?.first?.value ?? ""
        return TournamentParser.markdown(fromHTML: html)
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(AppEnvironment.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw http.statusCode == 404 ? RatingsError.notFound : RatingsError.httpStatus(http.statusCode)
            }
            return data
        } catch let error as RatingsError {
            throw error
        } catch {
            throw RatingsError.offline(underlying: error.localizedDescription)
        }
    }
}

/// Caches feeds for 15 minutes and article bodies for a day, and serves the
/// last copy when the site can't be reached.
final class CachedNewsService: Sendable {
    let upstream: any NewsProviding
    let cache: CacheStore

    private static let feedTTL: TimeInterval = 15 * 60
    private static let bodyTTL: TimeInterval = 24 * 60 * 60

    init(upstream: any NewsProviding, cache: CacheStore) {
        self.upstream = upstream
        self.cache = cache
    }

    func articles(_ topic: NewsTopic, force: Bool = false) async throws -> [NewsArticle] {
        try await cached(key: "news-\(topic.rawValue)", ttl: Self.feedTTL, force: force) {
            try await self.upstream.articles(topic)
        }
    }

    func body(of article: NewsArticle) async throws -> String {
        try await cached(key: "news-body-\(article.id)", ttl: Self.bodyTTL, force: false) {
            try await self.upstream.body(of: article)
        }
    }

    /// Last stored feed regardless of age, for the offline error state.
    func cachedArticles(_ topic: NewsTopic) async -> ([NewsArticle], Date)? {
        await cache.read([NewsArticle].self, key: "news-\(topic.rawValue)").map { ($0.value, $0.updatedAt) }
    }

    private func cached<T: Codable & Sendable>(
        key: String,
        ttl: TimeInterval,
        force: Bool,
        fetch: @Sendable () async throws -> T
    ) async throws -> T {
        if !force, let entry = await cache.read(T.self, key: key, ttl: ttl), entry.isFresh {
            return entry.value
        }
        do {
            let fresh = try await fetch()
            await cache.write(fresh, key: key)
            return fresh
        } catch {
            if let stale = await cache.read(T.self, key: key) { return stale.value }
            throw error
        }
    }
}

// MARK: - RSS parsing

enum NewsParser {
    static let site = URL(string: "https://new.uschess.org")!

    static func articles(fromRSS data: Data) -> [NewsArticle] {
        let collector = RSSItemCollector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.parse()
        return collector.items.compactMap(article)
    }

    private static func article(_ item: RSSItemCollector.Item) -> NewsArticle? {
        guard let link = URL(string: item.link.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let title = TournamentParser.clean(item.title)
        guard !title.isEmpty else { return nil }
        let author = TournamentParser.clean(item.creator)
        return NewsArticle(title: title,
                           link: link,
                           author: author.isEmpty ? nil : author,
                           published: date(item.pubDate),
                           imageURLs: imageURLs(in: item.description),
                           summary: summary(of: item.description))
    }

    /// Photos in the article. The feed lazy-loads images: `src` is an empty SVG
    /// placeholder and the real (site-relative) address is in `data-src`/`srcset`.
    static func imageURLs(in html: String) -> [URL] {
        var seen = Set<String>()
        var urls: [URL] = []
        for tag in TournamentParser.captures(#"(<img[^>]*>)"#, in: html) {
            let candidates = ["data-src", "srcset", "data-srcset", "src"].compactMap { attribute in
                TournamentParser.captures(#"\#(attribute)="([^"]+)""#, in: tag).first
            }
            guard let raw = candidates.first(where: { !$0.hasPrefix("data:") }) else { continue }
            let path = TournamentParser.unescape(raw.split(separator: " ").first.map(String.init) ?? raw)
            guard path.contains("/files/"), let url = URL(string: path, relativeTo: site)?.absoluteURL,
                  seen.insert(url.path()).inserted else { continue }
            urls.append(url)
        }
        return urls
    }

    /// The first real paragraph of the article, trimmed to a couple of lines.
    static func summary(of html: String) -> String {
        for paragraph in TournamentParser.captures(#"(?s)<p[^>]*>(.*?)</p>"#, in: html) {
            let text = TournamentParser.clean(paragraph)
            if text.count >= 40 {
                return text.count > 240 ? String(text.prefix(237)).trimmingCharacters(in: .whitespaces) + "…" : text
            }
        }
        return ""
    }

    private static let pubDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()

    static func date(_ text: String) -> Date? {
        pubDateFormatter.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Collects `<item>`s from an RSS document (title, link, description, author, date).
private final class RSSItemCollector: NSObject, XMLParserDelegate {
    struct Item {
        var title = ""
        var link = ""
        var description = ""
        var creator = ""
        var pubDate = ""
    }

    private(set) var items: [Item] = []
    private var current: Item?
    private var text = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        if elementName == "item" { current = Item() }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        guard current != nil else { return }
        switch elementName {
        case "title": current?.title = text
        case "link": current?.link = text
        case "description": current?.description = text
        case "dc:creator": current?.creator = text
        case "pubDate": current?.pubDate = text
        case "item":
            if let current { items.append(current) }
            current = nil
        default: break
        }
    }
}

// MARK: - Mock

/// Synthetic articles for demo mode and UI tests (no network).
struct MockNewsService: NewsProviding {
    static let articles: [NewsArticle] = [
        NewsArticle(title: "Sample Scholastic Open Draws Record Field",
                    link: URL(string: "https://new.uschess.org/news/sample-scholastic-open-record-field")!,
                    author: "Sample Staff",
                    published: Date.now.addingTimeInterval(-3 * 3_600),
                    imageURLs: [],
                    summary: "More than 400 players from 12 states filled the ballroom for the Sample Scholastic Open, the largest field in the event's history."),
        NewsArticle(title: "Tactics Tuesday: A Sample Back-Rank Trick",
                    link: URL(string: "https://new.uschess.org/news/tactics-tuesday-sample-back-rank")!,
                    author: "Sample Coach",
                    published: Date.now.addingTimeInterval(-2 * 86_400),
                    imageURLs: [],
                    summary: "White to move and win. The defender's king has no escape square, and one quiet move makes the difference."),
        NewsArticle(title: "Registration Opens for the Sample Grade Nationals",
                    link: URL(string: "https://new.uschess.org/news/sample-grade-nationals-registration")!,
                    author: "Sample Staff",
                    published: Date.now.addingTimeInterval(-6 * 86_400),
                    imageURLs: [],
                    summary: "Players in kindergarten through 12th grade can now register for the Sample Grade Nationals, held over three days in December."),
        NewsArticle(title: "Sample Club Wins State Team Championship",
                    link: URL(string: "https://new.uschess.org/news/sample-club-state-team")!,
                    author: "Sample Reporter",
                    published: Date.now.addingTimeInterval(-12 * 86_400),
                    imageURLs: [],
                    summary: "A late comeback in the final round gave the Sample Chess Club its first state team title since 2019."),
    ]

    func articles(_ topic: NewsTopic) async throws -> [NewsArticle] {
        try await Task.sleep(for: .milliseconds(250))
        return topic == .all ? Self.articles : Array(Self.articles.prefix(2))
    }

    func body(of article: NewsArticle) async throws -> String {
        try await Task.sleep(for: .milliseconds(200))
        return "\(article.summary)\n\n**Final standings**\n1 · Ava Sterling · 4.0\n2 · Alex Rivera · 3.0\n\nFull results and photos are on [US Chess](<\(article.link.absoluteString)>)."
    }
}

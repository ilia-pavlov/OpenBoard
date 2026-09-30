import Foundation

/// News comes from the US Chess website's RSS feeds: the main feed plus topic
/// feeds, merged, newest first. Articles themselves open on the website.
protocol NewsProviding: Sendable {
    /// Articles from the last `NewsFeeds.window`, newest first, without duplicates.
    func latest() async throws -> [NewsArticle]
}

struct LiveNewsService: NewsProviding {
    func latest() async throws -> [NewsArticle] {
        // A topic feed that fails is skipped; only all of them failing is an error.
        let results = await withTaskGroup(of: Result<[NewsArticle], Error>.self) { group in
            for url in NewsFeeds.urls {
                group.addTask {
                    do { return .success(NewsParser.articles(fromRSS: try await fetch(url))) }
                    catch { return .failure(error) }
                }
            }
            var all: [Result<[NewsArticle], Error>] = []
            for await result in group { all.append(result) }
            return all
        }
        let feeds = results.compactMap { try? $0.get() }
        if feeds.isEmpty, case .failure(let error)? = results.first { throw error }
        return NewsParser.merge(feeds.flatMap { $0 })
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

/// Caches the merged list for 15 minutes and serves the last copy offline.
final class CachedNewsService: Sendable {
    let upstream: any NewsProviding
    let cache: CacheStore

    private static let key = "news-latest"
    private static let ttl: TimeInterval = 15 * 60

    init(upstream: any NewsProviding, cache: CacheStore) {
        self.upstream = upstream
        self.cache = cache
    }

    func latest(force: Bool = false) async throws -> [NewsArticle] {
        if !force, let entry = await cache.read([NewsArticle].self, key: Self.key, ttl: Self.ttl), entry.isFresh {
            return entry.value
        }
        do {
            let fresh = try await upstream.latest()
            await cache.write(fresh, key: Self.key)
            return fresh
        } catch {
            if let stale = await cache.read([NewsArticle].self, key: Self.key) { return stale.value }
            throw error
        }
    }

    /// Last stored list regardless of age, for the offline error state.
    func cachedLatest() async -> ([NewsArticle], Date)? {
        await cache.read([NewsArticle].self, key: Self.key).map { ($0.value, $0.updatedAt) }
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

    /// One list from several feeds: duplicates dropped, only the recent window,
    /// newest first.
    static func merge(_ articles: [NewsArticle], now: Date = .now) -> [NewsArticle] {
        var seen = Set<String>()
        return articles
            .filter { seen.insert($0.id).inserted }
            .filter { ($0.published.map { now.timeIntervalSince($0) } ?? .infinity) <= NewsFeeds.window }
            .sorted { ($0.published ?? .distantPast) > ($1.published ?? .distantPast) }
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
                           imageURL: leadImage(in: item.description),
                           summary: summary(of: item.description))
    }

    /// The article's first photo. The feed lazy-loads images: `src` is an empty SVG
    /// placeholder and the real (site-relative) address is in `data-src`/`srcset`.
    static func leadImage(in html: String) -> URL? {
        for tag in TournamentParser.captures(#"(<img[^>]*>)"#, in: html) {
            let candidates = ["data-src", "srcset", "data-srcset", "src"].compactMap { attribute in
                TournamentParser.captures(#"\#(attribute)="([^"]+)""#, in: tag).first
            }
            guard let raw = candidates.first(where: { !$0.hasPrefix("data:") }) else { continue }
            let path = TournamentParser.unescape(raw.split(separator: " ").first.map(String.init) ?? raw)
            if path.contains("/files/"), let url = URL(string: path, relativeTo: site)?.absoluteURL {
                return url
            }
        }
        return nil
    }

    /// The first real paragraph of the article, trimmed to a few lines.
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
        article("Sample Scholastic Open Draws Record Field", hoursAgo: 3,
                "More than 400 players from 12 states filled the ballroom for the Sample Scholastic Open, the largest field in the event's history."),
        article("Tactics Tuesday: A Sample Back-Rank Trick", hoursAgo: 30,
                "White to move and win. The defender's king has no escape square, and one quiet move makes the difference."),
        article("Registration Opens for the Sample Grade Nationals", hoursAgo: 100,
                "Players in kindergarten through 12th grade can now register for the Sample Grade Nationals, held over three days in December."),
        article("Sample Club Wins State Team Championship", hoursAgo: 12 * 24,
                "A late comeback in the final round gave the Sample Chess Club its first state team title since 2019."),
        article("Five Endgames Every Scholastic Player Should Know", hoursAgo: 20 * 24,
                "From the lucida position to the square of the pawn, a sample coach picks the endings that decide junior games."),
    ]

    private static func article(_ title: String, hoursAgo: Double, _ summary: String) -> NewsArticle {
        let slug = title.lowercased().filter { $0.isLetter || $0 == " " }.replacingOccurrences(of: " ", with: "-")
        return NewsArticle(title: title,
                           link: URL(string: "https://new.uschess.org/news/\(slug)")!,
                           author: "Sample Staff",
                           published: Date.now.addingTimeInterval(-hoursAgo * 3_600),
                           imageURL: nil,
                           summary: summary)
    }

    func latest() async throws -> [NewsArticle] {
        try await Task.sleep(for: .milliseconds(250))
        return Self.articles
    }
}

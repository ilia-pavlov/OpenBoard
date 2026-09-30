import Foundation

/// News comes from the US Chess website, which has no news API:
///
/// - **Articles** from the news listing, `/news?page=N`: about 15 per page,
///   newest first, each with a photo, title and teaser (no dates).
/// - **Dates** from the sitemap (`lastmod` per page; the publish date, or a few
///   days later when an article was edited) and, exactly, from the main RSS
///   feed for the newest ten.
///
/// Articles themselves open on the website.
protocol NewsProviding: Sendable {
    /// One page of the listing, without dates.
    func listing(page: Int) async throws -> NewsPage
    /// Best-known publish date per article path ("/news/…").
    func dates() async throws -> [String: Date]
}

struct LiveNewsService: NewsProviding {
    private static let site = URL(string: "https://new.uschess.org")!

    func listing(page: Int) async throws -> NewsPage {
        var components = URLComponents(url: Self.site.appending(path: "news"), resolvingAgainstBaseURL: false)!
        if page > 0 { components.queryItems = [URLQueryItem(name: "page", value: String(page))] }
        let html = String(decoding: try await fetch(components.url!), as: UTF8.self)
        let articles = NewsParser.listing(html)
        return NewsPage(articles: articles, hasMore: !articles.isEmpty && html.contains("page=\(page + 1)"))
    }

    func dates() async throws -> [String: Date] {
        // The sitemap index names its pages; each lists ~2,000 URLs with lastmod.
        let index = String(decoding: try await fetch(Self.site.appending(path: "sitemap.xml")), as: UTF8.self)
        let pages = TournamentParser.captures(#"<loc>([^<]+sitemap\.xml\?page=\d+)</loc>"#, in: index)
            .compactMap(URL.init(string:))
        let sitemaps = await withTaskGroup(of: String?.self) { group in
            for page in pages {
                group.addTask { try? String(decoding: await fetch(page), as: UTF8.self) }
            }
            var all: [String] = []
            for await text in group { if let text { all.append(text) } }
            return all
        }
        guard !sitemaps.isEmpty else { throw RatingsError.notFound }
        var dates = sitemaps.reduce(into: [String: Date]()) { dates, sitemap in
            dates.merge(NewsParser.sitemapDates(sitemap)) { first, _ in first }
        }
        // Exact dates for the newest ten.
        if let rss = try? await fetch(Self.site.appending(path: "rss.xml")) {
            dates.merge(NewsParser.rssDates(rss)) { _, exact in exact }
        }
        return dates
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

/// Adds caching and dates. The first page is kept 15 minutes, older pages and
/// the date index 12 hours; the last copy is served when the site is down.
final class CachedNewsService: Sendable {
    let upstream: any NewsProviding
    let cache: CacheStore

    private static let firstPageTTL: TimeInterval = 15 * 60
    private static let olderTTL: TimeInterval = 12 * 60 * 60

    init(upstream: any NewsProviding, cache: CacheStore) {
        self.upstream = upstream
        self.cache = cache
    }

    /// A listing page with publish dates filled in.
    func page(_ number: Int, force: Bool = false) async throws -> NewsPage {
        async let listing = cached(key: "news-page-\(number)",
                                   ttl: number == 0 ? Self.firstPageTTL : Self.olderTTL,
                                   force: force) { try await self.upstream.listing(page: number) }
        // Dates are a nicety: a page still shows if they can't be loaded.
        let dates = (try? await cached(key: "news-dates", ttl: Self.olderTTL, force: force && number == 0) {
            try await self.upstream.dates()
        }) ?? [:]
        var page = try await listing
        for index in page.articles.indices where page.articles[index].published == nil {
            page.articles[index].published = dates[page.articles[index].link.path()]
        }
        return page
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

// MARK: - Parsing

enum NewsParser {
    static let site = URL(string: "https://new.uschess.org")!

    /// Articles on a listing page, in order. Each has one title link; its photo
    /// is the last image before the title and its teaser the first body field
    /// after it. Only the main column is read (the sidebar lists other things).
    static func listing(_ html: String) -> [NewsArticle] {
        var main = html
        if let start = html.range(of: "layout__region--first") {
            let end = html.range(of: "layout__region--second", range: start.upperBound..<html.endIndex)
            main = String(html[start.upperBound..<(end?.lowerBound ?? html.endIndex)])
        }
        // Walk title by title: the piece before a title holds its photo, the
        // piece after holds its teaser.
        let pieces = main.components(separatedBy: "views-field-title")
        var seen = Set<String>()
        var articles: [NewsArticle] = []
        for index in pieces.indices.dropFirst() {
            let piece = pieces[index]
            guard let match = TournamentParser.captureGroups(
                    ##"^[^>]*>\s*<h\d[^>]*>\s*<a href="(/news/[^"#?]+)"[^>]*>(.*?)</a>"##, in: piece).first,
                  seen.insert(match[0]).inserted,
                  let link = URL(string: match[0], relativeTo: site)?.absoluteURL else { continue }
            let title = TournamentParser.clean(match[1])
            guard !title.isEmpty else { continue }
            articles.append(NewsArticle(title: title,
                                        link: link,
                                        published: nil,
                                        imageURL: photo(in: pieces[index - 1]),
                                        summary: teaser(in: piece)))
        }
        return articles
    }

    /// The last listing photo in `html` (the one belonging to the next title).
    private static func photo(in html: String) -> URL? {
        let sources = TournamentParser.captures(#"<img[^>]+src="(/sites/[^"]+)""#, in: html)
        return sources.last.flatMap { URL(string: TournamentParser.unescape($0), relativeTo: site)?.absoluteURL }
    }

    private static func teaser(in html: String) -> String {
        guard let body = TournamentParser.capture(#"views-field-body.*?field-content">(.*?)(?:<a |</div>|</span>)"#,
                                                  in: html) else { return "" }
        return TournamentParser.clean(body).replacingOccurrences(of: "Read More »", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// "/news/…" → lastmod, from one sitemap page.
    static func sitemapDates(_ xml: String) -> [String: Date] {
        let formatter = ISO8601DateFormatter()
        var dates: [String: Date] = [:]
        for pair in TournamentParser.captureGroups(#"<loc>[^<]*?(/news/[^<]+)</loc>\s*<lastmod>([^<]+)</lastmod>"#,
                                                   in: xml) {
            if let date = formatter.date(from: pair[1]) { dates[pair[0]] = date }
        }
        return dates
    }

    /// "/news/…" → exact publish date, from the RSS feed (newest ten).
    static func rssDates(_ data: Data) -> [String: Date] {
        let collector = RSSItemCollector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.parse()
        var dates: [String: Date] = [:]
        for item in collector.items {
            guard let url = URL(string: item.link.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let date = pubDateFormatter.date(from: item.pubDate.trimmingCharacters(in: .whitespacesAndNewlines))
            else { continue }
            dates[url.path()] = date
        }
        return dates
    }

    /// The listing is newest first, but an edited article's sitemap date is the
    /// edit date. Cap each date at the one above it so the order and "3 days
    /// ago" labels stay truthful; an article with no date takes the one above.
    static func settleDates(_ articles: [NewsArticle]) -> [NewsArticle] {
        var ceiling: Date?
        return articles.map { article in
            var article = article
            let date = [article.published, ceiling].compactMap { $0 }.min()
            article.published = date
            ceiling = date
            return article
        }
    }

    private static let pubDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()
}

/// Collects `<item>` links and dates from an RSS document.
private final class RSSItemCollector: NSObject, XMLParserDelegate {
    struct Item {
        var link = ""
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

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        guard current != nil else { return }
        switch elementName {
        case "link": current?.link = text
        case "pubDate": current?.pubDate = text
        case "item":
            if let current { items.append(current) }
            current = nil
        default: break
        }
    }
}

// MARK: - Mock

/// Synthetic articles for demo mode and UI tests (no network): three pages
/// reaching back about four months.
struct MockNewsService: NewsProviding {
    private static let titles = [
        "Sample Scholastic Open Draws Record Field", "Tactics Tuesday: A Sample Back-Rank Trick",
        "Registration Opens for the Sample Grade Nationals", "Sample Club Wins State Team Championship",
        "Five Endgames Every Scholastic Player Should Know", "Sample Girls Championship Crowns New Champion",
        "Wednesday Workout: Sample Knight Forks", "Sample Coach Named Educator of the Year",
    ]

    private static let pageSize = 8

    private static func article(_ index: Int) -> NewsArticle {
        let title = "\(titles[index % titles.count])\(index >= titles.count ? " (\(index / titles.count + 1))" : "")"
        let slug = title.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }
            .replacingOccurrences(of: " ", with: "-")
        return NewsArticle(title: title,
                           link: URL(string: "https://new.uschess.org/news/\(slug)")!,
                           published: nil,
                           imageURL: nil,
                           summary: "A sample story for demo mode: results, photos and quotes appear here on the real site.")
    }

    func listing(page: Int) async throws -> NewsPage {
        try await Task.sleep(for: .milliseconds(250))
        let range = (page * Self.pageSize)..<((page + 1) * Self.pageSize)
        return NewsPage(articles: range.map(Self.article), hasMore: page < 2)
    }

    func dates() async throws -> [String: Date] {
        (0..<(3 * Self.pageSize)).reduce(into: [:]) { dates, index in
            dates[Self.article(index).link.path()] = Date.now.addingTimeInterval(-Double(index) * 5 * 86_400 - 3 * 3_600)
        }
    }
}

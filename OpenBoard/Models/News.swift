import Foundation

// MARK: - US Chess news (new.uschess.org)

/// One news article from the US Chess website's RSS feeds. Articles open on
/// the website itself; the app only lists them.
struct NewsArticle: Identifiable, Codable, Sendable, Hashable {
    var id: String { link.absoluteString }
    var title: String
    var link: URL
    var author: String?
    var published: Date?
    /// The article's lead photo, when it has one.
    var imageURL: URL?
    /// The opening paragraph as plain text.
    var summary: String
}

enum NewsFeeds {
    /// Each feed carries only its 10 newest articles, and the main one covers about
    /// two weeks. Merging it with the topic feeds (Drupal taxonomy terms, each
    /// checked to return articles) gives about 30 articles over two months.
    static let urls: [URL] = {
        let site = URL(string: "https://new.uschess.org")!
        let topics = [391, 361, 291, 60, 335, 637, 635, 304] // scholastics, national events,
        // top Americans, women, annotated games, Tactics Tuesday, kids, international
        return [site.appending(path: "rss.xml")]
            + topics.map { site.appending(path: "taxonomy/term/\($0)/feed") }
    }()

    /// Topic feeds reach back years; the list keeps what's recent.
    static let window: TimeInterval = 60 * 86_400
}

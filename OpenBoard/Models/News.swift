import Foundation

// MARK: - US Chess news (new.uschess.org)

/// One news article from the US Chess website's RSS feeds.
struct NewsArticle: Identifiable, Codable, Sendable, Hashable {
    var id: String { link.absoluteString }
    var title: String
    var link: URL
    var author: String?
    var published: Date?
    /// Photos in the article, in order; the first is the lead image.
    var imageURLs: [URL]
    /// The opening paragraph as plain text, for the list.
    var summary: String

    var imageURL: URL? { imageURLs.first }
}

/// The site's topic feeds (`/taxonomy/term/{id}/feed`), each checked to
/// return articles. `all` is the main feed.
enum NewsTopic: String, CaseIterable, Identifiable, Codable, Sendable {
    case all, scholastic, nationalEvents, topAmericans, women, games, tactics, kids, podcast, international

    var id: Self { self }

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .scholastic: String(localized: "Scholastic")
        case .nationalEvents: String(localized: "National events")
        case .topAmericans: String(localized: "Top Americans")
        case .women: String(localized: "Women")
        case .games: String(localized: "Annotated games")
        case .tactics: String(localized: "Tactics Tuesday")
        case .kids: String(localized: "Kids")
        case .podcast: String(localized: "Podcast")
        case .international: String(localized: "International")
        }
    }

    /// Drupal taxonomy term ID of the topic; nil for the main feed.
    var termID: Int? {
        switch self {
        case .all: nil
        case .scholastic: 391
        case .nationalEvents: 361
        case .topAmericans: 291
        case .women: 60
        case .games: 335
        case .tactics: 637
        case .kids: 635
        case .podcast: 289
        case .international: 304
        }
    }

    var feedURL: URL {
        let site = URL(string: "https://new.uschess.org")!
        return termID.map { site.appending(path: "taxonomy/term/\($0)/feed") } ?? site.appending(path: "rss.xml")
    }
}

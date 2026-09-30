import Foundation

// MARK: - US Chess news (new.uschess.org)

/// One news article. Articles open on the website itself; the app lists them.
struct NewsArticle: Identifiable, Codable, Sendable, Hashable {
    var id: String { link.absoluteString }
    var title: String
    var link: URL
    /// Publish date: exact for the newest articles (RSS), otherwise from the
    /// sitemap, settled so it's never newer than the article above it.
    var published: Date?
    /// The listing's 350×200 photo.
    var imageURL: URL?
    /// The listing's teaser: the article's opening lines.
    var summary: String

    /// The same photo at 750×400, for the large card. The site renders any
    /// image style on request, with or without the style's token.
    var largeImageURL: URL? {
        imageURL.flatMap {
            URL(string: $0.absoluteString.replacingOccurrences(of: "350x200_scale_and_smart_crop",
                                                               with: "750x400_scale_and_smart_crop"))
        }
    }
}

/// One page of the site's news listing (`/news?page=N`, about 15 articles).
struct NewsPage: Codable, Sendable, Hashable {
    var articles: [NewsArticle]
    var hasMore: Bool
}

/// How far back the News tab reaches.
enum NewsRange: String, CaseIterable, Identifiable, Sendable {
    case all, week, twoWeeks, month, threeMonths, year

    var id: Self { self }

    var title: String {
        switch self {
        case .week: String(localized: "This week")
        case .twoWeeks: String(localized: "14 days")
        case .month: String(localized: "1 month")
        case .threeMonths: String(localized: "3 months")
        case .year: String(localized: "1 year")
        case .all: String(localized: "All")
        }
    }

    /// The oldest date shown; nil for all.
    func cutoff(from now: Date = .now, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        return switch self {
        case .week: calendar.date(byAdding: .day, value: -7, to: today)
        case .twoWeeks: calendar.date(byAdding: .day, value: -14, to: today)
        case .month: calendar.date(byAdding: .month, value: -1, to: today)
        case .threeMonths: calendar.date(byAdding: .month, value: -3, to: today)
        case .year: calendar.date(byAdding: .year, value: -1, to: today)
        case .all: nil
        }
    }
}

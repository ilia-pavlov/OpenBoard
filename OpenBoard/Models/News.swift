import Foundation

// MARK: - News (new.uschess.org and kasparovchessfoundation.org)

/// Who published an article.
enum NewsSource: String, CaseIterable, Sendable {
    case usChess, kasparov

    var name: String {
        switch self {
        case .usChess: String(localized: "US Chess")
        case .kasparov: String(localized: "Kasparov Chess Foundation")
        }
    }

    /// For the source filter.
    var shortName: String {
        switch self {
        case .usChess: String(localized: "US Chess")
        case .kasparov: String(localized: "Kasparov Foundation")
        }
    }
}

/// One news article. Articles open on the publisher's website; the app lists them.
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

    /// Told apart by the link, so cached articles need no new field.
    var source: NewsSource {
        link.host()?.hasSuffix("kasparovchessfoundation.org") == true ? .kasparov : .usChess
    }

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

/// The News tab's one feed: US Chess articles in listing order, with Kasparov
/// Chess Foundation articles slotted in by date.
enum NewsFeed {
    /// While the US Chess listing still has pages to load, only KCF articles no
    /// older than its oldest loaded article are shown, so the feed never jumps
    /// past a stretch of US Chess news that hasn't loaded yet.
    static func merge(
        _ usChess: [NewsArticle],
        kasparov: [NewsArticle],
        complete: Bool
    ) -> [NewsArticle] {
        let floor = usChess.last?.published
        var extra = kasparov.filter { article in
            if complete { return true }
            guard let floor, let published = article.published else { return false }
            return published >= floor
        }[...]
        var feed: [NewsArticle] = []
        for article in usChess {
            while let next = extra.first,
                  (next.published ?? .distantPast) > (article.published ?? .distantPast) {
                feed.append(next)
                extra = extra.dropFirst()
            }
            feed.append(article)
        }
        return feed + extra
    }
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

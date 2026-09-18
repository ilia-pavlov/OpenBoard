import Foundation

// MARK: - Upcoming tournaments (US Chess Tournament Life Announcements)

/// One row of the US Chess "Upcoming Tournaments" search.
struct TournamentListing: Identifiable, Codable, Sendable, Hashable {
    /// Site path of the announcement, e.g. "/ica-glen-rock-quads-112".
    let id: String
    var name: String
    var location: String      // "Glen Rock, New Jersey"
    var organizer: String
    var summary: String
    /// Banner line, e.g. "Grand Prix, Enhanced Grand Prix" (empty for most events).
    var banner: String
    var startDate: Date?
    var endDate: Date?
    /// Weekly/monthly series listed as one long date range.
    var isRecurring: Bool
}

/// Full announcement for the detail screen.
struct TournamentDetail: Codable, Sendable, Hashable {
    let id: String
    var name: String
    var startDate: Date?
    var endDate: Date?
    var venueName: String?
    var street: String?
    var city: String?
    var state: String?
    var postalCode: String?
    var latitude: Double?
    var longitude: Double?
    var isOnline: Bool
    var isFIDERated: Bool
    var banner: [String]
    var organizerName: String?
    var organizerEmail: String?
    var organizerPhone: String?
    var organizerWebsite: URL?
    /// Best guess at the registration link found in the announcement text.
    var registrationURL: URL?
    /// Announcement body as plain text (paragraphs and "• " bullets).
    var announcement: String
    var links: [URL]

    var pageURL: URL? { URL(string: "https://new.uschess.org" + id) }

    var addressLine: String? {
        let cityLine = [city, [state, postalCode].compactMap { $0 }.joined(separator: " ")]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        let parts = [street, cityLine].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// A major event from the US Chess "Plan Ahead Calendar": national championships
/// and events with $5,000+ guaranteed prizes, listed nationwide.
struct MajorEvent: Identifiable, Codable, Sendable, Hashable {
    var id: String { "\(year)-\(dates)-\(name)" }
    var year: Int
    var dates: String        // "November 25-29"
    var name: String         // "US Masters ($25,000 Guaranteed)"
    var city: String
    var state: String
    var isNationalChampionship: Bool
    var startDate: Date?

    /// Name without the prize-fund note, for searching announcements.
    var searchName: String {
        name.replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Search filters

enum SearchRadius: Int, CaseIterable, Identifiable, Codable, Sendable {
    case mi25 = 25, mi50 = 50, mi100 = 100, mi200 = 200
    var id: Int { rawValue }
    var title: String { "\(rawValue) mi" }
}

enum UpcomingWindow: CaseIterable, Identifiable, Sendable {
    case any, weekend, month, threeMonths
    var id: Self { self }

    var title: String {
        switch self {
        case .any: String(localized: "Any time")
        case .weekend: String(localized: "This weekend")
        case .month: String(localized: "Next 30 days")
        case .threeMonths: String(localized: "Next 3 months")
        }
    }
    var chipTitle: String { self == .any ? String(localized: "When") : title }

    /// Inclusive date range, or nil for any time.
    func range(from now: Date = .now, calendar: Calendar = .current) -> ClosedRange<Date>? {
        let today = calendar.startOfDay(for: now)
        func days(_ n: Int) -> Date { calendar.date(byAdding: .day, value: n, to: today)! }
        switch self {
        case .any:
            return nil
        case .weekend:
            // Today through the coming Sunday (weekday 1).
            let weekday = calendar.component(.weekday, from: today)
            let untilSunday = (8 - weekday) % 7
            return today...days(untilSunday)
        case .month:
            return today...days(30)
        case .threeMonths:
            return today...days(92)
        }
    }
}

enum TournamentKind: CaseIterable, Identifiable, Sendable {
    case any, scholastic, quads, grandPrix
    var id: Self { self }

    var title: String {
        switch self {
        case .any: String(localized: "Any type")
        case .scholastic: String(localized: "Scholastic")
        case .quads: String(localized: "Quads")
        case .grandPrix: String(localized: "Grand Prix")
        }
    }
    var chipTitle: String { self == .any ? String(localized: "Type") : title }

    func matches(_ listing: TournamentListing) -> Bool {
        let text = "\(listing.name) \(listing.summary) \(listing.banner)".lowercased()
        switch self {
        case .any:
            return true
        case .scholastic:
            return ["scholastic", "k-12", "k-8", "k-5", "k-3", "grade", "kids", "youth", "junior", "school"]
                .contains { text.contains($0) }
        case .quads:
            return text.contains("quad")
        case .grandPrix:
            return text.contains("grand prix")
        }
    }
}

extension TournamentListing {
    /// Whether the listing falls inside `range` (recurring series match if they overlap it).
    func occurs(in range: ClosedRange<Date>?) -> Bool {
        guard let range else { return true }
        guard let start = startDate else { return false }
        let end = endDate ?? start
        return start <= range.upperBound && end >= range.lowerBound
    }
}

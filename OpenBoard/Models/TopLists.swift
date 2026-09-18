import Foundation

// MARK: - US Chess Top 100 lists (monthly, by rating type / age / gender)

enum TopListRating: String, CaseIterable, Identifiable, Codable, Sendable {
    case regular = "R", quick = "Q", blitz = "B"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .regular: String(localized: "Regular")
        case .quick: String(localized: "Quick")
        case .blitz: String(localized: "Blitz")
        }
    }
}

struct TopListDefinition: Identifiable, Codable, Sendable, Hashable {
    let id: String            // "Regular8", "WomensRegular10", "QuickUnder13"
    var name: String          // "Age 8", "Girls Age 10", "Under Age 13"
    var rating: TopListRating
    var minAge: Int?
    var maxAge: Int?
    var isWomen: Bool

    /// Age group without the gender word: "Age 8", "Under Age 13", "Overall".
    var ageGroup: String {
        var label = name
        // "Quick Under Age 13", "Blitz Age 50 and over", "Girls Age 8", "Women" …
        for prefix in ["Quick ", "Blitz ", "Top Women ", "Women ", "Girls "] where label.hasPrefix(prefix) {
            label = String(label.dropFirst(prefix.count))
        }
        if label == "Women" || label.isEmpty { return String(localized: "Overall") }
        return label.replacingOccurrences(of: "and Over", with: "and over")
    }

    /// Short label for badges: "Age 8", "Girls Age 10", "US Top 100", "Top Women".
    var badgeLabel: String {
        switch (ageGroup == String(localized: "Overall"), isWomen) {
        case (true, false): String(localized: "US Top 100")
        case (true, true): String(localized: "Top Women")
        case (false, true): name.hasPrefix("Girls") ? name : "Women \(ageGroup)"
        case (false, false): ageGroup
        }
    }

    /// Sort key: youngest first, then Under-N groups, overall, and seniors.
    var sortKey: Int {
        if let maxAge, minAge == nil, maxAge < 10 { return maxAge }         // "7 and under"
        if let minAge, let maxAge, minAge == maxAge { return minAge }       // single age
        if let maxAge, minAge == nil { return 100 + maxAge }               // Under N
        if minAge == nil, maxAge == nil { return 200 }                     // Overall
        return 300 + (minAge ?? 0)                                         // 50+, 65+
    }
}

struct TopListEntry: Identifiable, Codable, Sendable, Hashable {
    let id: String            // member ID
    var rank: Int
    var name: String
    var state: String?
    var rating: Int
}

struct TopList: Identifiable, Codable, Sendable, Hashable {
    var definition: TopListDefinition
    var reportDate: Date?
    var entries: [TopListEntry]
    var id: String { definition.id }
}

/// Where a player appears on a list — what a badge shows.
struct TopListRank: Codable, Sendable, Hashable {
    var definition: TopListDefinition
    var rank: Int
    var reportDate: Date?

    var monthLabel: String? {
        reportDate?.formatted(.dateTime.month(.abbreviated).year())
    }
}

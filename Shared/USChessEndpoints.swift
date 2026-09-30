import Foundation

// The one place the app's US Chess endpoints, query parameters and HTML parser
// patterns are written. The app builds every URL and parses every page from
// these constants, and `scripts/api_contract_check.py` reads THIS FILE to
// monitor the same endpoints twice a day (see README → API contract monitor).
//
// Keep the format the script can read:
//   - one constant per line: `static let name = #"value"#` (always a raw string)
//   - grouped in the nested enums below (Ratings, Site, Params, Patterns)
//   - placeholders in braces: {memberID}, {eventID}, {section}, {listID}, {path}
// Adding an endpoint here without a check in the script fails the monitor.

enum USChess {
    /// ratings-api.uschess.org (MUIR). Paths are relative to `base`.
    enum Ratings {
        static let base = #"https://ratings-api.uschess.org/api/v1"#
        static let member = #"members/{memberID}"#
        static let memberSections = #"members/{memberID}/sections"#
        static let memberGames = #"members/{memberID}/games"#
        static let memberSearch = #"members"#
        static let maxRanks = #"members/max-ranks"#
        static let ratedEvent = #"rated-events/{eventID}"#
        static let sectionStandings = #"rated-events/{eventID}/sections/{section}/standings"#
        static let topListCatalog = #"top-players"#
        static let topList = #"top-players/{listID}"#
    }

    /// new.uschess.org pages (HTML, or Drupal's JSON view of a page).
    enum Site {
        static let base = #"https://new.uschess.org"#
        static let upcomingSearch = #"upcoming-tournaments"#
        static let announcement = #"{path}"#
        static let planAheadCalendar = #"plan-ahead-calendar"#
    }

    /// Query parameter names (the API ignores unknown ones silently).
    enum Params {
        static let fuzzy = #"Fuzzy"#
        static let size = #"Size"#
        static let offset = #"Offset"#
        static let ratingSource = #"RatingSource"#
        static let radius = #"field_geofield_proximity[value]"#
        static let origin = #"field_geofield_proximity[source_configuration][origin_address]"#
        static let keyword = #"combine"#
        static let page = #"page"#
        static let format = #"_format"#
    }

    /// Regular expressions (and one split marker) the HTML parsers depend on.
    enum Patterns {
        static let listingRow = #"<div class="views-row">"#
        static let listingPath = #"<h3 class="title3"><a href="([^"]+)""#
        static let listingName = #"<h3 class="title3"><a [^>]*>(.*?)</a>"#
        static let listingDate = #"<time datetime="(\d{4}-\d{2}-\d{2})"#
        static let listingAddress = #"<div class="address">(.*?)</div>"#
        static let listingOrganizer = #"<div class="organizer-name">(.*?)</div>"#
        static let listingSummary = #"<div class="information">(.*?)</div>"#
        static let listingBanner = #"<div class="banner-line h4">(.*?)</div>"#
        static let pagerPage = #"[?&amp;]page=(\d+)"#
        static let planAheadEntry = #"<h2[^>]*>(.*?)</h2>|<p[^>]*>\s*<strong>([^<]*\d[^<]*):?\s*</strong>(.*?)</p>"#
    }

    /// `template` with each {placeholder} filled in.
    static func fill(_ template: String, _ values: [String: String] = [:]) -> String {
        values.reduce(template) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
    }
}

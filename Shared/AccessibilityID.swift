/// Accessibility identifiers shared by the app and the UI tests (this file is
/// compiled into both targets), so tests find elements by ID only and an ID
/// can't drift between the two.
enum AccessibilityID {
    // MARK: Screens (root containers — used to assert a screen is showing)

    enum Screen {
        static let myCard = "screen-my-card"
        static let profile = "screen-profile"
        static let ratingHistory = "screen-rating-history"
        static let crosstable = "screen-crosstable"
        static let search = "screen-search"
        static let events = "screen-events"
        static let tournament = "screen-tournament"
        static let topLists = "screen-top-lists"
        static let watching = "screen-watching"
    }

    // MARK: Shared

    static let copyMemberID = "copy-member-id"
    static let topBadges = "top-badges"
    /// One Top 100 badge on a profile, e.g. `topBadge("Regular9")`.
    static func topBadge(_ listID: String) -> String { "top-badge-\(listID)" }
    static let backButton = "BackButton" // system navigation back button

    /// A segmented-control item, e.g. `segment("profile", "history")`.
    static func segment(_ control: String, _ value: String) -> String { "segment-\(control)-\(value)" }
    /// A filter chip (dropdown), e.g. `filter("result")`.
    static func filter(_ name: String) -> String { "filter-\(name)" }
    /// One option inside a filter chip's menu, e.g. `filterOption("result", "down")`.
    static func filterOption(_ name: String, _ value: String) -> String { "filter-\(name)-\(value)" }

    // MARK: My Card & profile

    static let heroRatingCard = "hero-rating-card"
    static let profileRatingCard = "profile-rating-card"
    static let watchToggle = "watch-toggle"
    static func historyEvent(_ eventID: String) -> String { "history-event-\(eventID)" }

    // MARK: Rating History

    static func ratingHistoryEvent(_ eventID: String) -> String { "rating-history-event-\(eventID)" }

    // MARK: Crosstable

    static let sectionMenu = "section-menu"
    static func sectionOption(_ index: Int) -> String { "section-option-\(index)" }
    static func standing(_ memberID: String) -> String { "standing-\(memberID)" }
    static func viewFullProfile(_ memberID: String) -> String { "view-full-profile-\(memberID)" }

    // MARK: Search & Top 100

    static func searchResult(_ memberID: String) -> String { "search-result-\(memberID)" }
    static let browseTop100 = "browse-top-100"
    static func topListEntry(_ memberID: String) -> String { "toplist-\(memberID)" }

    // MARK: Events & upcoming tournaments

    static let upcomingLocation = "upcoming-location"
    static func upcoming(_ listingID: String) -> String { "upcoming-\(listingID)" }
    static let tournamentRegister = "tournament-register"
    static let tournamentAddress = "tournament-address"
    static let tournamentDirections = "tournament-directions"

    // MARK: Watching

    static func watchRow(_ memberID: String) -> String { "watch-row-\(memberID)" }
}

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
        static let news = "screen-news"
        static let newsArticle = "screen-news-article"
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
    static let bestWins = "best-wins"
    // News
    static func newsTopic(_ topic: String) -> String { "news-topic-\(topic)" }
    static func newsArticle(_ link: String) -> String { "news-article-\(link)" }
    static let bestWinsInfo = "best-wins-info"
    static let bestWinsInfoPopover = "best-wins-info-popover"
    /// A row of My Card's Recent events.
    static func recentEvent(_ eventID: String) -> String { "recent-event-\(eventID)" }
    /// One row of Best wins, keyed by the opponent's member ID.
    static func bestWin(_ opponentID: String) -> String { "best-win-\(opponentID)" }
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
    static let browseJoinUSChess = "browse-join-us-chess"
    static func topListEntry(_ memberID: String) -> String { "toplist-\(memberID)" }

    // MARK: Events & upcoming tournaments

    static let upcomingLocation = "upcoming-location"
    static func upcoming(_ listingID: String) -> String { "upcoming-\(listingID)" }
    static let tournamentRegister = "tournament-register"
    static let tournamentSave = "tournament-save"
    static let copyAnnouncement = "copy-announcement"
    /// One saved tournament row in Watching, e.g. `savedTournament("/sample-saturday-quads")`.
    static func savedTournament(_ id: String) -> String { "saved-tournament-\(id)" }
    static let tournamentAddress = "tournament-address"
    static let tournamentDirections = "tournament-directions"

    // MARK: Watching

    static func watchRow(_ memberID: String) -> String { "watch-row-\(memberID)" }
}

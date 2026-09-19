import XCTest

/// Base class for UI tests: launches the app offline (mock data) with the
/// requested options and exposes every screen object, so a test reads as a chain:
///
///     launch(.demoSeed)
///     myCard.assertOnScreen().tapHeroCard()
///     ratingHistory.assertOnScreen().assertEvent(Sample.eventID)
class Runner: XCTestCase {
    /// Launch arguments understood by the app (see `AppEnvironment`).
    enum LaunchOption {
        /// Synthetic watchlist so My Card / Watching have content.
        case demoSeed
        /// Open straight on a screen (tabs have no IDs, so tests start on the tab they need).
        case screen(Screen, arg: String? = nil)
        /// Pre-expand the followed player's crosstable row.
        case expandHighlight
        /// Seed the appearance preference; "default" clears it (fresh install).
        case appearance(String)
    }

    enum Screen: String {
        case search, events, watchlist, profile, event, history
    }

    /// Synthetic IDs from `MockRatingsService` / `MockTournamentsService`.
    enum Sample {
        static let playerID = "90000001"      // Alex Rivera, primary in demo mode
        static let eventID = "900000000001"   // Sample Scholastic Open 2026
        static let lossEventID = "900000000002"
        static let rivalID = "90000011"       // Maya Brooks, rank 3 in the sample event
        static let girlsListID = "WomensRegular8"
        static let age9ListID = "Regular9"
        static let upcomingID = "/sample-saturday-quads"   // Saturday Rated Quads
        static let upcomingID2 = "/sample-garden-state-open" // Garden State Open (2 days)
    }

    @MainActor private(set) lazy var app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches the app with mock data (never the network) plus `options`.
    @MainActor
    @discardableResult
    func launch(_ options: LaunchOption...) -> Self {
        var arguments = ["-mock"]
        for option in options {
            switch option {
            case .demoSeed:
                arguments.append("-demoSeed")
            case .screen(let screen, let arg):
                arguments += ["-screen", screen.rawValue]
                if let arg { arguments += ["-screenArg", arg] }
            case .expandHighlight:
                arguments.append("-expandHighlight")
            case .appearance(let value):
                arguments += ["-appearance", value]
            }
        }
        app.launchArguments = arguments
        app.launch()
        return self
    }

    // MARK: - Screens

    @MainActor var myCard: MyCardView { MyCardView(app) }
    @MainActor var profile: ProfileView { ProfileView(app) }
    @MainActor var ratingHistory: RatingHistoryView { RatingHistoryView(app) }
    @MainActor var crosstable: CrosstableView { CrosstableView(app) }
    @MainActor var search: SearchView { SearchView(app) }
    @MainActor var topLists: TopListsView { TopListsView(app) }
    @MainActor var events: EventsView { EventsView(app) }
    @MainActor var tournament: TournamentDetailView { TournamentDetailView(app) }
    @MainActor var watching: WatchingView { WatchingView(app) }
}

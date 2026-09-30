import Testing
import Foundation
@testable import OpenBoard

/// Live checks against the real US Chess services, through the app's own
/// services and parsers: if an endpoint moves, renames a field or changes its
/// HTML, these fail where the app would break.
///
/// Off by default (normal CI and local runs stay offline). The API monitor
/// workflow turns them on twice a day with `TEST_RUNNER_LIVE_API=1`; to run
/// them locally:
///
///     TEST_RUNNER_LIVE_API=1 xcodebuild test … -only-testing:OpenBoardTests/LiveAPITests
///
/// Subjects are public and long-lived: GM Fabiano Caruana and the 2025 North
/// American Open. Tests run one at a time to stay well under the API's rate
/// limit (~100 requests a minute).
@Suite("Live US Chess API",
       .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["LIVE_API"] == "1"),
       .timeLimit(.minutes(5)))
struct LiveAPITests {
    static let playerID = "12743305"      // Fabiano Caruana
    static let eventID = "202512300043"   // 35th North American Open (Dec 2025), 9 sections

    let ratings = LiveRatingsService()
    let tournaments = LiveTournamentsService()

    // MARK: - ratings-api.uschess.org

    /// members/{id}, members/{id}/sections (paged), members/max-ranks
    @Test func playerProfile() async throws {
        let player = try await ratings.player(id: Self.playerID)
        #expect(player.name.localizedCaseInsensitiveContains("Caruana"))
        #expect((player.ratings.regular?.value ?? 0) > 2000)
        #expect(!player.events.isEmpty, "no rated events decoded from members/{id}/sections")
        #expect(player.events.contains { $0.regular?.pre != nil && $0.regular?.post != nil },
                "no event carries a pre → post regular rating")
        #expect(player.ranking?.overall != nil, "national rank missing (max-ranks or rank fields)")
        #expect(player.ratingHistory.count > 10)
    }

    /// members?Fuzzy= and the 8-digit ID path of search
    @Test func search() async throws {
        let byName = try await ratings.search("caruana")
        #expect(byName.contains { $0.id == Self.playerID }, "Fuzzy name search didn't find the player")
        let byID = try await ratings.search(Self.playerID)
        #expect(byID.first?.id == Self.playerID)
    }

    /// rated-events/{id} and rated-events/{id}/sections/{n}/standings
    @Test func crosstable() async throws {
        let event = try await ratings.event(id: Self.eventID)
        #expect(event.name.localizedCaseInsensitiveContains("North American Open"))
        #expect(event.date != nil)
        #expect(event.sections.count >= 5, "section list shrank: \(event.sections.count)")
        let players = event.sections.flatMap(\.players)
        #expect(players.count > 500)
        #expect(players.contains { !$0.rounds.isEmpty }, "standings lost their round-by-round results")
        #expect(players.contains { $0.regular?.pre != nil }, "standings lost their pre-event ratings")
    }

    /// top-players and top-players/{id}
    @Test func topLists() async throws {
        let definitions = try await ratings.topListDefinitions()
        #expect(definitions.count > 20, "Top 100 catalog shrank: \(definitions.count)")
        let list = try #require(definitions.first { $0.rating == .regular })
        let top = try await ratings.topList(list)
        #expect(top.entries.count >= 50)
        #expect(top.entries.allSatisfy { !$0.name.isEmpty && $0.rating > 0 })
    }

    /// members/{id}/games?RatingSource=R (Best wins), then one section's
    /// standings for opponents' pre-event ratings
    @Test func bestWinsSources() async throws {
        let record = try await ratings.regularWins(memberID: Self.playerID)
        #expect(record.gameCount > 50)
        let win = try #require(record.wins.first, "no Regular wins decoded from members/{id}/games")
        #expect(!win.opponentName.isEmpty && !win.eventID.isEmpty)
        let ratingsInSection = try await ratings.regularPreRatings(eventID: win.eventID, section: win.section)
        #expect(ratingsInSection[win.opponentID] != nil,
                "the opponent's pre-event rating isn't in that section's standings")
    }

    // MARK: - new.uschess.org (HTML and JSON pages, no API)

    /// upcoming-tournaments search (HTML) and one announcement (?_format=json)
    @Test func upcomingTournaments() async throws {
        let listings = try await tournaments.upcoming(near: "Somerville, NJ", radius: .mi50)
        #expect(listings.count >= 5, "search near Somerville, NJ found only \(listings.count)")
        #expect(listings.contains { $0.startDate != nil }, "listing dates stopped parsing")
        #expect(listings.allSatisfy { !$0.name.isEmpty && $0.id.hasPrefix("/") })

        let listing = try #require(listings.first { !$0.isRecurring } ?? listings.first)
        let detail = try await tournaments.detail(id: listing.id)
        #expect(!detail.name.isEmpty)
        #expect(detail.startDate != nil)
        #expect(!detail.announcement.isEmpty, "announcement body is empty")
        #expect(detail.city != nil || detail.isOnline, "address fields stopped parsing")
    }

    /// plan-ahead-calendar (HTML)
    @Test func majorEvents() async throws {
        let events = try await tournaments.majorEvents()
        #expect(events.count >= 5, "Plan Ahead Calendar parsed only \(events.count) events")
        #expect(events.allSatisfy { !$0.name.isEmpty && !$0.city.isEmpty })
        #expect(events.contains { $0.startDate != nil })
    }
}

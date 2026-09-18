import Testing
import Foundation
@testable import OpenBoard

@Suite("Upcoming tournaments parsing")
struct UpcomingTournamentTests {
    private func ymd(_ date: Date?) -> String? {
        date.map { Calendar.current.dateComponents([.year, .month, .day], from: $0) }
            .map { String(format: "%04d-%02d-%02d", $0.year!, $0.month!, $0.day!) }
    }

    @Test func parsesSearchResults() throws {
        let listings = TournamentParser.listings(from: try fixtureText("upcoming_search", "html"))
        #expect(listings.count == 3)

        let dca = try #require(listings.first { $0.id.hasPrefix("/dca-somerset") })
        #expect(dca.name == "DCA Somerset County Scholastic (K-8 Grades) September 20th, 2026")
        #expect(dca.location == "Somerville, New Jersey")
        #expect(dca.organizer == "Dash Chess Academy")
        #expect(ymd(dca.startDate) == "2026-09-20")
        #expect(!dca.isRecurring)
        #expect(TournamentKind.scholastic.matches(dca))

        let weekly = try #require(listings.first { $0.id.contains("weekly-uscf") })
        #expect(weekly.isRecurring)
        #expect(ymd(weekly.endDate) == "2050-12-31")
    }

    @Test func readsLastPageFromPager() throws {
        #expect(TournamentParser.lastPageIndex(in: try fixtureText("upcoming_search", "html")) == 3)
        #expect(TournamentParser.lastPageIndex(in: "<div>no pager</div>") == 0)
    }

    @Test func sortsDatedFirstAndDropsEndedAndDuplicates() {
        func listing(_ id: String, start: Int, end: Int? = nil, recurring: Bool = false) -> TournamentListing {
            TournamentListing(id: id, name: id, location: "", organizer: "", summary: "", banner: "",
                              startDate: MockTournamentsService.date(start),
                              endDate: MockTournamentsService.date(end ?? start), isRecurring: recurring)
        }
        let sorted = TournamentParser.dedupedAndSorted([
            listing("weekly", start: -300, end: 3000, recurring: true),
            listing("later", start: 10),
            listing("ended", start: -5),
            listing("soon", start: 1),
            listing("soon", start: 1),
        ])
        #expect(sorted.map(\.id) == ["soon", "later", "weekly"])
    }

    @Test func parsesAnnouncementJSON() throws {
        let detail = try TournamentParser.detail(id: "/dca", json: try fixture("tla_node"))
        #expect(detail.venueName == "Knights of Columbus, Somerville")
        #expect(detail.addressLine == "495 E Main St, Somerville, NJ 08876")
        #expect(detail.latitude == 40.564642)
        #expect(detail.organizerName == "Dash Chess Academy")
        #expect(detail.registrationURL?.host() == "forms.gle") // the organizer's Google Form
        #expect(detail.announcement.contains("Tournament Format: Swiss"))
        #expect(detail.announcement.contains("• "))
        #expect(!detail.announcement.contains("<"))
    }

    @Test func parsesPlanAheadCalendar() throws {
        let events = TournamentParser.majorEvents(from: try fixtureText("plan_ahead", "html"))
        let masters = try #require(events.first { $0.name.hasPrefix("US Masters") })
        #expect(masters.year == 2026)
        #expect(masters.dates == "November 25-29")
        #expect(masters.city == "Charlotte")
        #expect(masters.state == "NC")
        #expect(masters.searchName == "US Masters")
        #expect(ymd(masters.startDate) == "2026-11-25")

        let worldOpen = try #require(events.first { $0.name == "World Open" })
        #expect(worldOpen.year == 2027)
        #expect(ymd(worldOpen.startDate) == "2027-06-30") // "June 30-July 4"
        #expect(events.contains { $0.isNationalChampionship && $0.state == "PA" })
    }

    @Test func weekendWindowEndsOnSunday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let friday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))!
        let range = UpcomingWindow.weekend.range(from: friday, calendar: calendar)!
        #expect(calendar.component(.weekday, from: range.upperBound) == 1) // Sunday
        #expect(calendar.dateComponents([.day], from: range.lowerBound, to: range.upperBound).day == 2)
    }
}

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
        #expect(detail.announcement.contains("**Tournament Format: Swiss**"))
        #expect(detail.announcement.contains("• **🏆 1st Place** Trophy in each Section"))
        #expect(detail.announcement.contains("[Register here](<https://forms.gle/7qqwd7Bpb6AH19mMA>)"))
        #expect(!detail.announcement.contains("<p"))
    }

    @Test func formatsAnnouncementForDisplay() throws {
        let detail = try TournamentParser.detail(id: "/dca", json: try fixture("tla_node"))
        let text = detail.formattedAnnouncement
        let plain = String(text.characters)
        #expect(!plain.contains("**"))
        #expect(!plain.contains("]("))

        let register = try #require(text.range(of: "Register here"))
        #expect(text[register].link?.host() == "forms.gle")
        let heading = try #require(text.range(of: "Tournament Format"))
        #expect(text[heading].inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
        let email = try #require(text.range(of: "dashchessacademy@dashnmore.com"))
        #expect(text[email].link?.scheme == "mailto") // bare email detected

        let copied = detail.copyableAnnouncement
        #expect(copied.contains("Register here (https://forms.gle/7qqwd7Bpb6AH19mMA)"))
        #expect(copied.contains("contact DCA via dashchessacademy@dashnmore.com"))
        #expect(!copied.contains("**"))
    }

    @Test(arguments: [
        ("<p><strong>Fee&nbsp;</strong>$40</p>", "**Fee** $40"),
        ("<p>Use <em>G/25</em>; d5</p>", "Use *G/25*; d5"),
        ("<h3>Prizes</h3><ul><li>1st</li></ul>", "**Prizes**\n\n• 1st"),
        ("<p>a_b * c [x]</p>", #"a\_b \* c \[x\]"#),
        ("<h2><a href=\"https://x.org\"><strong><u>K-12 Swiss</u></strong></a></h2>", "**[K-12 Swiss](<https://x.org>)**"),
        ("<p><a href=\"https://x.org\">Pay <strong>now</strong></a></p>", "[Pay now](<https://x.org>)"),
        ("<p><a href=\"javascript:x\">Click</a></p>", "Click"),
        ("<p><a href=\"https://x.org\"><img src=\"a.png\"></a>Text</p>", "Text"),
    ])
    func convertsAnnouncementHTML(html: String, markdown: String) {
        #expect(TournamentParser.markdown(fromHTML: html) == markdown)
    }

    /// 10 mi for dense cities up to 500 mi for big states; the stored raw value
    /// (miles) is unchanged, so a distance saved by an older build still loads.
    @Test func distanceOptionsCoverCitiesAndBigStates() throws {
        #expect(SearchRadius.allCases.map(\.rawValue) == [10, 25, 50, 100, 200, 300, 500])
        #expect(SearchRadius(rawValue: 50) == .mi50)
        #expect(SearchRadius.mi500.title == "500 mi")
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

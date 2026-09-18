import Foundation

/// Upcoming tournaments come from the US Chess website (new.uschess.org), not the
/// ratings API: the "Upcoming Tournaments" search (Tournament Life Announcements,
/// with distance search), each announcement's JSON, and the "Plan Ahead Calendar"
/// of major events. None of these are an official API, so parsing is defensive
/// and lives in `TournamentParser` where it is unit-tested against saved pages.
protocol TournamentsProviding: Sendable {
    /// Announcements within `radius` miles of `origin` (a city or ZIP), soonest first.
    func upcoming(near origin: String, radius: SearchRadius) async throws -> [TournamentListing]
    func detail(id: String) async throws -> TournamentDetail
    func majorEvents() async throws -> [MajorEvent]
    /// Finds the announcement for a Plan Ahead entry, if the organizer posted one.
    func findAnnouncement(for event: MajorEvent) async throws -> TournamentListing?
}

struct LiveTournamentsService: TournamentsProviding {
    static let site = URL(string: "https://new.uschess.org")!
    /// The search returns 30 per page; cap how many pages one search pulls.
    static let maxPages = 6

    func upcoming(near origin: String, radius: SearchRadius) async throws -> [TournamentListing] {
        let query = [
            URLQueryItem(name: "field_geofield_proximity[value]", value: String(radius.rawValue)),
            URLQueryItem(name: "field_geofield_proximity[source_configuration][origin_address]", value: origin),
        ]
        let first = try await page(query, page: 0)
        let lastPage = min(TournamentParser.lastPageIndex(in: first), Self.maxPages - 1)
        var listings = TournamentParser.listings(from: first)
        if lastPage > 0 {
            let rest = try await withThrowingTaskGroup(of: (Int, [TournamentListing]).self) { group in
                for n in 1...lastPage {
                    group.addTask { (n, TournamentParser.listings(from: try await page(query, page: n))) }
                }
                return try await group.reduce(into: [:]) { $0[$1.0] = $1.1 }
            }
            for n in 1...lastPage { listings += rest[n] ?? [] }
        }
        return TournamentParser.dedupedAndSorted(listings)
    }

    func detail(id: String) async throws -> TournamentDetail {
        guard var components = URLComponents(url: Self.site.appending(path: id), resolvingAgainstBaseURL: false)
        else { throw RatingsError.badURL }
        components.queryItems = [URLQueryItem(name: "_format", value: "json")]
        guard let url = components.url else { throw RatingsError.badURL }
        let data = try await fetch(url)
        return try TournamentParser.detail(id: id, json: data)
    }

    func majorEvents() async throws -> [MajorEvent] {
        let html = try await text(Self.site.appending(path: "plan-ahead-calendar"))
        return TournamentParser.majorEvents(from: html)
    }

    func findAnnouncement(for event: MajorEvent) async throws -> TournamentListing? {
        let html = try await page([URLQueryItem(name: "combine", value: event.searchName)], page: 0)
        return TournamentParser.bestMatch(for: event, in: TournamentParser.listings(from: html))
    }

    // MARK: - HTTP

    private func page(_ query: [URLQueryItem], page: Int) async throws -> String {
        guard var components = URLComponents(url: Self.site.appending(path: "upcoming-tournaments"),
                                             resolvingAgainstBaseURL: false)
        else { throw RatingsError.badURL }
        components.queryItems = query + (page > 0 ? [URLQueryItem(name: "page", value: String(page))] : [])
        guard let url = components.url else { throw RatingsError.badURL }
        return try await text(url)
    }

    private func text(_ url: URL) async throws -> String {
        String(decoding: try await fetch(url), as: UTF8.self)
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(AppEnvironment.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw http.statusCode == 404 ? RatingsError.notFound : RatingsError.httpStatus(http.statusCode)
            }
            return data
        } catch let error as RatingsError {
            throw error
        } catch {
            throw RatingsError.offline(underlying: error.localizedDescription)
        }
    }
}

// MARK: - Parsing

enum TournamentParser {
    // MARK: Search results page

    static func listings(from html: String) -> [TournamentListing] {
        html.components(separatedBy: #"<div class="views-row">"#).dropFirst().compactMap { row in
            guard let path = capture(#"<h3 class="title3"><a href="([^"]+)""#, in: row),
                  let name = capture(#"<h3 class="title3"><a [^>]*>(.*?)</a>"#, in: row) else { return nil }
            let times = captures(#"<time datetime="(\d{4}-\d{2}-\d{2})"#, in: row)
            let isRange = row.contains("date-recur-occurrences")
            let start = times.first.flatMap(day)
            let end = times.count > 1 ? day(times[times.count - 1]) : start
            // A range spanning more than two weeks is a recurring series, not a multi-day event.
            let isRecurring = isRange && (start.flatMap { s in end.map { $0.timeIntervalSince(s) > 14 * 86_400 } } ?? false)
            return TournamentListing(
                id: path,
                name: clean(name),
                // Organizers type stray commas/spaces: "Princeton, , New Jersey", "Millburn , New Jersey".
                location: clean(capture(#"<div class="address">(.*?)</div>"#, in: row) ?? "")
                    .replacingOccurrences(of: #"\s*,(\s*,)*\s*"#, with: ", ", options: .regularExpression),
                organizer: clean(capture(#"<div class="organizer-name">(.*?)</div>"#, in: row) ?? ""),
                summary: clean(capture(#"<div class="information">(.*?)</div>"#, in: row) ?? ""),
                banner: clean(capture(#"<div class="banner-line h4">(.*?)</div>"#, in: row) ?? ""),
                startDate: start,
                endDate: end,
                isRecurring: isRecurring
            )
        }
    }

    /// Highest `page=N` in the pager (0 when there's a single page).
    static func lastPageIndex(in html: String) -> Int {
        captures(#"[?&amp;]page=(\d+)"#, in: html).compactMap(Int.init).max() ?? 0
    }

    /// Dated events soonest first, then recurring series; duplicates across pages removed.
    static func dedupedAndSorted(_ listings: [TournamentListing]) -> [TournamentListing] {
        var seen = Set<String>()
        let today = Calendar.current.startOfDay(for: .now)
        let unique = listings.filter {
            seen.insert($0.id).inserted && ($0.endDate ?? $0.startDate ?? .distantFuture) >= today
        }
        return unique.sorted { a, b in
            if a.isRecurring != b.isRecurring { return !a.isRecurring }
            return (a.startDate ?? .distantFuture) < (b.startDate ?? .distantFuture)
        }
    }

    // MARK: Announcement JSON

    private struct NodeJSON: Decodable {
        struct Value<T: Decodable>: Decodable { let value: T? }
        struct DateRange: Decodable { let value: String?; let end_value: String? }
        struct Address: Decodable {
            let administrative_area: String?, locality: String?, postal_code: String?, address_line1: String?
        }
        struct Geo: Decodable { let lat: Double?; let lon: Double? }
        struct Link: Decodable { let uri: String? }

        let title: [Value<String>]?
        let body: [Value<String>]?
        let field_event_dates: [DateRange]?
        let field_event_location_name: [Value<String>]?
        let field_event_address: [Address]?
        let field_geofield: [Geo]?
        let field_online_event: [Value<Bool>]?
        let field_fide_rated: [Value<Bool>]?
        let field_banner_line: [Value<String>]?
        let field_organizer_name: [Value<String>]?
        let field_organizer_email_address: [Value<String>]?
        let field_organizer_phone_number: [Value<String>]?
        let field_organizer_website: [Link]?
    }

    static func detail(id: String, json: Data) throws -> TournamentDetail {
        let node = try JSONDecoder().decode(NodeJSON.self, from: json)
        let bodyHTML = node.body?.first?.value ?? ""
        let links = self.links(in: bodyHTML)
        let address = node.field_event_address?.first
        let website = node.field_organizer_website?.first?.uri.flatMap(URL.init(string:))
        return TournamentDetail(
            id: id,
            name: clean(node.title?.first?.value ?? ""),
            startDate: node.field_event_dates?.first?.value.flatMap(day),
            endDate: node.field_event_dates?.first?.end_value.flatMap(day),
            venueName: node.field_event_location_name?.first?.value.map(clean),
            street: address?.address_line1.map(clean),
            city: address?.locality.map(clean),
            state: address?.administrative_area,
            postalCode: address?.postal_code,
            latitude: node.field_geofield?.first?.lat,
            longitude: node.field_geofield?.first?.lon,
            isOnline: node.field_online_event?.first?.value ?? false,
            isFIDERated: node.field_fide_rated?.first?.value ?? false,
            banner: (node.field_banner_line ?? []).compactMap(\.value),
            organizerName: node.field_organizer_name?.first?.value.map(clean),
            organizerEmail: node.field_organizer_email_address?.first?.value,
            organizerPhone: node.field_organizer_phone_number?.first?.value,
            organizerWebsite: website,
            registrationURL: registrationLink(in: bodyHTML),
            announcement: plainText(fromHTML: bodyHTML),
            links: links
        )
    }

    /// The link in the announcement most likely to be the entry/registration form.
    static func registrationLink(in html: String) -> URL? {
        let anchors = captureGroups(#"<a [^>]*href="([^"]+)"[^>]*>(.*?)</a>"#, in: html)
        let hints = ["regist", "entry", "entries", "enter", "sign up", "signup", "sign-up",
                     "onlineregistration", "chessregister", "caissachess", "eventbrite",
                     "forms.gle", "docs.google.com/forms", "jotform", "payment"]
        for anchor in anchors {
            let haystack = (anchor[0] + " " + anchor[1]).lowercased()
            if hints.contains(where: haystack.contains),
               let url = URL(string: unescape(anchor[0])), url.scheme?.hasPrefix("http") == true {
                return url
            }
        }
        return nil
    }

    static func links(in html: String) -> [URL] {
        var seen = Set<String>()
        return captures(#"<a [^>]*href="(https?://[^"]+)""#, in: html)
            .map(unescape)
            .filter { seen.insert($0).inserted }
            .compactMap(URL.init(string:))
    }

    /// Paragraphs and list items as plain text; tags stripped, entities decoded.
    static func plainText(fromHTML html: String) -> String {
        var text = html
        for (pattern, replacement) in [(#"(?i)<br\s*/?>"#, "\n"),
                                       // Organizers put each line in its own <p>; headings get a gap.
                                       (#"(?i)</(p|div|tr)>"#, "\n"),
                                       (#"(?i)</h\d>"#, "\n\n"),
                                       (#"(?i)<li[^>]*>"#, "• "),
                                       (#"(?i)</li>"#, "\n"),
                                       (#"<[^>]+>"#, "")] {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        text = unescape(text)
        text = text.replacingOccurrences(of: #"[ \t\u{00A0}]+"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #" *\n *"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Plan Ahead Calendar

    static func majorEvents(from html: String) -> [MajorEvent] {
        var events: [MajorEvent] = []
        var year: Int?
        // Walk year headings and entries in document order.
        let tokens = captureGroups(#"<h2[^>]*>(.*?)</h2>|<p[^>]*>\s*<strong>([^<]*\d[^<]*):?\s*</strong>(.*?)</p>"#, in: html)
        for token in tokens {
            if !token[0].isEmpty {
                year = Int(clean(token[0]).prefix(4)) ?? year
                continue
            }
            guard let year else { continue }
            let dates = clean(token[1]).trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            var rest = clean(token[2])
            let isNational = rest.contains("(N)")
            rest = rest.replacingOccurrences(of: "(N)", with: "").trimmingCharacters(in: .whitespaces)
            var parts = rest.components(separatedBy: ", ")
            guard parts.count >= 3, !dates.isEmpty else { continue }
            let state = parts.removeLast().trimmingCharacters(in: .whitespaces)
            let city = parts.removeLast().trimmingCharacters(in: .whitespaces)
            events.append(MajorEvent(year: year, dates: dates, name: parts.joined(separator: ", "),
                                     city: city, state: state, isNationalChampionship: isNational,
                                     startDate: startDate(dates, year: year)))
        }
        return events
    }

    /// "November 25-29" / "June 30-July 4" → the first day in `year`.
    static func startDate(_ dates: String, year: Int) -> Date? {
        guard let first = capture(#"^([A-Za-z]+ \d{1,2})"#, in: dates) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM d yyyy"
        return formatter.date(from: "\(first) \(year)")
    }

    /// The search result whose title shares the most words with the event name.
    static func bestMatch(for event: MajorEvent, in listings: [TournamentListing]) -> TournamentListing? {
        func words(_ s: String) -> Set<String> {
            Set(s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 })
        }
        let target = words(event.searchName)
        guard !target.isEmpty else { return nil }
        let scored = listings.map { ($0, Double(words($0.name).intersection(target).count) / Double(target.count)) }
        return scored.filter { $0.1 >= 0.6 }.max { $0.1 < $1.1 }?.0
    }

    // MARK: Helpers

    private static func day(_ iso: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(iso.prefix(10)))
    }

    static func clean(_ html: String) -> String {
        unescape(html.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func unescape(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        for (entity, char) in [("&nbsp;", "\u{00A0}"), ("&quot;", "\""), ("&#039;", "'"), ("&#39;", "'"),
                               ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&ndash;", "–"),
                               ("&mdash;", "—"), ("&rsquo;", "’"), ("&lsquo;", "‘"), ("&ldquo;", "“"),
                               ("&rdquo;", "”"), ("&hellip;", "…"), ("&amp;", "&")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        // Numeric entities: &#8217; / &#x2019;
        while let range = out.range(of: #"&#(x?)([0-9A-Fa-f]+);"#, options: .regularExpression) {
            let token = String(out[range])
            let isHex = token.hasPrefix("&#x")
            let digits = token.dropFirst(isHex ? 3 : 2).dropLast()
            let scalar = UInt32(digits, radix: isHex ? 16 : 10).flatMap(Unicode.Scalar.init)
            out.replaceSubrange(range, with: scalar.map { String(Character($0)) } ?? "")
        }
        return out
    }

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
    }

    static func capture(_ pattern: String, in text: String) -> String? {
        captureGroups(pattern, in: text).first?.first
    }

    static func captures(_ pattern: String, in text: String) -> [String] {
        captureGroups(pattern, in: text).compactMap(\.first)
    }

    /// Every match's capture groups (unmatched groups are "").
    static func captureGroups(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = regex(pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (1..<max(match.numberOfRanges, 2)).map { i in
                let r = match.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
        }
    }
}

// MARK: - Mock

/// Synthetic data for previews, UI tests and `-mock` runs.
struct MockTournamentsService: TournamentsProviding {
    static func date(_ daysFromToday: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: daysFromToday, to: Calendar.current.startOfDay(for: .now))!
    }

    static let listings: [TournamentListing] = [
        TournamentListing(id: "/sample-scholastic-fall-classic", name: "Sample Scholastic Fall Classic (K-8)",
                          location: "Somerville, New Jersey", organizer: "Sample Chess Academy",
                          summary: "USCF rated scholastic Swiss, 4 rounds, G/25 d5. Trophies in every section.",
                          banner: "", startDate: date(2), endDate: date(2), isRecurring: false),
        TournamentListing(id: "/sample-saturday-quads", name: "Saturday Rated Quads",
                          location: "Princeton, New Jersey", organizer: "Sample Chess Club",
                          summary: "Three-round quads grouped by rating. G/30 d5.",
                          banner: "", startDate: date(9), endDate: date(9), isRecurring: false),
        TournamentListing(id: "/sample-garden-state-open", name: "Garden State Open",
                          location: "Edison, New Jersey", organizer: "Sample Chess Federation",
                          summary: "Five-round Swiss with Open, U1800 and U1200 sections. $2,000 prize fund.",
                          banner: "Grand Prix", startDate: date(20), endDate: date(21), isRecurring: false),
        TournamentListing(id: "/sample-friday-night-rapid", name: "Friday Night Rapid",
                          location: "New Brunswick, New Jersey", organizer: "Sample Chess Club",
                          summary: "Weekly rated rapid, every Friday at 7 pm.",
                          banner: "", startDate: date(-400), endDate: date(3000), isRecurring: true),
    ]

    func upcoming(near origin: String, radius: SearchRadius) async throws -> [TournamentListing] {
        try await Task.sleep(for: .milliseconds(250))
        return Self.listings
    }

    func detail(id: String) async throws -> TournamentDetail {
        try await Task.sleep(for: .milliseconds(200))
        guard let listing = Self.listings.first(where: { $0.id == id }) else { throw RatingsError.notFound }
        return TournamentDetail(
            id: id, name: listing.name, startDate: listing.startDate, endDate: listing.endDate,
            venueName: "Community Center", street: "495 E Main St", city: "Somerville", state: "NJ",
            postalCode: "08876", latitude: 40.5646, longitude: -74.5900, isOnline: false, isFIDERated: false,
            banner: listing.banner.isEmpty ? [] : [listing.banner],
            organizerName: listing.organizer, organizerEmail: "info@example.com", organizerPhone: "5555550100",
            organizerWebsite: URL(string: "https://example.com"),
            registrationURL: URL(string: "https://example.com/register"),
            announcement: "\(listing.summary)\n\nSections\n• Under 500\n• Under 1000\n• Open\n\nEntry fee: $40 by the Wednesday before.",
            links: [URL(string: "https://example.com/register")!])
    }

    func majorEvents() async throws -> [MajorEvent] {
        [MajorEvent(year: 2026, dates: "November 25-29", name: "US Masters ($25,000 Guaranteed)",
                    city: "Charlotte", state: "NC", isNationalChampionship: false, startDate: Self.date(60)),
         MajorEvent(year: 2026, dates: "December 11-13", name: "National K-12 Grade Championships",
                    city: "Orlando", state: "FL", isNationalChampionship: true, startDate: Self.date(80)),
         MajorEvent(year: 2027, dates: "June 30-July 4", name: "World Open",
                    city: "Philadelphia", state: "PA", isNationalChampionship: false, startDate: Self.date(280))]
    }

    func findAnnouncement(for event: MajorEvent) async throws -> TournamentListing? {
        Self.listings.first
    }
}

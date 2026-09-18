import SwiftUI
import MapKit

/// One upcoming tournament: when, where (map + directions + distance),
/// registration, the full announcement and organizer contacts.
struct TournamentDetailView: View {
    let id: String

    @Environment(AppModel.self) private var model
    @State private var state: Loadable<TournamentDetail> = .idle

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                ScrollView { SkeletonList().padding(16) }
            case .loaded(let detail):
                TournamentDetailContent(detail: detail)
            case .failed(let message, _, _):
                ScrollView {
                    ErrorCard(message: message, cachedAt: nil) {
                        Task { await load() }
                    }
                    .padding(16)
                }
            }
        }
        .background(Color.obBackground)
        .navigationTitle("Tournament")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = state.value?.pageURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url)
                }
            }
        }
        .task(id: id) { await load() }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await model.tournaments.detail(id: id))
        } catch {
            state = .failed(message: error.localizedDescription, cached: nil, cachedAt: nil)
        }
    }
}

struct TournamentDetailContent: View {
    let detail: TournamentDetail

    @Environment(AppModel.self) private var model
    @State private var showFullAnnouncement = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                registerButton
                if detail.latitude != nil || detail.addressLine != nil {
                    locationCard
                }
                if !detail.announcement.isEmpty {
                    announcementCard
                }
                organizerCard
                if let page = detail.pageURL {
                    Link(destination: page) {
                        Label("View on US Chess", systemImage: "arrow.up.forward.square")
                            .font(.footnote.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
            }
            .padding(16)
        }
        .accessibilityIdentifier(AccessibilityID.Screen.tournament)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.name)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let start = detail.startDate {
                Label(dateText(start), systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            let tags = detail.banner + (detail.isFIDERated ? ["FIDE rated"] : []) + (detail.isOnline ? ["Online"] : [])
            if !tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.obGold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.obGold.opacity(0.14), in: Capsule())
                    }
                }
            }
        }
    }

    private func dateText(_ start: Date) -> String {
        guard let end = detail.endDate, end > start else {
            return start.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        }
        // Long ranges are weekly/monthly series.
        if end.timeIntervalSince(start) > 14 * 86_400 { return "Recurring" }
        return Format.dateRange(start, end)
    }

    // MARK: - Register

    @ViewBuilder
    private var registerButton: some View {
        if let url = detail.registrationURL ?? detail.organizerWebsite {
            Link(destination: url) {
                Label(detail.registrationURL != nil ? "Register" : "Organizer website",
                      systemImage: detail.registrationURL != nil ? "pencil.and.list.clipboard" : "safari")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .accessibilityIdentifier(AccessibilityID.tournamentRegister)
        }
    }

    // MARK: - Location

    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = detail.latitude, let lon = detail.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Location")
            if let coordinate {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coordinate, latitudinalMeters: 1_500, longitudinalMeters: 1_500))) {
                    Marker(detail.venueName ?? detail.name, coordinate: coordinate)
                        .tint(Color.obGold)
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .allowsHitTesting(false)
            }
            VStack(alignment: .leading, spacing: 3) {
                if let venue = detail.venueName, !venue.isEmpty {
                    Text(venue)
                        .font(.subheadline.weight(.semibold))
                }
                if let address = detail.addressLine {
                    Text(address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityIdentifier(AccessibilityID.tournamentAddress)
                }
                if let miles = distanceMiles {
                    Text("About \(miles) mi from you")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let directions = directionsURL {
                Link(destination: directions) {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier(AccessibilityID.tournamentDirections)
            }
        }
        .padding(16)
        .obCard()
    }

    private var distanceMiles: Int? {
        guard let here = model.location.coordinate, let there = coordinate else { return nil }
        let meters = CLLocation(latitude: here.latitude, longitude: here.longitude)
            .distance(from: CLLocation(latitude: there.latitude, longitude: there.longitude))
        return Int((meters / 1_609.344).rounded())
    }

    /// Apple Maps driving directions to the venue.
    private var directionsURL: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")!
        if let coordinate {
            components.queryItems = [URLQueryItem(name: "daddr", value: "\(coordinate.latitude),\(coordinate.longitude)")]
        } else if let address = detail.addressLine {
            components.queryItems = [URLQueryItem(name: "daddr", value: address)]
        } else {
            return nil
        }
        return components.url
    }

    // MARK: - Announcement

    private var announcementCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Announcement")
            Text(detail.announcement)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(showFullAnnouncement ? nil : 12)
                .textSelection(.enabled)
            Button(showFullAnnouncement ? "Show less" : "Show more") {
                withAnimation(.snappy) { showFullAnnouncement.toggle() }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.obGold)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .obCard()
    }

    // MARK: - Organizer

    @ViewBuilder
    private var organizerCard: some View {
        let rows = organizerRows
        if detail.organizerName != nil || !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Organizer")
                if let name = detail.organizerName {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                }
                ForEach(rows, id: \.url) { row in
                    Link(destination: row.url) {
                        Label(row.title, systemImage: row.icon)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .obCard()
        }
    }

    private var organizerRows: [(title: String, icon: String, url: URL)] {
        var rows: [(String, String, URL)] = []
        if let email = detail.organizerEmail, let url = URL(string: "mailto:\(email)") {
            rows.append((email, "envelope", url))
        }
        if let phone = detail.organizerPhone {
            let digits = phone.filter(\.isNumber)
            if let url = URL(string: "tel:\(digits)") { rows.append((Format.phone(digits), "phone", url)) }
        }
        if let site = detail.organizerWebsite {
            rows.append((site.host() ?? site.absoluteString, "safari", site))
        }
        return rows
    }
}

// MARK: - Major event (Plan Ahead Calendar entry)

/// Shows the organizer's announcement when one can be found; otherwise the
/// calendar entry with links to look it up.
struct MajorEventView: View {
    let event: MajorEvent

    @Environment(AppModel.self) private var model
    @State private var state: Loadable<TournamentListing?> = .idle

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                ScrollView { SkeletonList().padding(16) }
            case .loaded(let match?):
                TournamentDetailView(id: match.id)
            case .loaded(nil), .failed:
                fallback
            }
        }
        .background(Color.obBackground)
        .navigationTitle("Tournament")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: event.id) {
            state = .loading
            do {
                state = .loaded(try await model.tournaments.findAnnouncement(for: event))
            } catch {
                state = .failed(message: error.localizedDescription, cached: nil, cachedAt: nil)
            }
        }
    }

    private var fallback: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MajorEventRow(event: event)
                Text("The organizer hasn't posted a full announcement on US Chess yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let search = webSearchURL {
                    Link(destination: search) {
                        Label("Search the web", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                }
                if let maps = mapsURL {
                    Link(destination: maps) {
                        Label("\(event.city), \(event.state) in Maps", systemImage: "map")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(16)
        }
    }

    private var webSearchURL: URL? {
        var components = URLComponents(string: "https://duckduckgo.com/")!
        components.queryItems = [URLQueryItem(name: "q", value: "\(event.searchName) \(event.year) chess \(event.city)")]
        return components.url
    }

    private var mapsURL: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [URLQueryItem(name: "q", value: "\(event.city), \(event.state)")]
        return components.url
    }
}

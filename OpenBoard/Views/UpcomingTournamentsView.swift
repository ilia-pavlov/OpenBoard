import SwiftUI

/// Events tab → Upcoming: US Chess tournaments near the user (distance, date and
/// type filters) or the nationwide list of major events.
struct UpcomingTournamentsSection: View {
    enum Scope: String, CaseIterable, Identifiable {
        case nearMe = "Near me"
        case majors = "Major events"
        var id: Self { self }
    }

    @Environment(AppModel.self) private var model
    @AppStorage("upcoming.radius") private var radius: SearchRadius = .mi50
    @State private var scope: Scope = .nearMe
    @State private var window: UpcomingWindow = .any
    @State private var kind: TournamentKind = .any
    @State private var listings: Loadable<[TournamentListing]> = .idle
    @State private var majors: Loadable<[MajorEvent]> = .idle
    @State private var editingLocation = false
    @State private var locationText = ""

    private var location: LocationProvider { model.location }

    var body: some View {
        VStack(spacing: 14) {
            Picker("Scope", selection: $scope) {
                ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch scope {
            case .nearMe: nearMe
            case .majors: majorEvents
            }
        }
        .task {
            if location.origin == nil, location.status == .idle { await location.useCurrentLocation() }
        }
        .task(id: searchKey) { await loadListings() }
        .task(id: scope) { if scope == .majors, majors.value == nil { await loadMajors() } }
        .alert("Search near", isPresented: $editingLocation) {
            TextField("City or ZIP", text: $locationText)
                .textContentType(.postalCode)
            Button("Search") { location.useManual(locationText) }
            Button("Use current location") { Task { await location.useCurrentLocation() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a city (\"Princeton, NJ\") or a ZIP code.")
        }
    }

    private var searchKey: String { "\(location.origin ?? "")|\(radius.rawValue)" }

    // MARK: - Near me

    @ViewBuilder
    private var nearMe: some View {
        locationRow

        HStack(spacing: 8) {
            FilterChip(title: radius.title, systemImage: "location.circle", active: true) {
                Picker("Distance", selection: $radius) {
                    ForEach(SearchRadius.allCases) { Text("Within \($0.title)").tag($0) }
                }
            }
            FilterChip(title: window.chipTitle, systemImage: "calendar", active: window != .any) {
                Picker("When", selection: $window) {
                    ForEach(UpcomingWindow.allCases) { Text($0.title).tag($0) }
                }
            }
            FilterChip(title: kind.chipTitle, systemImage: "checkerboard.rectangle", active: kind != .any) {
                Picker("Type", selection: $kind) {
                    ForEach(TournamentKind.allCases) { Text($0.title).tag($0) }
                }
            }
        }

        switch listings {
        case .idle, .loading:
            if location.origin != nil {
                SkeletonCard(height: 76)
                SkeletonCard(height: 76)
                SkeletonCard(height: 76)
            }
        case .loaded(let all):
            results(all)
        case .failed(let message, let cached, let cachedAt):
            ErrorCard(message: message, cachedAt: cachedAt) {
                Task { await loadListings() }
            }
            if let cached { results(cached) }
        }
    }

    private var locationRow: some View {
        Button {
            locationText = ""
            editingLocation = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: location.status == .denied ? "location.slash" : "location.fill")
                    .foregroundStyle(Color.obGold)
                VStack(alignment: .leading, spacing: 2) {
                    Text(locationTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let hint = locationHint {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("Change")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.obGold)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .obCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("upcoming-location")
    }

    private var locationTitle: String {
        switch location.status {
        case .locating: "Finding your location…"
        case .denied: "Location is off"
        case .failed: "Couldn't find your location"
        case .idle, .located: location.origin.map { "Near \($0)" } ?? "Choose a location"
        }
    }

    private var locationHint: String? {
        switch location.status {
        case .denied, .failed: "Tap to enter a city or ZIP"
        default: nil
        }
    }

    @ViewBuilder
    private func results(_ all: [TournamentListing]) -> some View {
        let range = window.range()
        let filtered = all.filter { $0.occurs(in: range) && kind.matches($0) }
        let dated = filtered.filter { !$0.isRecurring }
        let recurring = filtered.filter(\.isRecurring)

        if filtered.isEmpty {
            EmptyStateCard(systemImage: "magnifyingglass",
                           title: "No tournaments found",
                           message: "Try a larger distance or a different date or type.")
        } else {
            SectionLabel(text: "\(dated.count) \(dated.count == 1 ? "tournament" : "tournaments") within \(radius.title)")
                .padding(.top, 2)
            ForEach(dated) { listing in
                NavigationLink(value: Destination.upcomingTournament(id: listing.id)) {
                    TournamentListingRow(listing: listing)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("upcoming-\(listing.id)")
            }
            if !recurring.isEmpty {
                SectionLabel(text: "Weekly & recurring")
                    .padding(.top, 8)
                ForEach(recurring) { listing in
                    NavigationLink(value: Destination.upcomingTournament(id: listing.id)) {
                        TournamentListingRow(listing: listing)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Listings from US Chess Tournament Life Announcements.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
    }

    // MARK: - Major events

    @ViewBuilder
    private var majorEvents: some View {
        switch majors {
        case .idle, .loading:
            SkeletonCard(height: 64)
            SkeletonCard(height: 64)
        case .loaded(let events):
            majorList(events)
        case .failed(let message, let cached, let cachedAt):
            ErrorCard(message: message, cachedAt: cachedAt) {
                Task { await loadMajors() }
            }
            if let cached { majorList(cached) }
        }
    }

    @ViewBuilder
    private func majorList(_ events: [MajorEvent]) -> some View {
        let today = Calendar.current.startOfDay(for: .now)
        let upcoming = events.filter { ($0.startDate ?? .distantFuture) >= today }
        Text("National championships and events with $5,000+ guaranteed prizes, from the US Chess Plan Ahead Calendar.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        ForEach(upcoming) { event in
            NavigationLink(value: Destination.majorEvent(event)) {
                MajorEventRow(event: event)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading

    private func loadListings() async {
        guard let origin = location.origin else { return }
        listings = .loading
        do {
            listings = .loaded(try await model.tournaments.upcoming(near: origin, radius: radius))
        } catch is CancellationError {
            // A newer search replaced this one.
        } catch {
            listings = .failed(message: error.localizedDescription, cached: nil, cachedAt: nil)
        }
    }

    private func loadMajors() async {
        majors = .loading
        do {
            majors = .loaded(try await model.tournaments.majorEvents())
        } catch {
            majors = .failed(message: error.localizedDescription, cached: nil, cachedAt: nil)
        }
    }
}

// MARK: - Rows

struct TournamentListingRow: View {
    var listing: TournamentListing

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            DateBlock(date: listing.isRecurring ? nil : listing.startDate)
            VStack(alignment: .leading, spacing: 4) {
                Text(listing.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !listing.banner.isEmpty {
                    Text(listing.banner)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.obGold)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.obGold.opacity(0.14), in: Capsule())
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(14)
        .obCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [listing.location]
        if listing.isRecurring {
            parts.insert("Recurring", at: 0)
        } else if let start = listing.startDate, let end = listing.endDate, end > start {
            parts.insert(Format.dateRange(start, end), at: 0)
        }
        if !listing.organizer.isEmpty { parts.append(listing.organizer) }
        return parts.joined(separator: " · ")
    }
}

struct MajorEventRow: View {
    var event: MajorEvent

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            DateBlock(date: event.startDate)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text("\(event.dates), \(String(event.year)) · \(event.city), \(event.state)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if event.isNationalChampionship {
                    Label("National Championship", systemImage: "star.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.obGold)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(14)
        .obCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Calendar-page style "SEP / 20 / SUN" block; a repeat symbol when there's no single date.
/// Weekend days are tinted so Saturday/Sunday events stand out.
struct DateBlock: View {
    var date: Date?

    var body: some View {
        VStack(spacing: 0) {
            if let date {
                Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.obGold)
                Text(date.formatted(.dateTime.day()))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Calendar.current.isDateInWeekend(date) ? Color.obTeal : Color.secondary)
            } else {
                Image(systemName: "repeat")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.obTeal)
            }
        }
        .frame(width: 46, height: 62)
        .background(Color.obBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }
}

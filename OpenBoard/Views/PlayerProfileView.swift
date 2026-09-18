import SwiftUI
import SwiftData

struct PlayerProfileView: View {
    let memberID: String

    @Environment(AppModel.self) private var model
    @Query private var watched: [WatchedPlayer]
    @State private var state: Loadable<Player> = .idle
    @State private var segment: Segment = .ratings
    @State private var isWatching = false

    enum Segment: String, CaseIterable {
        case ratings = "Ratings"
        case history = "History"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch state {
                case .idle, .loading:
                    SkeletonList()
                case .loaded(let player):
                    loadedBody(player)
                case .failed(let message, let cached, let cachedAt):
                    ErrorCard(message: message, cachedAt: cachedAt) {
                        Task { await load(force: true) }
                    }
                    if let cached { loadedBody(cached) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .accessibilityIdentifier(AccessibilityID.Screen.profile)
        .background(Color.obBackground)
        .navigationTitle(state.value?.name ?? "Player")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let player = state.value, let shareImage = shareImage(player) {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: shareImage,
                              preview: SharePreview("\(player.name) — OpenBoard result", image: shareImage)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .task(id: memberID) {
            isWatching = model.isWatching(memberID)
            await load(force: false)
        }
        .refreshable { await load(force: true) }
    }

    // MARK: - Body

    @ViewBuilder
    private func loadedBody(_ player: Player) -> some View {
        header(player)

        Picker("Section", selection: $segment) {
            ForEach(Segment.allCases, id: \.self) { Text($0.rawValue).tag($0).accessibilityIdentifier(AccessibilityID.segment("profile", "\($0)")) }
        }
        .pickerStyle(.segmented)
        .padding(.vertical, 4)

        switch segment {
        case .ratings: ratingsBody(player)
        case .history: historyBody(player)
        }
    }

    private func header(_ player: Player) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                InitialsAvatar(name: player.name,
                               tint: isWatching ? .obGold : .obTeal,
                               size: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.name)
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                    HStack(spacing: 0) {
                        CopyableID(id: player.id)
                        Text(subtitle(player))
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    ClassChip(rating: player.ratings.regular?.value,
                              stateName: player.ranking?.stateName ?? player.state)
                    PlayerTopBadges(memberID: player.id)
                }
                Spacer()
            }

            Button {
                model.toggleWatch(player)
                isWatching.toggle()
            } label: {
                Label(isWatching ? "Watching" : "Watch",
                      systemImage: isWatching ? "heart.fill" : "heart")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isWatching ? Color.obGold : .primary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .sensoryFeedback(isWatching ? .success : .impact, trigger: isWatching)
            .accessibilityIdentifier(AccessibilityID.watchToggle)
        }
        .padding(.top, 8)
    }

    private func subtitle(_ player: Player) -> String {
        var parts: [String] = []
        if let state = player.state { parts.append(state) }
        parts.append("US Chess member")
        return " · " + parts.joined(separator: " · ")
    }

    // MARK: - Ratings segment

    @ViewBuilder
    private func ratingsBody(_ player: Player) -> some View {
        let liveRegular = player.events.first?.regular?.post

        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 16) {
                RatingHistoryLink(player: player, system: .regular) {
                    DualRatingCard(published: player.ratings.regular?.value,
                                   live: liveRegular,
                                   footnote: dualFootnote(player.ratings.regular),
                                   sparkline: player.ratingHistory,
                                   showsDisclosure: player.hasHistory(.regular))
                }
                .accessibilityIdentifier(AccessibilityID.profileRatingCard)
                HStack(spacing: 16) {
                    RatingHistoryLink(player: player, system: .quick) {
                        MiniRatingCard(label: "Quick", rating: player.ratings.quick, tint: .obTeal,
                                       showsDisclosure: player.hasHistory(.quick))
                    }
                    MiniRatingCard(label: "Blitz", rating: player.ratings.blitz, tint: .obTeal)
                }
                if hasOnlineRatings(player.ratings) {
                    HStack(spacing: 16) {
                        MiniRatingCard(label: "Online Reg", rating: player.ratings.onlineRegular, tint: .obTeal)
                        MiniRatingCard(label: "Online Quick", rating: player.ratings.onlineQuick, tint: .obTeal)
                    }
                }
            }
        }

        if let ranking = player.ranking {
            HStack(spacing: 16) {
                if let overall = ranking.overall {
                    StatCard(title: "National", value: "№ \(overall.rank.formatted())",
                             caption: "of \(overall.total.formatted())", systemImage: "flag.fill")
                }
                if let stateRank = ranking.state {
                    StatCard(title: ranking.stateName ?? "State", value: "№ \(stateRank.rank.formatted())",
                             caption: "of \(stateRank.total.formatted())",
                             systemImage: "mappin.and.ellipse", tint: .obTeal)
                }
            }
        }
    }

    private func dualFootnote(_ rating: Rating?) -> String? {
        guard let rating else { return nil }
        var parts: [String] = []
        if let floor = rating.floor { parts.append("FLOOR \(floor)") }
        if let games = rating.games { parts.append("\(games) GAMES") }
        if rating.isProvisional { parts.append("PROVISIONAL") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func hasOnlineRatings(_ ratings: Ratings) -> Bool {
        ratings.onlineRegular?.isRated == true || ratings.onlineQuick?.isRated == true
            || ratings.onlineBlitz?.isRated == true
    }

    // MARK: - History segment

    @ViewBuilder
    private func historyBody(_ player: Player) -> some View {
        if player.events.isEmpty {
            EmptyStateCard(systemImage: "calendar.badge.exclamationmark",
                           title: "No rated events yet",
                           message: "Results appear here as soon as US Chess rates an event.")
        } else {
            ForEach(player.events) { event in
                NavigationLink(value: Destination.event(id: event.id, highlight: player.id)) {
                    EventResultRow(event: event)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(AccessibilityID.historyEvent(event.id))
            }
        }
    }

    // MARK: - Share

    private func shareImage(_ player: Player) -> Image? {
        guard let event = player.events.first else { return nil }
        return ShareCardRenderer.render(ResultShareCard(
            playerName: player.name,
            eventName: event.name,
            placement: nil,
            score: event.score,
            delta: event.regular?.delta,
            newRating: event.regular?.post ?? player.ratings.regular?.value))
    }

    // MARK: - Loading

    private func load(force: Bool) async {
        if state.value == nil {
            if let (cached, _) = await model.service.cachedPlayer(id: memberID) {
                state = .loaded(cached)
            } else {
                state = .loading
            }
        }
        do {
            state = .loaded(try await model.service.player(id: memberID))
        } catch {
            let cached = await model.service.cachedPlayer(id: memberID)
            state = .failed(message: error.localizedDescription,
                            cached: cached?.0, cachedAt: cached?.1)
        }
    }
}

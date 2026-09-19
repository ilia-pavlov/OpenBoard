import SwiftUI
import SwiftData

struct MyCardView: View {
    @Environment(AppModel.self) private var model
    // Reactive: when the primary flag changes anywhere (e.g. "Make primary" in
    // the Watching tab), @Query republishes and this view re-renders. Reading a
    // computed fetch off AppModel is NOT observed and left My Card stale.
    @Query(filter: #Predicate<WatchedPlayer> { $0.isPrimary },
           sort: \WatchedPlayer.sortOrder) private var primaries: [WatchedPlayer]
    @State private var state: Loadable<Player> = .idle
    @State private var refreshPulse = 0

    private var primaryMemberID: String? { primaries.first?.memberID }

    var body: some View {
        Group {
            if let memberID = primaryMemberID {
                content(memberID: memberID)
                    .id(memberID) // fresh load state when the primary changes
            } else {
                onboarding
            }
        }
        .background(Color.obBackground)
    }

    // MARK: - Loaded content

    private func content(memberID: String) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                ScreenTitle(state.value?.firstName ?? "My Card") { AppearanceMenu() }
                switch state {
                case .idle, .loading:
                    if let player = state.value {
                        loadedBody(player)
                    } else {
                        SkeletonList()
                    }
                case .loaded(let player):
                    loadedBody(player)
                case .failed(let message, let cached, let cachedAt):
                    ErrorCard(message: message, cachedAt: cachedAt) {
                        Task { await load(memberID: memberID, force: true) }
                    }
                    if let cached { loadedBody(cached) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .accessibilityIdentifier(AccessibilityID.Screen.myCard)
        // The name is drawn in the content, not as a large navigation title,
        // so the appearance control can sit on its line.
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await load(memberID: memberID, force: true)
            refreshPulse += 1
        }
        .sensoryFeedback(.success, trigger: refreshPulse)
        .task(id: memberID) {
            await load(memberID: memberID, force: false)
        }
    }

    @ViewBuilder
    private func loadedBody(_ player: Player) -> some View {
        let lastEvent = player.events.first

        HStack(spacing: 8) {
            CopyableID(id: player.id)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .kerning(1.2)
            Spacer()
            ClassChip(rating: player.ratings.regular?.value,
                      stateName: player.ranking?.stateName ?? player.state)
        }
        .padding(.top, 4)

        PlayerTopBadges(memberID: player.id)

        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 16) {
                RatingHistoryLink(player: player, system: .regular) {
                    HeroRatingCard(rating: player.ratings.regular,
                                   delta: lastEvent?.regular?.delta,
                                   sparkline: player.ratingHistory,
                                   peak: player.peakRegular,
                                   showsDisclosure: player.hasHistory(.regular))
                }
                .accessibilityIdentifier(AccessibilityID.heroRatingCard)
                HStack(spacing: 16) {
                    RatingHistoryLink(player: player, system: .quick) {
                        MiniRatingCard(label: "Quick", rating: player.ratings.quick, tint: .obTeal,
                                       showsDisclosure: player.hasHistory(.quick))
                    }
                    MiniRatingCard(label: "Blitz", rating: player.ratings.blitz, tint: .obTeal)
                }
            }
        }

        if let lastEvent, let delta = lastEvent.regular?.delta, delta != 0 {
            justRatedBanner(event: lastEvent, playerID: player.id)
        }

        if let ranking = player.ranking {
            rankingCards(ranking)
        }

        if !player.events.isEmpty {
            SectionLabel(text: "Recent events")
                .padding(.top, 8)
            ForEach(player.events.prefix(6)) { event in
                NavigationLink(value: Destination.event(id: event.id, highlight: player.id)) {
                    EventResultRow(event: event)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func justRatedBanner(event: EventResult, playerID: String) -> some View {
        NavigationLink(value: Destination.event(id: event.id, highlight: playerID)) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(Color.obGold)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(event.name) was just rated")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let pre = event.regular?.pre, let post = event.regular?.post {
                        Text("\(pre) → \(post) (\((post - pre).signedString))")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(post >= pre ? Color.obUp : Color.obDown)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .obCard()
        }
        .buttonStyle(.plain)
    }

    private func rankingCards(_ ranking: Ranking) -> some View {
        HStack(spacing: 16) {
            if let overall = ranking.overall {
                StatCard(title: "National",
                         value: "№ \(overall.rank.formatted())",
                         caption: "of \(overall.total.formatted()) · top \(100 - overall.computedPercentile)%",
                         systemImage: "flag.fill")
            }
            if let state = ranking.state {
                StatCard(title: ranking.stateName ?? "State",
                         value: "№ \(state.rank.formatted())",
                         caption: "of \(state.total.formatted()) · top \(100 - state.computedPercentile)%",
                         systemImage: "mappin.and.ellipse",
                         tint: .obTeal)
            }
        }
    }

    // MARK: - Onboarding empty state

    private var onboarding: some View {
        ScrollView {
            VStack(spacing: 20) {
                ScreenTitle("My Card") { AppearanceMenu() }
                    .padding(.horizontal, 16)
                Image(systemName: "crown.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.obGold)
                    .padding(.top, 60)
                Text("Welcome to OpenBoard")
                    .font(.largeTitle.weight(.bold))
                Text("Follow a US Chess player to build your card. Search by name or enter an 8-digit member ID.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    model.selectedTab = .search
                } label: {
                    Label("Find a player", systemImage: "magnifyingglass")
                        .font(.headline)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.glassProminent)
            }
            .frame(maxWidth: .infinity)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Loading

    private func load(memberID: String, force: Bool) async {
        if state.value == nil {
            if let (cached, _) = await model.service.cachedPlayer(id: memberID) {
                state = .loaded(cached)
            } else {
                state = .loading
            }
        }
        do {
            let fresh = try await model.service.player(id: memberID)
            state = .loaded(fresh)
        } catch {
            let cached = await model.service.cachedPlayer(id: memberID)
            state = .failed(message: error.localizedDescription,
                            cached: cached?.0, cachedAt: cached?.1)
        }
    }
}

// MARK: - Event row (shared with profile history)

struct EventResultRow: View {
    var event: EventResult
    var system: RatingSystem = .regular

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(Format.eventDate(event.date))
                    if let score = event.score {
                        Text("·")
                        Text(score).monospacedDigit()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let prePost = event.result(for: system), let pre = prePost.pre, let post = prePost.post {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(pre) → \(post)")
                        .font(.footnote.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    if let delta = prePost.delta {
                        DeltaBadge(delta: delta)
                    }
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .obCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

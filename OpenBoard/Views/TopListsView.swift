import SwiftUI
import SwiftData

// MARK: - Badge

/// "🏅 #37 · Age 9" — shown wherever a player on a Top 100 list appears.
struct TopRankBadge: View {
    var rank: TopListRank
    var compact = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "medal.fill")
            Text(compact ? "#\(rank.rank)" : "#\(rank.rank) · \(rank.definition.badgeLabel)")
                .monospacedDigit()
                .lineLimit(1)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(Color.obGold)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.obGold.opacity(0.14), in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Number \(rank.rank) on the US Chess Top 100, \(rank.definition.badgeLabel)")
    }
}

/// The player's best badge, if any — drop into any row.
struct PlayerTopBadge: View {
    var memberID: String
    var compact = false
    @Environment(AppModel.self) private var model

    var body: some View {
        if let best = model.topLists.best(for: memberID) {
            TopRankBadge(rank: best, compact: compact)
        }
    }
}

/// Every list the player is on, each linking to that list (profiles, My Card).
struct PlayerTopBadges: View {
    var memberID: String
    @Environment(AppModel.self) private var model

    var body: some View {
        let ranks = model.topLists.ranks(for: memberID)
        if !ranks.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ranks, id: \.definition.id) { rank in
                        NavigationLink(value: Destination.topList(id: rank.definition.id, highlight: memberID)) {
                            TopRankBadge(rank: rank)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(AccessibilityID.topBadge(rank.definition.id))
                    }
                }
            }
            .scrollClipDisabled()
            .accessibilityIdentifier(AccessibilityID.topBadges)
        }
    }
}

// MARK: - Browse

/// Search → Top 100: every US Chess Top 100 list, filtered by rating type,
/// open/girls, age group, and (optionally) the user's state.
struct TopListsBrowseView: View {
    enum Group: String, CaseIterable, Identifiable {
        case open = "Open"
        case women = "Girls & Women"
        var id: Self { self }
    }

    @Environment(AppModel.self) private var model
    @Query(filter: #Predicate<WatchedPlayer> { $0.isPrimary }) private var primaries: [WatchedPlayer]
    @State private var rating: TopListRating = .regular
    @State private var group: Group = .open
    @State private var listID: String?
    @State private var stateOnly = false
    @State private var definitions: Loadable<[TopListDefinition]> = .idle

    private var homeState: String? { primaries.first?.state }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch definitions {
                case .idle, .loading:
                    SkeletonList()
                case .failed(let message, _, _):
                    ErrorCard(message: message, cachedAt: nil) { Task { await loadDefinitions() } }
                case .loaded(let all):
                    filters(all)
                    if let definition = selected(all) {
                        TopListContent(definition: definition, highlight: nil,
                                       stateFilter: stateOnly ? homeState : nil)
                            .id("\(definition.id)-\(stateOnly)")
                    }
                }
            }
            .padding(16)
        }
        .accessibilityIdentifier(AccessibilityID.Screen.topLists)
        .background(Color.obBackground)
        .navigationTitle("Top 100")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDefinitions() }
    }

    private func options(_ all: [TopListDefinition]) -> [TopListDefinition] {
        all.filter { $0.rating == rating && $0.isWomen == (group == .women) }
            .sorted { $0.sortKey < $1.sortKey }
    }

    private func selected(_ all: [TopListDefinition]) -> TopListDefinition? {
        let options = options(all)
        return options.first { $0.id == listID } ?? options.first { $0.ageGroup == "Overall" } ?? options.first
    }

    @ViewBuilder
    private func filters(_ all: [TopListDefinition]) -> some View {
        Picker("Rating", selection: $rating) {
            ForEach(TopListRating.allCases) { Text($0.title).tag($0).accessibilityIdentifier(AccessibilityID.segment("toplist-rating", "\($0)")) }
        }
        .pickerStyle(.segmented)

        let current = selected(all)
        HStack(spacing: 8) {
            FilterChip(title: current?.ageGroup ?? "Age", systemImage: "person.crop.circle",
                       active: current?.ageGroup != "Overall", id: AccessibilityID.filter("age")) {
                Picker("Age", selection: Binding(get: { current?.id ?? "" }, set: { listID = $0 })) {
                    ForEach(options(all)) { Text($0.ageGroup).tag($0.id).accessibilityIdentifier(AccessibilityID.filterOption("age", $0.id)) }
                }
            }
            FilterChip(title: group == .open ? "Open" : "Girls", systemImage: "figure.stand",
                       active: group == .women, id: AccessibilityID.filter("list")) {
                Picker("List", selection: $group) {
                    ForEach(Group.allCases) { Text($0.rawValue).tag($0).accessibilityIdentifier(AccessibilityID.filterOption("list", "\($0)")) }
                }
            }
            if let homeState {
                FilterChip(title: stateOnly ? homeState : "All states", systemImage: "mappin.and.ellipse",
                           active: stateOnly, id: AccessibilityID.filter("state")) {
                    Picker("State", selection: $stateOnly) {
                        Text("All states").tag(false).accessibilityIdentifier(AccessibilityID.filterOption("state", "all"))
                        Text("\(homeState) only").tag(true).accessibilityIdentifier(AccessibilityID.filterOption("state", "home"))
                    }
                }
            }
        }
        .onChange(of: rating) { keepAgeGroup(all) }
        .onChange(of: group) { keepAgeGroup(all) }
    }

    /// Switching rating type or open/girls keeps the same age group when it exists.
    private func keepAgeGroup(_ all: [TopListDefinition]) {
        let age = all.first { $0.id == listID }?.ageGroup
        listID = options(all).first { $0.ageGroup == age }?.id
    }

    private func loadDefinitions() async {
        if definitions.value != nil { return }
        definitions = .loading
        do {
            definitions = .loaded(try await model.service.topListDefinitions())
        } catch {
            definitions = .failed(message: error.localizedDescription, cached: nil, cachedAt: nil)
        }
    }
}

// MARK: - Single list

/// One list, opened from a badge; scrolls to and highlights the player.
struct TopListView: View {
    let id: String
    var highlight: String?

    @Environment(AppModel.self) private var model
    @State private var definition: TopListDefinition?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let definition {
                        TopListContent(definition: definition, highlight: highlight, stateFilter: nil) {
                            guard let highlight else { return }
                            Task {
                                try? await Task.sleep(for: .milliseconds(300))
                                withAnimation { proxy.scrollTo(highlight, anchor: .center) }
                            }
                        }
                    } else {
                        SkeletonList()
                    }
                }
                .padding(16)
            }
        }
        .accessibilityIdentifier(AccessibilityID.Screen.topLists)
        .background(Color.obBackground)
        .navigationTitle("Top 100")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: id) {
            definition = model.topLists.definitions.first { $0.id == id }
            if definition == nil {
                definition = try? await model.service.topListDefinitions().first { $0.id == id }
            }
        }
    }
}

/// Header + rows for one list.
struct TopListContent: View {
    let definition: TopListDefinition
    var highlight: String?
    var stateFilter: String?
    var onLoaded: () -> Void = {}

    @Environment(AppModel.self) private var model
    @State private var list: Loadable<TopList> = .idle

    var body: some View {
        switch list {
        case .idle, .loading:
            SkeletonList()
                .task { await load() }
        case .failed(let message, _, _):
            ErrorCard(message: message, cachedAt: nil) { Task { await load() } }
        case .loaded(let list):
            let entries = stateFilter.map { state in list.entries.filter { $0.state == state } } ?? list.entries
            VStack(alignment: .leading, spacing: 4) {
                Text("\(definition.isWomen && !definition.name.hasPrefix("Girls") ? "Women · " : "")\(definition.name) · \(definition.rating.title)")
                    .font(.title3.weight(.bold))
                Text([list.reportDate.map { "As of \($0.formatted(.dateTime.month(.wide).day().year()))" },
                      stateFilter.map { "\(entries.count) from \($0)" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if entries.isEmpty {
                EmptyStateCard(systemImage: "person.3", title: "No players from \(stateFilter ?? "here")",
                               message: "Nobody from this state is on this list right now.")
            }
            LazyVStack(spacing: 8) {
                ForEach(entries) { entry in
                    NavigationLink(value: Destination.player(id: entry.id)) {
                        TopListRow(entry: entry,
                                   isHighlight: entry.id == highlight,
                                   isWatched: model.watchedIDs.contains(entry.id))
                    }
                    .buttonStyle(.plain)
                    .id(entry.id)
                    .accessibilityIdentifier(AccessibilityID.topListEntry(entry.id))
                }
            }
        }
    }

    private func load() async {
        list = .loading
        do {
            list = .loaded(try await model.service.topList(definition))
            onLoaded()
        } catch {
            list = .failed(message: error.localizedDescription, cached: nil, cachedAt: nil)
        }
    }
}

struct TopListRow: View {
    var entry: TopListEntry
    var isHighlight: Bool
    var isWatched: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(entry.rank <= 3 ? Color.obGold : .secondary)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let state = entry.state {
                        Text(state)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.obTeal)
                    }
                    if isWatched {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.obGold)
                    }
                }
            }
            Spacer()
            Text("\(entry.rating)")
                .font(.body.weight(.semibold))
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .obCard(cornerRadius: 16)
        .overlay {
            if isHighlight {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.obGold, lineWidth: 2)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

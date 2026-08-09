import SwiftUI

struct CrosstableView: View {
    let eventID: String
    var highlightMemberID: String?

    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var state: Loadable<ChessEvent> = .idle
    @State private var sectionIndex = 0
    @State private var expanded: Set<String> = []

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                ScrollView {
                    SkeletonList().padding(16)
                }
            case .loaded(let event):
                loadedBody(event)
            case .failed(let message, let cached, let cachedAt):
                VStack(spacing: 0) {
                    ErrorCard(message: message, cachedAt: cachedAt) {
                        Task { await load(force: true) }
                    }
                    .padding(16)
                    if let cached {
                        loadedBody(cached)
                    } else {
                        Spacer()
                    }
                }
            }
        }
        .background(Color.obBackground)
        .navigationTitle(state.value?.name ?? "Crosstable")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: eventID) { await load(force: false) }
        .refreshable { await load(force: true) }
    }

    // MARK: - Loaded

    @ViewBuilder
    private func loadedBody(_ event: ChessEvent) -> some View {
        VStack(spacing: 0) {
            header(event)

            if event.sections.count > 1 {
                Picker("Section", selection: $sectionIndex) {
                    ForEach(Array(event.sections.enumerated()), id: \.offset) { index, section in
                        Text(section.name).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            if sizeClass == .regular {
                // iPad: no paging; one roomy list.
                if let section = event.sections[safe: sectionIndex] {
                    standingsList(section)
                }
            } else {
                TabView(selection: $sectionIndex) {
                    ForEach(Array(event.sections.enumerated()), id: \.offset) { index, section in
                        standingsList(section)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
    }

    private func header(_ event: ChessEvent) -> some View {
        HStack {
            Text("EVENT \(eventID)\(event.date.map { " · RATED \(Format.eventDate($0).uppercased())" } ?? "")")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .kerning(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func standingsList(_ section: EventSection) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(section.players) { standing in
                        StandingRow(
                            standing: standing,
                            isWatched: model.watchedIDs.contains(standing.id),
                            isHighlight: standing.id == highlightMemberID,
                            isExpanded: expanded.contains(standing.id),
                            opponentName: { rank in section.players.first { $0.rank == rank }?.name },
                            onTap: { toggle(standing.id) }
                        )
                        .id(standing.id)
                        .accessibilityIdentifier("standing-\(standing.id)")
                    }
                }
                .padding(16)
            }
            .onAppear {
                guard let target = highlightMemberID,
                      section.players.contains(where: { $0.id == target }) else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    withAnimation(.easeInOut) { proxy.scrollTo(target, anchor: .center) }
                }
            }
        }
    }

    private func toggle(_ id: String) {
        withAnimation(.snappy(duration: 0.28)) {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }

    // MARK: - Load

    private func load(force: Bool) async {
        if state.value == nil {
            if let (cached, _) = await model.service.cachedEvent(id: eventID) {
                state = .loaded(cached)
                selectHighlightSection(cached)
            } else {
                state = .loading
            }
        }
        do {
            let event = try await model.service.event(id: eventID)
            state = .loaded(event)
            selectHighlightSection(event)
        } catch {
            let cached = await model.service.cachedEvent(id: eventID)
            state = .failed(message: error.localizedDescription,
                            cached: cached?.0, cachedAt: cached?.1)
        }
    }

    /// Jump the segmented control to whichever section contains the followed player.
    private func selectHighlightSection(_ event: ChessEvent) {
        guard let target = highlightMemberID else { return }
        if let index = event.sections.firstIndex(where: { section in
            section.players.contains { $0.id == target }
        }) {
            sectionIndex = index
        }
        if AppEnvironment.autoExpandHighlight { expanded.insert(target) }
    }
}

// MARK: - Standing row

struct StandingRow: View {
    var standing: Standing
    var isWatched: Bool
    var isHighlight: Bool
    var isExpanded: Bool
    /// Resolves an opponent's name from their finishing rank within this section.
    var opponentName: (Int) -> String?
    var onTap: () -> Void

    private var placeColor: Color {
        standing.rank <= 3 ? .obGold : .secondary
    }

    private var canExpand: Bool { !standing.rounds.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) { header }
                .buttonStyle(.plain)

            if isExpanded {
                gamesSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .obCard()
        .overlay {
            if isHighlight || isWatched {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.obGold.opacity(isHighlight ? 0.9 : 0.45),
                                  lineWidth: isHighlight ? 2 : 1)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: Header (tappable)

    private var header: some View {
        HStack(spacing: 12) {
            Text("\(standing.rank)")
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(placeColor)
                .frame(width: 30, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(standing.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let state = standing.state {
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
                HStack(spacing: 10) {
                    prePostText("R", standing.regular)
                    prePostText("Q", standing.quick)
                }
                .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 8)

            Text(standing.points)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.primary)

            if canExpand {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(canExpand ? (isExpanded ? "Collapse games" : "Show games") : "")
    }

    // MARK: Expanded games

    private var gamesSection: some View {
        VStack(spacing: 8) {
            Divider().overlay(Color.obHairline).padding(.vertical, 10)
            if standing.rounds.isEmpty {
                Text("Round-by-round results aren't available for this section.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(standing.rounds, id: \.round) { gameRow($0) }
            }
            NavigationLink(value: Destination.player(id: standing.id)) {
                HStack(spacing: 4) {
                    Text("View full profile")
                    Image(systemName: "chevron.right")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.obGold)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 2)
            }
            .buttonStyle(.plain)
        }
    }

    private func gameRow(_ outcome: RoundOutcome) -> some View {
        HStack(spacing: 12) {
            resultChip(outcome.symbol)
            Text("Round \(outcome.round)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .leading)
            Text(opponentText(outcome))
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            if let color = outcome.color, outcome.symbol != "B" {
                Text(color.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Round \(outcome.round), \(resultWord(outcome.symbol)) \(opponentText(outcome))")
    }

    private func opponentText(_ outcome: RoundOutcome) -> String {
        if outcome.symbol == "B" { return "Bye" }
        let name = outcome.opponentName ?? outcome.opponentRank.flatMap(opponentName)
        return name.map { "vs \($0)" } ?? "vs opponent"
    }

    private func resultChip(_ symbol: String) -> some View {
        Text(symbol)
            .font(.caption.weight(.heavy))
            .foregroundStyle(chipTint(symbol))
            .frame(width: 26, height: 26)
            .background(chipTint(symbol).opacity(0.16), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func chipTint(_ symbol: String) -> Color {
        switch symbol {
        case "W": .obUp
        case "L": .obDown
        case "D": .obTeal
        default: .secondary
        }
    }

    private func resultWord(_ symbol: String) -> String {
        switch symbol {
        case "W": "beat"
        case "L": "lost to"
        case "D": "drew"
        case "B": "bye"
        default: "played"
        }
    }

    @ViewBuilder
    private func prePostText(_ label: String, _ prePost: PrePost?) -> some View {
        if let prePost, prePost.post != nil {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                Text("\(prePost.pre.map(String.init) ?? "new") → \(prePost.post.map(String.init) ?? "—")")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if let delta = prePost.delta {
                    Text(delta >= 0 ? "▲\(delta)" : "▼\(abs(delta))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(delta >= 0 ? Color.obUp : Color.obDown)
                }
            }
            .lineLimit(1)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

import SwiftUI

struct CrosstableView: View {
    let eventID: String
    var highlightMemberID: String?

    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var state: Loadable<ChessEvent> = .idle
    @State private var sectionIndex = 0
    @State private var expanded: Set<String> = []
    @State private var showingSections = false

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
        .navigationTitle("Tournament") // full name wraps in the header below
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
                sectionMenu(event)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
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
        let playerCount = event.sections.reduce(0) { $0 + $1.players.count }
        let meta = [event.date.map { "Rated \(Format.eventDate($0))" },
                    "\(playerCount) \(playerCount == 1 ? "player" : "players")"]
            .compactMap { $0 }.joined(separator: " · ")

        return VStack(alignment: .leading, spacing: 6) {
            Text(event.name)
                .font(.title3.weight(.bold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    Text(meta + " · ")
                    CopyableID(id: eventID, prefix: "Event ")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(meta)
                    CopyableID(id: eventID, prefix: "Event ")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func highlightSectionIndex(_ event: ChessEvent) -> Int? {
        guard let id = highlightMemberID else { return nil }
        return event.sections.firstIndex { $0.players.contains { $0.id == id } }
    }

    /// Full-width selector showing the current section's whole name and
    /// "Section 2 of 5"; tapping opens a sheet listing every section.
    /// Swiping the standings still pages between sections on iPhone.
    private func sectionMenu(_ event: ChessEvent) -> some View {
        let current = event.sections[safe: sectionIndex]
        let isHighlightSection = sectionIndex == highlightSectionIndex(event)

        return Button {
            showingSections = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Section \(sectionIndex + 1) of \(event.sections.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .kerning(1)
                    HStack(spacing: 6) {
                        Text(current?.name ?? "")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        if isHighlightSection {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.obGold)
                        }
                    }
                }
                Spacer(minLength: 8)
                Text("\(current?.players.count ?? 0) players")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .obCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Section \(sectionIndex + 1) of \(event.sections.count): \(current?.name ?? "")")
        .accessibilityHint("Choose a section")
        .accessibilityIdentifier("section-menu")
        .sensoryFeedback(.selection, trigger: sectionIndex)
        .sheet(isPresented: $showingSections) {
            SectionPickerSheet(sections: event.sections,
                               selection: $sectionIndex,
                               highlightIndex: highlightSectionIndex(event))
        }
    }

    private func standingsList(_ section: EventSection) -> some View {
        let estimates = RoundRatingEstimator.estimate(section)
        let byRank = Dictionary(section.players.map { ($0.rank, $0) }, uniquingKeysWith: { first, _ in first })
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(section.players) { standing in
                        StandingRow(
                            standing: standing,
                            isWatched: model.watchedIDs.contains(standing.id),
                            isHighlight: standing.id == highlightMemberID,
                            isExpanded: expanded.contains(standing.id),
                            opponent: { byRank[$0] },
                            estimates: estimates,
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

// MARK: - Section picker sheet

struct SectionPickerSheet: View {
    let sections: [EventSection]
    @Binding var selection: Int
    var highlightIndex: Int?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(Array(sections.enumerated()), id: \.offset) { index, section in
                Button {
                    selection = index
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(section.name)
                                .font(.body.weight(index == selection ? .semibold : .regular))
                                .foregroundStyle(.primary)
                            HStack(spacing: 6) {
                                Text("\(section.players.count) players")
                                if index == highlightIndex {
                                    Label("Followed player", systemImage: "star.fill")
                                        .foregroundStyle(Color.obGold)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if index == selection {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.obGold)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(index == selection ? .isSelected : [])
                .accessibilityIdentifier("section-option-\(index)")
            }
            .navigationTitle("Sections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Standing row

struct StandingRow: View {
    var standing: Standing
    var isWatched: Bool
    var isHighlight: Bool
    var isExpanded: Bool
    /// Resolves an opponent from their finishing rank within this section.
    var opponent: (Int) -> Standing?
    /// Estimated per-round rating changes for everyone in the section.
    var estimates: RoundRatingEstimator.Estimates
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
                // Side by side when they fit, otherwise stacked — never truncated.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        prePostText("R", standing.regular)
                        prePostText("Q", standing.quick)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        prePostText("R", standing.regular)
                        prePostText("Q", standing.quick)
                    }
                }
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
                if let total = eventDelta, hasEstimates {
                    Text("≈ Estimated per game from the official \(estimates.system.title) change (\(total.signedString)). US Chess only publishes the event total.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
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

    private var eventDelta: Int? {
        (estimates.system == .regular ? standing.regular : standing.quick)?.delta
    }

    private var hasEstimates: Bool { estimates.byMember[standing.id] != nil }

    private func gameRow(_ outcome: RoundOutcome) -> some View {
        let opponent = outcome.opponentRank.flatMap(opponent)
        let mine = estimates.change(for: standing.id, round: outcome.round)
        let theirs = opponent.flatMap { estimates.change(for: $0.id, round: outcome.round) }

        return HStack(spacing: 12) {
            resultChip(outcome.symbol)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Round \(outcome.round)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    if let color = outcome.color, !color.isEmpty, outcome.symbol != "B" {
                        Text(color.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                HStack(spacing: 4) {
                    Text(opponentText(outcome, opponent))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let rating = opponent.flatMap(opponentRating) {
                        Text("(\(rating))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .layoutPriority(1)
                    }
                }
                .font(.caption.weight(.medium))
            }
            Spacer(minLength: 8)
            if mine != nil || theirs != nil {
                VStack(alignment: .trailing, spacing: 2) {
                    if let mine {
                        estimateText(mine)
                            .font(.caption.weight(.bold))
                    }
                    if let theirs, let opponent {
                        HStack(spacing: 3) {
                            Text(opponent.firstName)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            estimateText(theirs)
                        }
                        .font(.caption2.weight(.semibold))
                    }
                }
                .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(outcome, opponent: opponent, mine: mine, theirs: theirs))
    }

    private func estimateText(_ change: Int) -> some View {
        Text("≈ \(change.signedString)")
            .monospacedDigit()
            .foregroundStyle(change > 0 ? Color.obUp : change < 0 ? Color.obDown : Color.secondary)
    }

    private func opponentRating(_ opponent: Standing) -> Int? {
        let result = estimates.system == .regular ? opponent.regular : opponent.quick
        return result?.pre ?? result?.post
    }

    private func opponentText(_ outcome: RoundOutcome, _ opponent: Standing?) -> String {
        if outcome.symbol == "B" { return "Bye" }
        let name = outcome.opponentName ?? opponent?.name
        return name.map { "vs \($0)" } ?? "vs opponent"
    }

    private func accessibilityText(_ outcome: RoundOutcome, opponent: Standing?,
                                   mine: Int?, theirs: Int?) -> String {
        var text = "Round \(outcome.round), \(resultWord(outcome.symbol)) \(opponentText(outcome, opponent))"
        if let mine { text += ", about \(mine.signedString) for \(standing.firstName)" }
        if let theirs, let opponent { text += ", about \(theirs.signedString) for \(opponent.firstName)" }
        return text
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

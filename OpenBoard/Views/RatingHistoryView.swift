import SwiftUI
import Charts

/// Full-screen rating history: a line of post-event ratings where each event is
/// a dot colored by direction (up / down / even), filterable by rating system,
/// event count, period, and result direction. Every event links to its crosstable.
struct RatingHistoryView: View {
    let player: Player
    @State private var system: RatingSystem
    @State private var count: EventCount = .all
    @State private var period: Period = .all
    @State private var direction: Direction = .all
    @State private var selectedID: String?

    init(player: Player, initialSystem: RatingSystem = .regular) {
        self.player = player
        _system = State(initialValue: initialSystem)
    }

    // MARK: - Filters

    enum EventCount: Int, CaseIterable, Identifiable {
        case five = 5, ten = 10, twenty = 20, all = 0
        var id: Int { rawValue }
        var title: String { self == .all ? String(localized: "All events") : String(localized: "Last \(rawValue)") }
        /// Chip label: the filter's name while unfiltered, else the choice.
        var chipTitle: String { self == .all ? String(localized: "Events") : title }
    }

    enum Period: CaseIterable, Identifiable {
        case threeMonths, year, all
        var id: Self { self }
        var title: String {
            switch self {
            case .threeMonths: String(localized: "3 months")
            case .year: String(localized: "1 year")
            case .all: String(localized: "All time")
            }
        }
        var chipTitle: String { self == .all ? String(localized: "Time") : title }
        var cutoff: Date? {
            switch self {
            case .threeMonths: Calendar.current.date(byAdding: .month, value: -3, to: .now)
            case .year: Calendar.current.date(byAdding: .year, value: -1, to: .now)
            case .all: nil
            }
        }
    }

    enum Direction: CaseIterable, Identifiable {
        case all, up, down, even
        var id: Self { self }
        var title: String {
            switch self {
            case .all: String(localized: "Any result")
            case .up: String(localized: "Gained")
            case .down: String(localized: "Lost")
            case .even: String(localized: "No change")
            }
        }
        var chipTitle: String { self == .all ? String(localized: "Result") : title }
        var systemImage: String {
            switch self {
            case .all: "line.3.horizontal.decrease"
            case .up: "arrow.up.right"
            case .down: "arrow.down.right"
            case .even: "equal"
            }
        }
        func matches(_ delta: Int) -> Bool {
            switch self {
            case .all: true
            case .up: delta > 0
            case .down: delta < 0
            case .even: delta == 0
            }
        }
    }

    // MARK: - Data

    private struct Entry: Identifiable {
        let index: Int
        let event: EventResult
        let pre: Int
        let post: Int
        var id: String { event.id }
        var delta: Int { post - pre }
        var tint: Color { delta > 0 ? .obUp : delta < 0 ? .obDown : .gray }
    }

    /// Chart window: rated events for the system, oldest → newest, cut by period then count.
    private var entries: [Entry] {
        var events = player.events
            .filter { $0.result(for: system)?.post != nil }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        if let cutoff = period.cutoff {
            events = events.filter { ($0.date ?? .distantPast) >= cutoff }
        }
        if count != .all {
            events = Array(events.suffix(count.rawValue))
        }
        return events.enumerated().map { index, event in
            let result = event.result(for: system)!
            return Entry(index: index, event: event,
                         pre: result.pre ?? result.post!, post: result.post!)
        }
    }

    // MARK: - Body

    var body: some View {
        let entries = entries
        let visible = entries.filter { direction.matches($0.delta) }

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Rating", selection: $system) {
                    ForEach(RatingSystem.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                filterChips

                if entries.isEmpty {
                    EmptyStateCard(systemImage: "chart.xyaxis.line",
                                   title: "No \(system.title.lowercased()) events",
                                   message: "Try a longer period or another rating type.")
                } else {
                    summary(entries)
                    chartCard(entries)
                    if let selected = entries.first(where: { $0.id == selectedID }) {
                        SectionLabel(text: "Selected event")
                        eventLink(selected.event)
                    }
                    SectionLabel(text: "Events · \(visible.count)")
                        .padding(.top, 4)
                    if visible.isEmpty {
                        Text("No events match “\(direction.title)” in this range.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(visible.reversed()) { entry in
                        eventLink(entry.event)
                            .accessibilityIdentifier("rating-history-event-\(entry.id)")
                    }
                }
            }
            .padding()
        }
        .background(Color.obBackground)
        .navigationTitle("Rating History")
        .navigationSubtitle(player.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: system) { selectedID = nil }
        .sensoryFeedback(.selection, trigger: selectedID)
    }

    // MARK: - Filter chips

    /// Three equal-width chips that always fit one row; pick the "all" option to clear one.
    private var filterChips: some View {
        HStack(spacing: 8) {
            FilterChip(title: count.chipTitle, systemImage: "number", active: count != .all) {
                Picker("Events", selection: $count) {
                    ForEach(EventCount.allCases) { Text($0.title).tag($0) }
                }
            }
            FilterChip(title: period.chipTitle, systemImage: "calendar", active: period != .all) {
                Picker("Time", selection: $period) {
                    ForEach(Period.allCases) { Text($0.title).tag($0) }
                }
            }
            FilterChip(title: direction.chipTitle, systemImage: direction.systemImage, active: direction != .all) {
                Picker("Result", selection: $direction) {
                    ForEach(Direction.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                }
            }
        }
    }

    // MARK: - Summary

    private func summary(_ entries: [Entry]) -> some View {
        let net = entries.last!.post - entries.first!.pre
        let ups = entries.filter { $0.delta > 0 }.count
        let downs = entries.filter { $0.delta < 0 }.count
        let evens = entries.count - ups - downs

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(entries.first!.pre) → \(entries.last!.post)")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text("\(entries.count == 1 ? "1 event" : "\(entries.count) events") · peak \(entries.map(\.post).max()!)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                DeltaBadge(delta: net, prominent: true)
                HStack(spacing: 8) {
                    tally(ups, "arrow.up", .obUp)
                    tally(downs, "arrow.down", .obDown)
                    tally(evens, "equal", .secondary)
                }
            }
        }
        .padding(16)
        .obCard()
        .accessibilityElement(children: .combine)
    }

    private func tally(_ n: Int, _ symbol: String, _ tint: Color) -> some View {
        Label("\(n)", systemImage: symbol)
            .labelStyle(TallyLabelStyle())
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
    }

    private struct TallyLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 2) { configuration.icon.imageScale(.small); configuration.title }
        }
    }

    // MARK: - Chart

    private func chartCard(_ entries: [Entry]) -> some View {
        let domain = yDomain(entries)
        let selected = entries.first { $0.id == selectedID }

        return VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(entries) { entry in
                    AreaMark(x: .value("Event", entry.index),
                             yStart: .value("Base", domain.lowerBound),
                             yEnd: .value("Rating", entry.post))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [Color.obGold.opacity(0.28), Color.obGold.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Event", entry.index), y: .value("Rating", entry.post))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .foregroundStyle(Color.obGold)
                }
                if let selected {
                    RuleMark(x: .value("Event", selected.index))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                ForEach(entries) { entry in
                    let isSelected = entry.id == selectedID
                    PointMark(x: .value("Event", entry.index), y: .value("Rating", entry.post))
                        .symbolSize(isSelected ? 160 : 70)
                        .foregroundStyle(entry.tint.opacity(direction.matches(entry.delta) ? 1 : 0.25))
                        .annotation(position: .top, spacing: 6) {
                            if isSelected {
                                Text(entry.delta.signedString)
                                    .font(.caption2.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(entry.tint)
                            }
                        }
                        .accessibilityLabel(entry.event.name)
                        .accessibilityValue("\(entry.post), \(entry.delta.signedString)")
                }
            }
            .chartYScale(domain: domain)
            .chartXScale(domain: -0.5...(Double(entries.count) - 0.5))
            .chartXAxis {
                AxisMarks(values: axisIndices(entries.count)) { value in
                    let i = value.as(Int.self) ?? 0
                    AxisGridLine()
                    // Edge labels hang inward so they aren't clipped by the plot bounds.
                    AxisValueLabel(anchor: i == 0 ? .topLeading
                                   : i == entries.count - 1 ? .topTrailing : .top) {
                        if entries.indices.contains(i), let date = entries[i].event.date {
                            Text(date.formatted(.dateTime.month(.abbreviated).year(.twoDigits)))
                                .fixedSize()
                        }
                    }
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let plot = proxy.plotFrame else { return }
                            let x = location.x - geo[plot].minX
                            guard let raw: Double = proxy.value(atX: x) else { return }
                            let i = min(max(Int(raw.rounded()), 0), entries.count - 1)
                            let id = entries[i].id
                            selectedID = selectedID == id ? nil : id
                        }
                }
            }
            .frame(height: 220)

            HStack(spacing: 12) {
                legend("Gained", .obUp)
                legend("Lost", .obDown)
                legend("No change", .gray)
                Spacer()
                Text("Tap a dot")
                    .foregroundStyle(.tertiary)
            }
            .font(.caption2)
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func legend(_ title: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(title).foregroundStyle(.secondary)
        }
    }

    private func yDomain(_ entries: [Entry]) -> ClosedRange<Int> {
        let values = entries.flatMap { [$0.pre, $0.post] }
        guard let lo = values.min(), let hi = values.max(), lo != hi else {
            let v = values.first ?? 0
            return (v - 50)...(v + 50)
        }
        let pad = max(10, (hi - lo) / 6)
        return (lo - pad)...(hi + pad)
    }

    /// Up to four evenly spaced labelled ticks, always including the oldest and newest event.
    private func axisIndices(_ n: Int) -> [Int] {
        guard n > 4 else { return Array(0..<n) }
        return (0...3).map { Int((Double($0) * Double(n - 1) / 3).rounded()) }
    }

    // MARK: - Rows

    private func eventLink(_ event: EventResult) -> some View {
        NavigationLink(value: Destination.event(id: event.id, highlight: player.id)) {
            EventResultRow(event: event, system: system)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Entry point

/// Wraps a rating card so tapping it opens that player's rating history —
/// or leaves it inert when there are no rated events for `system` to chart.
struct RatingHistoryLink<Card: View>: View {
    let player: Player
    let system: RatingSystem
    @ViewBuilder var card: Card

    var body: some View {
        if player.hasHistory(system) {
            NavigationLink(value: Destination.ratingHistory(player: player, system: system)) {
                card
            }
            .buttonStyle(.plain)
        } else {
            card
        }
    }
}

#Preview {
    NavigationStack {
        RatingHistoryView(player: MockRatingsService.samplePlayer)
            .openBoardDestinations()
    }
    .environment(AppModel(dataSource: .mock, demoSeed: false))
    .tint(.obGold)
}

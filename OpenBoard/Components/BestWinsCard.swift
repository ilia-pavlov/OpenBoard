import SwiftUI

/// "Best wins": the highest-rated opponents the player has beaten in Regular
/// play, rated as they were going into that event. The top win is featured;
/// the next two sit under it. Each row opens that event's crosstable.
///
/// The first scan of an active player takes a while (one paced request per
/// event), so wins appear as they're found, above a progress line. Hidden when
/// the finished scan finds no wins over rated opponents, or fails with none.
struct BestWinsCard: View {
    let memberID: String

    @Environment(AppModel.self) private var model
    @State private var progress: BestWinsProgress?
    @State private var stopped = false
    @State private var showsInfo = false

    var body: some View {
        Group {
            if isHidden {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionLabel(text: "Best wins")
                        infoButton
                    }
                    .padding(.top, 8)
                    VStack(spacing: 0) {
                        ForEach(Array((progress?.wins ?? []).enumerated()), id: \.element.id) { index, win in
                            let topRank = model.topLists.best(for: win.opponentID)
                            if index > 0 {
                                Divider().padding(.leading, 16)
                            }
                            NavigationLink(value: Destination.event(id: win.eventID, highlight: memberID)) {
                                BestWinRow(win: win,
                                           topRank: topRank,
                                           featured: index == 0)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(BestWinRow.accessibilityText(win, topRank: topRank))
                            .accessibilityIdentifier(AccessibilityID.bestWin(win.opponentID))
                        }
                        if progress?.isFinished != true {
                            if progress?.wins.isEmpty == false {
                                Divider().padding(.leading, 16)
                            }
                            statusRow
                        }
                    }
                    .obCard()
                    .animation(.snappy, value: progress?.wins)
                }
                .accessibilityElement(children: .contain) // keep each row's own identifier
                .accessibilityIdentifier(AccessibilityID.bestWins)
            }
        }
        .task(id: memberID) { await scan() }
    }

    private var infoButton: some View {
        Button {
            showsInfo = true
        } label: {
            Image(systemName: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About best wins")
        .accessibilityIdentifier(AccessibilityID.bestWinsInfo)
        .popover(isPresented: $showsInfo) {
            BestWinsInfo()
                .presentationCompactAdaptation(.popover)
        }
    }

    /// Nothing to show: the scan ended (finished or failed) without a win.
    private var isHidden: Bool {
        let ended = stopped || progress?.isFinished == true
        return ended && (progress?.wins.isEmpty ?? true)
    }

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if !stopped {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !stopped, let progress, progress.eventsTotal > 0 {
                ProgressView(value: Double(progress.eventsChecked), total: Double(progress.eventsTotal))
                    .tint(Color.obGold)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        guard let progress else { return String(localized: "Loading rated games…") }
        if stopped {
            return String(localized: "Couldn't finish: US Chess is busy. Showing wins found so far.")
        }
        let games = progress.gameCount.formatted()
        return String(localized: "Analyzing \(games) games · \(progress.eventsChecked) of \(progress.eventsTotal) events")
    }

    private func scan() async {
        progress = nil
        stopped = false
        do {
            for try await step in model.service.bestWinsScan(memberID: memberID) {
                progress = step
            }
        } catch is CancellationError {
            // Left the screen; cached sections let the next visit pick up from here.
        } catch {
            stopped = true
        }
    }
}

/// The ⓘ explanation, in plain words for parents and kids.
private struct BestWinsInfo: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Best wins")
                .font(.headline)
            Text("The strongest players this player has beaten in rated games.")
            Label("The rating is the opponent's rating on the day of the game, not today.",
                  systemImage: "calendar")
            Label("\"+150 above\" means the opponent was rated 150 points higher at the time.",
                  systemImage: "arrow.up.right")
            Label("A medal means the opponent is on a US Chess Top 100 list today.",
                  systemImage: "medal")
            Label("Tap a win to see that tournament.", systemImage: "hand.tap")
            Text("The first check can take a few minutes for players with lots of games. After that it's instant.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 300, alignment: .leading)
        .padding(18)
    }
}

private struct BestWinRow: View {
    let win: NotableWin
    /// The opponent's best spot on today's Top 100 lists, if any.
    let topRank: TopListRank?
    let featured: Bool

    var body: some View {
        HStack(spacing: 12) {
            if featured {
                Image(systemName: "trophy.fill")
                    .font(.title3)
                    .foregroundStyle(Color.obGold)
                    .frame(width: 28)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(win.opponentName)
                    .font(featured ? .headline : .subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let topRank {
                    TopRankBadge(rank: topRank)
                }
                Text([win.eventName, Format.eventDate(win.date)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(String(win.opponentRating)) // "2551", like the rating cards — no grouping
                    .font(featured ? .title2.weight(.bold) : .subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(featured ? Color.obGold : Color.primary)
                if let gap = win.ratingGap, gap > 0 {
                    Text("+\(String(gap)) above")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.obUp)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(featured ? 16 : 14)
        .contentShape(Rectangle())
    }

    /// Read by VoiceOver on the row's link, in place of the row's separate texts.
    static func accessibilityText(_ win: NotableWin, topRank: TopListRank?) -> String {
        var text = "Beat \(win.opponentName), rated \(win.opponentRating), at \(win.eventName)"
        if let gap = win.ratingGap, gap > 0 { text += ", \(gap) points above" }
        if let topRank { text += ". Now number \(topRank.rank) on the Top 100, \(topRank.definition.badgeLabel)" }
        return text
    }
}

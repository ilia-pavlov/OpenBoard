import SwiftUI

/// "Best wins": the highest-rated opponents the player has beaten in Regular
/// play, rated as they were going into that event. The top win is featured;
/// the next two sit under it. Each row opens that event's crosstable.
///
/// The first scan of an active player takes a while (one paced request per
/// event), so wins appear as they're found, above a progress line with Pause.
/// A paused scan stays paused (across launches) until Resume, which picks up
/// where it stopped: checked events are cached. Hidden when the finished scan
/// finds no wins over rated opponents, or fails with none.
struct BestWinsCard: View {
    let memberID: String

    @Environment(AppModel.self) private var model
    @State private var progress: BestWinsProgress?
    @State private var stopped = false
    @State private var showsInfo = false
    /// Whose wins `progress` holds; `.task` re-runs on every return to the screen.
    @State private var scannedMemberID: String?
    /// The win opened last, tinted when the user comes back.
    @State private var lastOpenedWinID: String?

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
                                    .background(Color.obGold.opacity(lastOpenedWinID == win.id ? 0.12 : 0))
                                    .animation(.snappy, value: lastOpenedWinID)
                                    .accessibilityAddTraits(lastOpenedWinID == win.id ? .isSelected : [])
                            }
                            .buttonStyle(.plain)
                            .onOpen { lastOpenedWinID = win.id }
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
        .task(id: ScanKey(memberID: memberID, paused: isPaused)) {
            if isPaused {
                await showSaved()
            } else {
                await scan()
            }
        }
    }

    private struct ScanKey: Equatable {
        let memberID: String
        let paused: Bool
    }

    private var isPaused: Bool { model.pausedBestWins.contains(memberID) }

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
        guard !isPaused else { return false }
        let ended = stopped || progress?.isFinished == true
        return ended && (progress?.wins.isEmpty ?? true)
    }

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if isPaused {
                    Image(systemName: "pause.circle.fill")
                        .foregroundStyle(.secondary)
                } else if !stopped {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                if !stopped {
                    pauseButton
                }
            }
            if !stopped, let progress, progress.eventsTotal > 0 {
                ProgressView(value: Double(progress.eventsChecked), total: Double(progress.eventsTotal))
                    .tint(isPaused ? Color.secondary : Color.obGold)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Pause stops the requests at once; Resume continues from the last
    /// checked event.
    private var pauseButton: some View {
        Button {
            withAnimation(.snappy) {
                model.setBestWinsPaused(!isPaused, for: memberID)
            }
        } label: {
            Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.obGold)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.obGold.opacity(0.14), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPaused ? "Resume checking best wins" : "Pause checking best wins")
        .accessibilityIdentifier(AccessibilityID.bestWinsPause)
    }

    private var statusText: String {
        if isPaused {
            guard let progress, progress.eventsTotal > 0 else { return String(localized: "Paused") }
            return String(localized: "Paused · \(progress.eventsChecked) of \(progress.eventsTotal) events checked")
        }
        guard let progress else { return String(localized: "Loading rated games…") }
        if stopped {
            return String(localized: "Couldn't finish: US Chess is busy. Showing wins found so far.")
        }
        let games = progress.gameCount.formatted()
        return String(localized: "Analyzing \(games) games · \(progress.eventsChecked) of \(progress.eventsTotal) events")
    }

    /// Paused with nothing on screen (e.g. after a relaunch): show the wins and
    /// count earlier scans found, from the cache alone.
    private func showSaved() async {
        guard progress == nil || scannedMemberID != memberID else { return }
        scannedMemberID = memberID
        progress = nil
        do {
            for try await step in model.service.bestWinsScan(memberID: memberID, cachedOnly: true) {
                progress = step
            }
        } catch {
            // Nothing saved yet; the row just says Paused.
        }
    }

    private func scan() async {
        // Back from a crosstable: the finished card stays exactly as it was, so
        // the screen keeps its scroll position.
        if scannedMemberID == memberID, progress?.isFinished == true { return }
        if scannedMemberID != memberID {
            progress = nil
            lastOpenedWinID = nil
        }
        scannedMemberID = memberID
        stopped = false
        do {
            for try await step in model.service.bestWinsScan(memberID: memberID) {
                // Resuming a scan left midway: its cached sections replay in a
                // moment; keep the wins on screen until it catches up, so the
                // card never shrinks and shifts the rows below.
                if let shown = progress?.wins, step.wins.count < shown.count, !step.isFinished {
                    progress?.gameCount = step.gameCount
                    progress?.eventsChecked = step.eventsChecked
                    progress?.eventsTotal = step.eventsTotal
                } else {
                    progress = step
                }
            }
        } catch is CancellationError {
            // Left the screen or paused; cached sections let it pick up from here.
        } catch {
            // Pausing cancels in-flight requests, which can surface as errors.
            if !Task.isCancelled && !isPaused { stopped = true }
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
            Text("The first check can take a few minutes for players with lots of games. Pause stops it and Resume picks up where it left off; after that it's instant.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 300, alignment: .leading)
        .padding(18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.bestWinsInfoPopover)
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

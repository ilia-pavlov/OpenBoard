import SwiftUI

/// "Best wins": the highest-rated opponents the player has beaten in Regular
/// play, rated as they were going into that event. The top win is featured;
/// the next two sit under it. Each row opens that event's crosstable.
/// Hidden when the player has no wins over rated opponents, or when loading fails.
struct BestWinsCard: View {
    let memberID: String

    @Environment(AppModel.self) private var model
    @State private var state: Loadable<[NotableWin]> = .idle

    var body: some View {
        switch state {
        case .idle, .loading:
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Best wins")
                    .padding(.top, 8)
                SkeletonCard(height: 132)
            }
            .task(id: memberID) { await load() }
        case .loaded(let wins) where !wins.isEmpty:
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Best wins")
                    .padding(.top, 8)
                VStack(spacing: 0) {
                    ForEach(Array(wins.enumerated()), id: \.element.id) { index, win in
                        if index > 0 {
                            Divider().padding(.leading, 16)
                        }
                        NavigationLink(value: Destination.event(id: win.eventID, highlight: memberID)) {
                            BestWinRow(win: win, featured: index == 0)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(AccessibilityID.bestWin(win.opponentID))
                    }
                }
                .obCard()
            }
            .accessibilityIdentifier(AccessibilityID.bestWins)
        default:
            EmptyView()
        }
    }

    private func load() async {
        state = .loading
        do {
            state = .loaded(try await model.service.bestWins(memberID: memberID))
        } catch {
            state = .failed(message: error.localizedDescription, cached: nil, cachedAt: nil)
        }
    }
}

private struct BestWinRow: View {
    let win: NotableWin
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var text = "Beat \(win.opponentName), rated \(win.opponentRating), at \(win.eventName)"
        if let gap = win.ratingGap, gap > 0 { text += ", \(gap) points above" }
        return text
    }
}

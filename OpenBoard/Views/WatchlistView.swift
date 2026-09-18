import SwiftUI
import SwiftData

struct WatchlistView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \WatchedPlayer.sortOrder) private var watched: [WatchedPlayer]
    @State private var isChecking = false

    private var primary: [WatchedPlayer] { watched.filter(\.isPrimary) }
    private var rivals: [WatchedPlayer] { watched.filter { !$0.isPrimary } }

    var body: some View {
        List {
            if watched.isEmpty {
                Section {
                    EmptyStateCard(systemImage: "heart",
                                   title: "Nobody on the board yet",
                                   message: "Open any player and tap ♥ Watch to track their rating here.")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            if !primary.isEmpty {
                Section("My players") {
                    ForEach(primary) { row in
                        watchRow(row, tint: .obGold)
                    }
                    .onDelete { unfollow(from: primary, at: $0) }
                }
            }

            if !rivals.isEmpty {
                Section("Rivals & friends") {
                    ForEach(rivals) { row in
                        watchRow(row, tint: .obTeal)
                    }
                    .onDelete { unfollow(from: rivals, at: $0) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier(AccessibilityID.Screen.watching)
        .background(Color.obBackground)
        .navigationTitle("Watching")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    checkNow()
                } label: {
                    if isChecking {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isChecking)
                .accessibilityLabel("Check ratings now")
            }
        }
        .refreshable { await runCheck() }
    }

    // MARK: - Rows

    private func watchRow(_ row: WatchedPlayer, tint: Color) -> some View {
        NavigationLink(value: Destination.player(id: row.memberID)) {
            HStack(spacing: 12) {
                InitialsAvatar(name: row.name, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if row.isPrimary {
                            Image(systemName: "crown.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.obGold)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(Format.daysAgo(row.lastRatedDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        PlayerTopBadge(memberID: row.memberID)
                    }
                }
                Spacer()
                ClockDigits(value: row.lastKnownRegular,
                            tint: row.isPrimary ? .obGold : .obTeal,
                            size: .body)
            }
        }
        .contextMenu {
            if !row.isPrimary {
                Button {
                    model.setPrimary(row.memberID)
                } label: {
                    Label("Make primary", systemImage: "crown")
                }
            }
            Button(role: .destructive) {
                context.delete(row)
                try? context.save()
            } label: {
                Label("Unfollow", systemImage: "heart.slash")
            }
        }
        .accessibilityIdentifier(AccessibilityID.watchRow(row.memberID))
    }

    private func unfollow(from rows: [WatchedPlayer], at offsets: IndexSet) {
        for index in offsets { context.delete(rows[index]) }
        try? context.save()
    }

    // MARK: - Manual poll

    private func checkNow() {
        isChecking = true
        Task {
            await runCheck()
            isChecking = false
        }
    }

    private func runCheck() async {
        await RefreshScheduler.checkWatchlist(container: model.container, service: model.service)
    }
}

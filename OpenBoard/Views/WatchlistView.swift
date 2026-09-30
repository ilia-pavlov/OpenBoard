import SwiftUI
import SwiftData

struct WatchlistView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \WatchedPlayer.sortOrder) private var watched: [WatchedPlayer]
    // Soonest first; undated (recurring series) last.
    @Query(sort: \SavedTournament.startDate) private var savedTournaments: [SavedTournament]
    @State private var isChecking = false
    @State private var editMode: EditMode = .inactive

    private var primary: [WatchedPlayer] { watched.filter(\.isPrimary) }
    private var rivals: [WatchedPlayer] { watched.filter { !$0.isPrimary } }

    var body: some View {
        VStack(spacing: 0) {
            ScreenTitle("Watching") {
                HStack(spacing: 18) {
                    if watched.count > 1 { editButton }
                    refreshButton
                }
            }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            list
        }
        .background(Color.obBackground)
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.editMode, $editMode)
    }

    /// Edit shows drag handles for reordering players (a long press and drag
    /// works too, outside Edit).
    private var editButton: some View {
        Button(editMode.isEditing ? "Done" : "Edit") {
            withAnimation { editMode = editMode.isEditing ? .inactive : .active }
        }
        .font(.body.weight(editMode.isEditing ? .semibold : .regular))
        .foregroundStyle(Color.obGold)
        .accessibilityIdentifier(AccessibilityID.watchlistEdit)
    }

    private var refreshButton: some View {
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

    private var list: some View {
        List {
            if !savedTournaments.isEmpty {
                Section("Saved tournaments") {
                    ForEach(savedTournaments) { row in
                        savedTournamentRow(row)
                            .deleteDisabled(editMode.isEditing) // Edit is for Rivals & friends only
                    }
                    .onDelete { offsets in
                        for index in offsets { model.removeSaved(savedTournaments[index]) }
                    }
                }
            }

            if watched.isEmpty && savedTournaments.isEmpty {
                Section {
                    EmptyStateCard(systemImage: "heart",
                                   title: "Nothing on the board yet",
                                   message: "Open any player and tap ♥ Watch to track their rating, or save a tournament from Events to keep it here.")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            if !primary.isEmpty {
                Section("My players") {
                    ForEach(primary) { row in
                        watchRow(row, tint: .obGold)
                            .deleteDisabled(editMode.isEditing) // Edit is for Rivals & friends only
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
                    .onMove { source, destination in
                        var reordered = rivals
                        reordered.move(fromOffsets: source, toOffset: destination)
                        // My players stay first; rivals follow in the new order.
                        model.reorderWatched(primary + reordered)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier(AccessibilityID.Screen.watching)
        .refreshable { await runCheck() }
    }

    // MARK: - Rows

    private func savedTournamentRow(_ row: SavedTournament) -> some View {
        NavigationLink(value: Destination.upcomingTournament(id: row.id)) {
            HStack(spacing: 12) {
                Image(systemName: "bookmark.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.obGold)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if let caption = savedCaption(row) {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .accessibilityIdentifier(AccessibilityID.savedTournament(row.id))
    }

    /// "Sep 27 · Princeton, NJ", dropping whichever half is missing.
    private func savedCaption(_ row: SavedTournament) -> String? {
        let when = row.startDate.map { start -> String in
            // Most events are one day; a range of it to itself reads as
            // "Sun, Sep 27 - Sun, Sep 27".
            guard let end = row.endDate,
                  !Calendar.current.isDate(start, inSameDayAs: end) else {
                return Format.eventDate(start)
            }
            return Format.dateRange(start, end)
        }
        let parts = [when, row.location].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

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
                    // Side by side when they fit; stacked when the row is narrow
                    // (Edit mode's handles, large text) instead of squeezing the date.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            lastRated(row)
                            PlayerTopBadge(memberID: row.memberID)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            lastRated(row)
                            PlayerTopBadge(memberID: row.memberID)
                        }
                    }
                }
                // Fill the row up to the rating so the name gets all the room there
                // is; the rating never shrinks, so only a long name truncates.
                .frame(maxWidth: .infinity, alignment: .leading)
                ClockDigits(value: row.lastKnownRegular,
                            tint: row.isPrimary ? .obGold : .obTeal,
                            size: .body)
                    .fixedSize()
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

    private func lastRated(_ row: WatchedPlayer) -> some View {
        Text(Format.daysAgo(row.lastRatedDate))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
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

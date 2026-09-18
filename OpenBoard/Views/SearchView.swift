import SwiftUI
import SwiftData

enum SearchScope: String, CaseIterable {
    case players = "Players"
    case tournaments = "Tournaments"
}

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \RecentSearch.searchedAt, order: .reverse) private var recents: [RecentSearch]

    @State private var query = ""
    @State private var scope: SearchScope = .players
    @State private var results: [PlayerSummary] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        List {
            if query.isEmpty {
                browseSection
                recentsSection
            } else if scope == .tournaments {
                tournamentSection
            } else {
                playerResultsSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.obBackground)
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Name, member ID, or event ID")
        .searchScopes($scope, activation: .onSearchPresentation) {
            ForEach(SearchScope.allCases, id: \.self) { s in
                Text(s.rawValue).tag(s)
            }
        }
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .onChange(of: query) { _, newValue in
            scheduleSearch(newValue)
        }
        .onChange(of: scope) { _, _ in
            scheduleSearch(query, debounce: false)
        }
    }

    // MARK: - Sections

    private var browseSection: some View {
        Section {
            NavigationLink(value: Destination.topLists) {
                HStack(spacing: 14) {
                    Image(systemName: "medal.fill")
                        .font(.title2)
                        .foregroundStyle(Color.obGold)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Top 100 lists")
                            .font(.subheadline.weight(.semibold))
                        Text("Best US Chess players by age: 7 & under through 18, girls, seniors")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .accessibilityIdentifier("browse-top-100")
        }
    }

    private var recentsSection: some View {
        Section {
            if recents.isEmpty {
                EmptyStateCard(systemImage: "magnifyingglass",
                               title: "Find anyone rated by US Chess",
                               message: "Type a name (\"pavlov\"), an 8-digit member ID, or switch to Tournaments and paste a 12-digit event ID.")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(recents.prefix(8)) { recent in
                    Button {
                        query = recent.query
                    } label: {
                        Label(recent.query, systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(.primary)
                    }
                }
            }
        } header: {
            if !recents.isEmpty { Text("Recent") }
        }
    }

    @ViewBuilder
    private var playerResultsSection: some View {
        Section {
            if isSearching && results.isEmpty {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonCard(height: 56)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else if let errorMessage {
                ErrorCard(message: errorMessage, cachedAt: nil) {
                    scheduleSearch(query, debounce: false)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if results.isEmpty && !isSearching {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(results) { player in
                    NavigationLink(value: Destination.player(id: player.id)) {
                        PlayerSummaryRow(player: player)
                    }
                    .accessibilityIdentifier("search-result-\(player.id)")
                }
            }
        }
    }

    private var tournamentSection: some View {
        Section {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if trimmed.count == 12, trimmed.allSatisfy(\.isNumber) {
                NavigationLink(value: Destination.event(id: trimmed, highlight: model.primaryMemberID)) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open crosstable")
                                .font(.subheadline.weight(.semibold))
                            Text("Event \(trimmed)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(Color.obGold)
                    }
                }
            } else {
                Text("Tournament lookup uses the 12-digit US Chess event ID (year, month, day, then a sequence number).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Debounced search

    private func scheduleSearch(_ text: String, debounce: Bool = true) {
        searchTask?.cancel()
        errorMessage = nil
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, scope == .players else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            if debounce {
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard !Task.isCancelled else { return }
            do {
                let found = try await model.service.search(trimmed)
                guard !Task.isCancelled else { return }
                results = found
                isSearching = false
                model.rememberSearch(trimmed)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                isSearching = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Result row

struct PlayerSummaryRow: View {
    var player: PlayerSummary

    var body: some View {
        HStack(spacing: 12) {
            InitialsAvatar(name: player.name)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(player.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let state = player.state {
                        Text(state)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.obTeal.opacity(0.16), in: Capsule())
                            .foregroundStyle(Color.obTeal)
                    }
                }
                HStack(spacing: 6) {
                    Text("ID \(player.id)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    PlayerTopBadge(memberID: player.id)
                }
            }
            Spacer()
            ClockDigits(value: player.regular, size: .body)
        }
        .accessibilityElement(children: .combine)
    }
}

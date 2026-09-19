import SwiftUI
import SwiftData

/// Events tab: upcoming tournaments to play (near you or major events), and
/// results — the primary player's recent events plus direct event-ID entry.
struct EventsView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case upcoming = "Upcoming"
        case results = "Results"
        var id: Self { self }
    }

    @Environment(AppModel.self) private var model
    @Query(filter: #Predicate<WatchedPlayer> { $0.isPrimary },
           sort: \WatchedPlayer.sortOrder) private var primaries: [WatchedPlayer]
    @State private var eventIDInput = ""
    @State private var state: Loadable<Player> = .idle
    @State private var mode: Mode = .upcoming

    private var primaryMemberID: String? { primaries.first?.memberID }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ScreenTitle("Events")
                Picker("Events", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0).accessibilityIdentifier(AccessibilityID.segment("events", "\($0)")) }
                }
                .pickerStyle(.segmented)

                if mode == .upcoming {
                    UpcomingTournamentsSection()
                } else {
                    resultsContent
                }
            }
            .padding(16)
        }
        .accessibilityIdentifier(AccessibilityID.Screen.events)
        .background(Color.obBackground)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: primaryMemberID) { await load(force: false) }
        .refreshable { await load(force: true) }
    }

    @ViewBuilder
    private var resultsContent: some View {
        idEntryCard

        switch state {
        case .idle, .loading:
            if primaryMemberID != nil {
                SkeletonCard(height: 64)
                SkeletonCard(height: 64)
            }
        case .loaded(let player):
            recentEvents(player)
        case .failed(let message, let cached, let cachedAt):
            ErrorCard(message: message, cachedAt: cachedAt) {
                Task { await load(force: true) }
            }
            if let cached { recentEvents(cached) }
        }

        joinCard
    }

    // MARK: - Event-ID entry

    private var idEntryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Open a crosstable")
            HStack(spacing: 10) {
                TextField("12-digit event ID", text: $eventIDInput)
                    .keyboardType(.numberPad)
                    .font(.body.monospaced())
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.obBackground, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.obHairline))
                NavigationLink(value: Destination.event(id: eventIDInput,
                                                        highlight: primaryMemberID)) {
                    Image(systemName: "arrow.right")
                        .font(.headline)
                }
                .buttonStyle(.glassProminent)
                .disabled(!isValidEventID)
            }
            Text("Find the 12-digit event ID on any US Chess rating report or crosstable (year, month, day, then a sequence number).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .obCard()
    }

    // MARK: - Join US Chess (no rating yet)

    /// Official US Chess membership sign-up (verified live 2026-08-08).
    private static let joinURL = URL(string: "https://www.uschess.org/join")!

    private var joinCard: some View {
        Link(destination: Self.joinURL) {
            HStack(spacing: 14) {
                Image(systemName: "person.badge.plus")
                    .font(.title2)
                    .foregroundStyle(Color.obGold)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text("No USCF rating yet?")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Join US Chess to get an official rating — tap to sign up.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.forward")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .obCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("No USCF rating yet? Join US Chess to get an official rating. Opens the US Chess website.")
        .padding(.top, 4)
    }

    private var isValidEventID: Bool {
        let trimmed = eventIDInput.trimmingCharacters(in: .whitespaces)
        return trimmed.count == 12 && trimmed.allSatisfy(\.isNumber)
    }

    // MARK: - Recent events

    @ViewBuilder
    private func recentEvents(_ player: Player) -> some View {
        if !player.events.isEmpty {
            SectionLabel(text: "\(player.firstName)'s recent events")
                .padding(.top, 6)
            ForEach(player.events) { event in
                NavigationLink(value: Destination.event(id: event.id, highlight: player.id)) {
                    EventResultRow(event: event)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func load(force: Bool) async {
        guard let memberID = primaryMemberID else { return }
        if state.value == nil {
            if let (cached, _) = await model.service.cachedPlayer(id: memberID) {
                state = .loaded(cached)
            } else {
                state = .loading
            }
        }
        do {
            state = .loaded(try await model.service.player(id: memberID))
        } catch {
            let cached = await model.service.cachedPlayer(id: memberID)
            state = .failed(message: error.localizedDescription,
                            cached: cached?.0, cachedAt: cached?.1)
        }
    }
}

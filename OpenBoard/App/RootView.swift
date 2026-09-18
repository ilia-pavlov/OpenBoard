import SwiftUI
import SwiftData

struct RootView: View {
    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            SplitRootView()
        } else {
            TabRootView()
        }
    }
}

// MARK: - Shared destination routing

extension View {
    func openBoardDestinations() -> some View {
        navigationDestination(for: Destination.self) { destination in
            switch destination {
            case .player(let id):
                PlayerProfileView(memberID: id)
            case .event(let id, let highlight):
                CrosstableView(eventID: id, highlightMemberID: highlight)
            case .ratingHistory(let player, let system):
                RatingHistoryView(player: player, initialSystem: system)
            }
        }
    }
}

// MARK: - iPhone: 4 tabs

struct TabRootView: View {
    @Environment(AppModel.self) private var model
    @State private var myCardPath: [Destination] = []
    @State private var searchPath: [Destination] = []
    @State private var eventsPath: [Destination] = []
    @State private var watchingPath: [Destination] = []

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            Tab(AppTab.myCard.title, systemImage: AppTab.myCard.systemImage, value: AppTab.myCard) {
                NavigationStack(path: $myCardPath) {
                    MyCardView().openBoardDestinations()
                }
            }
            Tab(AppTab.search.title, systemImage: AppTab.search.systemImage, value: AppTab.search) {
                NavigationStack(path: $searchPath) {
                    SearchView().openBoardDestinations()
                }
            }
            Tab(AppTab.events.title, systemImage: AppTab.events.systemImage, value: AppTab.events) {
                NavigationStack(path: $eventsPath) {
                    EventsView().openBoardDestinations()
                }
            }
            Tab(AppTab.watching.title, systemImage: AppTab.watching.systemImage, value: AppTab.watching) {
                NavigationStack(path: $watchingPath) {
                    WatchlistView().openBoardDestinations()
                }
            }
        }
        .onAppear(perform: handleScreenshotRoute)
    }

    /// `-screen profile|event|history|search|watchlist|events` for demos & screenshots.
    private func handleScreenshotRoute() {
        guard let screen = AppEnvironment.requestedScreen else { return }
        switch screen {
        case "search":
            model.selectedTab = .search
        case "events":
            model.selectedTab = .events
        case "watchlist":
            model.selectedTab = .watching
        case "profile":
            model.selectedTab = .search
            searchPath = [.player(id: AppEnvironment.requestedScreenArg ?? MockRatingsService.samplePlayerID)]
        case "history":
            model.selectedTab = .myCard
            myCardPath = [.ratingHistory(player: MockRatingsService.samplePlayer, system: .regular)]
        case "event":
            model.selectedTab = .events
            eventsPath = [.event(id: MockRatingsService.sampleEventID,
                                 highlight: MockRatingsService.samplePlayerID)]
        default:
            break
        }
    }
}

// MARK: - iPad: split view

private enum SidebarItem: Hashable {
    case tab(AppTab)
    case watched(String)
}

struct SplitRootView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \WatchedPlayer.sortOrder) private var watched: [WatchedPlayer]
    @State private var selection: SidebarItem? = .tab(.myCard)
    @State private var detailPath: [Destination] = []

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(AppTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.systemImage)
                            .tag(SidebarItem.tab(tab))
                    }
                }
                Section("Watching") {
                    ForEach(watched) { row in
                        Label {
                            Text(row.name)
                        } icon: {
                            InitialsAvatar(name: row.name,
                                           tint: row.isPrimary ? .obGold : .obTeal,
                                           size: 26)
                        }
                        .tag(SidebarItem.watched(row.memberID))
                    }
                }
            }
            .navigationTitle("OpenBoard")
        } detail: {
            NavigationStack(path: $detailPath) {
                detailRoot.openBoardDestinations()
            }
            .id(selection) // fresh stack per sidebar choice
        }
        .onAppear(perform: handleScreenshotRoute)
    }

    @ViewBuilder
    private var detailRoot: some View {
        switch selection {
        case .tab(.myCard), nil: MyCardView()
        case .tab(.search): SearchView()
        case .tab(.events): EventsView()
        case .tab(.watching): WatchlistView()
        case .watched(let id): PlayerProfileView(memberID: id)
        }
    }

    private func handleScreenshotRoute() {
        guard let screen = AppEnvironment.requestedScreen else { return }
        switch screen {
        case "search": selection = .tab(.search)
        case "events": selection = .tab(.events)
        case "watchlist": selection = .tab(.watching)
        case "profile": selection = .watched(MockRatingsService.samplePlayerID)
        case "history":
            selection = .tab(.myCard)
            detailPath = [.ratingHistory(player: MockRatingsService.samplePlayer, system: .regular)]
        case "event":
            selection = .tab(.events)
            detailPath = [.event(id: MockRatingsService.sampleEventID,
                                 highlight: MockRatingsService.samplePlayerID)]
        default: break
        }
    }
}

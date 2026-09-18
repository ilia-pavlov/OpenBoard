import Foundation
import Observation

/// Which Top 100 lists each player is on, so any screen can show a badge.
/// Loads every Regular-rating list once in the background (cached 12 h by
/// `CachedRatingsService`); US Chess doesn't publish ages, so being on an
/// age list is the only age signal there is.
@MainActor
@Observable
final class TopListsIndex {
    private(set) var definitions: [TopListDefinition] = []
    private(set) var isLoaded = false
    private var ranksByMember: [String: [TopListRank]] = [:]
    private var isLoading = false

    /// All lists the player is on, best rank first.
    func ranks(for memberID: String) -> [TopListRank] {
        ranksByMember[memberID] ?? []
    }

    /// The badge to show where there's room for one.
    func best(for memberID: String) -> TopListRank? {
        ranks(for: memberID).first
    }

    func load(from service: CachedRatingsService) async {
        guard !isLoaded, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard let all = try? await service.topListDefinitions() else { return }
        definitions = all

        let badgeLists = all.filter { $0.rating == .regular }
        var byMember: [String: [TopListRank]] = [:]
        await withTaskGroup(of: TopList?.self) { group in
            // A few at a time: ~35 small requests, politely.
            var pending = badgeLists.makeIterator()
            for _ in 0..<6 {
                guard let next = pending.next() else { break }
                group.addTask { try? await service.topList(next) }
            }
            for await list in group {
                if let list {
                    for entry in list.entries {
                        byMember[entry.id, default: []].append(
                            TopListRank(definition: list.definition, rank: entry.rank, reportDate: list.reportDate))
                    }
                }
                if let next = pending.next() {
                    group.addTask { try? await service.topList(next) }
                }
            }
        }
        ranksByMember = byMember.mapValues { ranks in
            ranks.sorted { ($0.rank, $0.definition.sortKey) < ($1.rank, $1.definition.sortKey) }
        }
        isLoaded = true
    }
}

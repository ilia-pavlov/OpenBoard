import Testing
import Foundation
@testable import OpenBoard

@Suite("USCF API decoding")
struct DecodingTests {
    @Test func decodesMemberProfile() throws {
        let member = try JSONDecoder().decode(APIMember.self, from: fixture("sample_member"))
        #expect(member.id == "90000001")
        #expect(member.firstName == "ALEX")
        #expect(member.rank == 58_224)
        #expect(member.stateRank == 2_204)

        let ratings = USCFMapper.ratings(from: member.ratings)
        #expect(ratings.regular?.value == 383)
        #expect(ratings.regular?.floor == 131)
        #expect(ratings.regular?.games == 5)
        #expect(ratings.quick?.value == 379)
        #expect(ratings.blitz?.value == nil)
    }

    @Test func decodesMemberSectionsIntoEventResults() throws {
        let page = try JSONDecoder().decode(APIPage<APIMemberSection>.self,
                                            from: fixture("sample_member_sections"))
        let events = USCFMapper.eventResults(from: page.items)
        #expect(!events.isEmpty)

        let event = try #require(events.first { $0.id == "900000000001" })
        #expect(event.regular?.pre == 322)
        #expect(event.regular?.post == 420)
        #expect(event.quick?.pre == 319)
        #expect(event.quick?.post == 415)
        #expect(event.regular?.delta == 98)
    }

    @Test func decodesStandingsWithRounds() throws {
        let page = try JSONDecoder().decode(APIPage<APIStanding>.self,
                                            from: fixture("sample_standings"))
        #expect(!page.items.isEmpty)
        let standings = page.items.map { USCFMapper.standing($0, roundCount: 4) }
        let first = try #require(standings.first)
        #expect(first.rank == 1)
        #expect(first.points == "4.0")
        #expect(first.rounds.count == 4)
        #expect(first.rounds.allSatisfy { ["W", "L", "D", "B", "–"].contains($0.symbol) })
    }

    @Test func decodesSearchResults() throws {
        let page = try JSONDecoder().decode(APIPage<APIMember>.self,
                                            from: fixture("sample_search"))
        let summaries = page.items.map(USCFMapper.summary)
        #expect(!summaries.isEmpty)
        // USCF stores names in ALL CAPS; mapper should title-case them.
        #expect(summaries.allSatisfy { $0.name != $0.name.uppercased() || $0.name.count <= 2 })
    }

    @Test func computesPercentilesFromMaxRanks() throws {
        let ranks = try JSONDecoder().decode([APIMaxRank].self, from: fixture("sample_max-ranks"))
        let member = try JSONDecoder().decode(APIMember.self, from: fixture("sample_member"))
        let player = USCFMapper.player(member: member, sections: [], maxRanks: ranks)

        let overall = try #require(player.ranking?.overall)
        #expect(overall.total == 76_379)
        #expect(overall.computedPercentile == 24)

        let state = try #require(player.ranking?.state)
        #expect(state.total == 2_711)
        #expect(state.computedPercentile == 19)
    }
}

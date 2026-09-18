import Testing
import Foundation
@testable import OpenBoard

@Suite("Delta math")
struct DeltaTests {
    @Test func positiveDelta() {
        #expect(PrePost(pre: 322, post: 420, games: 12).delta == 98)
    }

    @Test func negativeDelta() {
        #expect(PrePost(pre: 374, post: 313, games: 20).delta == -61)
    }

    @Test func missingSideYieldsNil() {
        #expect(PrePost(pre: nil, post: 823, games: 4).delta == nil)
        #expect(PrePost(pre: 322, post: nil, games: nil).delta == nil)
    }

    @Test func clockDigitsZeroPad() {
        #expect(383.clockDigits == "0383")
        #expect(1500.clockDigits == "1500")
        #expect(7.clockDigits == "0007")
    }

    @Test func historySeriesIsChronological() {
        let events = USCFMapper.eventResults(from: [])
        #expect(USCFMapper.history(from: events).isEmpty)

        let player = MockRatingsService.samplePlayer
        #expect(player.ratingHistory.last == 420)
        #expect(player.peakRegular == 420)
    }
}

import Testing
import Foundation
@testable import OpenBoard

@Suite("USCF class titles")
struct ClassTitleTests {
    @Test(arguments: [
        (2500, ClassTitle.seniorMaster),
        (2400, .seniorMaster),
        (2399, .nationalMaster),
        (2200, .nationalMaster),
        (2000, .expert),
        (1800, .classA),
        (1600, .classB),
        (1400, .classC),
        (1200, .classD),
        (1000, .classE),
        (800, .classF),
        (600, .classG),
        (400, .classH),
        (383, .classI),
        (200, .classI),
        (199, .classJ),
        (0, .classJ),
    ])
    func titleForRating(rating: Int, expected: ClassTitle) {
        #expect(ClassTitle(rating: rating) == expected)
    }
}

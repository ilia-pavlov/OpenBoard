import XCTest

final class WatchingTests: Runner {
    private let ava = "90000010"    // first rival in demo mode
    private let maya = "90000011"
    private let liam = "90000012"   // last rival

    /// Rivals can be reordered by drag and drop (Edit shows the handles), and
    /// the order sticks after leaving the tab.
    @MainActor
    func testReorderPlayers() {
        launch(.demoSeed, .screen(.watchlist))
        watching.assertOnScreen()
            .assertOrder(ava, above: liam)
            .drag(ava, onto: liam)
            .assertOrder(liam, above: ava)
            .assertOrder(maya, above: ava)
            .selectTab("My Card")
            .selectTab("Watching")
        watching.assertOrder(liam, above: ava)
    }
}

import XCTest

final class CrosstableTests: Runner {
    /// Long section names are chosen from a sheet; picking one shows its standings.
    @MainActor
    func testSectionPicker() {
        launch(.screen(.event))
        crosstable
            .assertOnScreen()
            .assertStanding(Sample.playerID) // opens on the followed player's section
            .openSectionPicker()
            .assertSectionOption(1, name: "Section 2 Open U1200 G/45;d5 (K-12)")
            .chooseSection(1)
            .assertStanding("90000020")
    }

    /// Expanded rows link to the player's profile.
    @MainActor
    func testExpandedRowOpensProfile() {
        launch(.screen(.event))
        crosstable
            .assertOnScreen()
            .tapStanding(Sample.rivalID)
            .tapViewFullProfile(Sample.rivalID)
        profile
            .assertLoaded()
    }
}

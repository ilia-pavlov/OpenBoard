import SwiftUI

/// Screen title drawn in the content rather than as a large navigation title,
/// so a control can sit on its line. Tabs that use it hide their navigation bar.
///
/// Pair with `.toolbar(.hidden, for: .navigationBar)` on the same screen, and
/// move whatever lived in that toolbar into `accessory`.
struct ScreenTitle<Accessory: View>: View {
    private let title: String
    private let accessory: Accessory

    init(_ title: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            accessory
                .font(.title3)
        }
    }
}

extension ScreenTitle where Accessory == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

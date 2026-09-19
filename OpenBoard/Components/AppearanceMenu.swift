import SwiftUI

/// Toolbar control mirroring the Home Screen quick actions, so the preference
/// is reachable without knowing about the long-press menu.
struct AppearanceMenu: View {
    @AppStorage(Appearance.key) private var appearance: Appearance = .default

    var body: some View {
        Menu {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { option in
                    Label(option.title, systemImage: option.systemImage)
                        .tag(option)
                }
            }
        } label: {
            Image(systemName: appearance.systemImage)
        }
        .accessibilityLabel("Appearance: \(appearance.title)")
    }
}

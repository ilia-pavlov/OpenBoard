import SwiftUI

/// Light/dark preference. Dark by default — the palette in Theme.swift is
/// dark-first and the light variants are the fallback, not the other way round.
///
/// Stored in UserDefaults rather than on AppModel because the scene delegate
/// writes it from outside the SwiftUI world when a Home Screen quick action
/// fires; `@AppStorage(Appearance.key)` in the app then picks the change up.
///
/// Shared/ is compiled into the app and the UI test target, so tests can name
/// these raw values without duplicating them.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let key = "appearance"
    static let `default` = Appearance.dark

    var id: String { rawValue }

    /// nil means "follow iOS", including its automatic day/night switching.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    /// The stored preference, readable outside SwiftUI (scene delegate, tests).
    static var current: Appearance {
        UserDefaults.standard.string(forKey: key).flatMap(Appearance.init) ?? .default
    }

    /// Demo/screenshot/UI-test helper: `-appearance light|dark|system` seeds the
    /// stored preference at launch, and `-appearance default` clears it so a test
    /// can assert what a fresh install does. Seeding rather than shadowing keeps
    /// one source of truth — the menu and the rendered theme can't disagree.
    static func applyLaunchArgument() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-appearance"), args.indices.contains(i + 1) else { return }
        let value = args[i + 1]
        if value == "default" {
            UserDefaults.standard.removeObject(forKey: key)
        } else if Appearance(rawValue: value) != nil {
            UserDefaults.standard.set(value, forKey: key)
        }
    }
}

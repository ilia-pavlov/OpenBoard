import SwiftUI
import UIKit

/// Home Screen quick actions (long-press the app icon) for the appearance
/// preference. Built dynamically rather than declared in Info.plist so the
/// active one can be marked — the menu has no checkmark, so the subtitle
/// carries that state — and so the list rebuilds when the choice changes.
enum QuickActions {
    /// `UIApplicationShortcutItem.type` for an appearance action.
    static func type(for appearance: Appearance) -> String { "appearance.\(appearance.rawValue)" }

    static func appearance(for type: String) -> Appearance? {
        guard type.hasPrefix("appearance.") else { return nil }
        return Appearance(rawValue: String(type.dropFirst("appearance.".count)))
    }

    /// Rebuilds the menu, marking `current`. iOS shows at most four items and
    /// there are three, so none are dropped.
    @MainActor
    static func refresh(current: Appearance = .current) {
        UIApplication.shared.shortcutItems = Appearance.allCases.map { appearance in
            UIApplicationShortcutItem(
                type: type(for: appearance),
                localizedTitle: appearance.title,
                localizedSubtitle: appearance == current ? "Current" : nil,
                icon: UIApplicationShortcutIcon(systemImageName: appearance.systemImage),
                userInfo: nil
            )
        }
    }

    /// Applies a tapped action. Returns false when it isn't one of ours.
    @MainActor
    @discardableResult
    static func handle(_ item: UIApplicationShortcutItem) -> Bool {
        guard let appearance = appearance(for: item.type) else { return false }
        UserDefaults.standard.set(appearance.rawValue, forKey: Appearance.key)
        refresh(current: appearance)
        return true
    }
}

// MARK: - Delegates

/// A quick action can't reach a running app through the app delegate in a
/// scene-based app, so the scene delegate below does the work; this exists to
/// point UIKit at it.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Cold launch straight from a quick action: the item arrives here, not in
    /// `windowScene(_:performActionFor:)`.
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let item = connectionOptions.shortcutItem {
            QuickActions.handle(item)
        } else {
            QuickActions.refresh()
        }
    }

    /// The app was already running (foreground or background).
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(QuickActions.handle(shortcutItem))
    }
}

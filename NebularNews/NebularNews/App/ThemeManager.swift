import SwiftUI

/// Manages app-wide color scheme preference (system, light, or dark).
///
/// Persists the user's choice in UserDefaults. When set to `.system`,
/// returns `nil` from `resolvedColorScheme` so SwiftUI follows the
/// device's system setting automatically.
@Observable
@MainActor
final class ThemeManager {
    enum Mode: String, CaseIterable, Identifiable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"

        var id: String { rawValue }
    }

    private static let defaultsKey = "themeMode"

    var mode: Mode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.defaultsKey)
        }
    }

    /// The resolved color scheme, or `nil` to follow the system setting.
    var resolvedColorScheme: ColorScheme? {
        switch mode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.defaultsKey)
        self.mode = saved.flatMap(Mode.init(rawValue:)) ?? .system
    }
}

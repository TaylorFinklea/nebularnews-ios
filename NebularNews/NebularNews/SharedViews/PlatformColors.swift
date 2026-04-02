import SwiftUI

// MARK: - Cross-platform View modifiers
//
// These no-op on macOS for iOS-only modifiers that don't exist in AppKit/macOS SwiftUI.

extension View {
    /// Applies `.navigationBarTitleDisplayMode` on iOS; no-op on macOS.
    @ViewBuilder
    func inlineNavigationBarTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Hides the tab bar on iOS; no-op on macOS.
    @ViewBuilder
    func hideTabBar() -> some View {
        #if os(iOS)
        self.toolbar(.hidden, for: .tabBar)
        #else
        self
        #endif
    }
}

// MARK: - Cross-platform system color shims
//
// UIColor names like `.tertiarySystemFill` and `.secondarySystemGroupedBackground`
// are not available in NSColor on macOS. These static properties provide the
// nearest macOS equivalents so that views using `Color.platformTertiaryFill` etc.
// compile and look reasonable on both platforms.

extension Color {
    /// Equivalent to `Color(.tertiarySystemFill)` on iOS.
    static var platformTertiaryFill: Color {
        #if os(macOS)
        Color(nsColor: .quaternaryLabelColor)
        #else
        Color(.tertiarySystemFill)
        #endif
    }

    /// Equivalent to `Color(.secondarySystemFill)` on iOS.
    static var platformSecondaryFill: Color {
        #if os(macOS)
        Color(nsColor: .tertiaryLabelColor).opacity(0.18)
        #else
        Color(.secondarySystemFill)
        #endif
    }

    /// Equivalent to `Color(.systemBackground)` on iOS.
    static var platformSystemBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }

    /// Equivalent to `Color(.secondarySystemGroupedBackground)` on iOS.
    static var platformSecondaryGroupedBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(.secondarySystemGroupedBackground)
        #endif
    }

    /// Equivalent to `Color(.secondarySystemBackground)` on iOS.
    static var platformSecondaryBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(.secondarySystemBackground)
        #endif
    }
}

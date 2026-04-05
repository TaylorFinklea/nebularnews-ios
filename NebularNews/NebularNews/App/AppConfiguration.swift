import Foundation

struct AppConfiguration {
    static let shared = AppConfiguration(bundle: .main)

    let bundleIdentifier: String
    let keychainService: String
    let backgroundRefreshTaskIdentifier: String

    init(bundle: Bundle) {
        let bundleIdentifier = bundle.bundleIdentifier ?? "com.example.nebularnews.ios"
        self.bundleIdentifier = bundleIdentifier
        self.keychainService = bundle.stringValue(forInfoDictionaryKey: "KeychainService") ?? bundleIdentifier
        self.backgroundRefreshTaskIdentifier =
            bundle.stringValue(forInfoDictionaryKey: "BackgroundRefreshTaskIdentifier")
            ?? "\(bundleIdentifier).feedRefresh"
    }
}

enum PaginationConfig {
    static let defaultPageSize = 30
    static let dashboardPageSize = 10
    static let companionPageSize = 100
}

private extension Bundle {
    func stringValue(forInfoDictionaryKey key: String) -> String? {
        object(forInfoDictionaryKey: key).flatMap { value in
            let trimmed = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

}

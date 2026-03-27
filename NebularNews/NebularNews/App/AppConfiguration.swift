import Foundation

struct AppConfiguration {
    static let shared = AppConfiguration(bundle: .main)

    let bundleIdentifier: String
    let keychainService: String
    let backgroundRefreshTaskIdentifier: String
    let mobileOAuthClientId: String
    let mobileOAuthClientName: String
    let mobileOAuthRedirectURI: URL
    let mobileDefaultServerURL: URL

    init(bundle: Bundle) {
        let bundleIdentifier = bundle.bundleIdentifier ?? "com.example.nebularnews.ios"
        self.bundleIdentifier = bundleIdentifier
        self.keychainService = bundle.stringValue(forInfoDictionaryKey: "KeychainService") ?? bundleIdentifier
        self.backgroundRefreshTaskIdentifier =
            bundle.stringValue(forInfoDictionaryKey: "BackgroundRefreshTaskIdentifier")
            ?? "\(bundleIdentifier).feedRefresh"
        self.mobileOAuthClientId = bundle.stringValue(forInfoDictionaryKey: "MobileOAuthClientId") ?? "nebular-news-ios"
        self.mobileOAuthClientName = bundle.stringValue(forInfoDictionaryKey: "MobileOAuthClientName") ?? "Nebular News iOS"
        self.mobileOAuthRedirectURI =
            URL(string: bundle.stringValue(forInfoDictionaryKey: "MobileOAuthRedirectURI") ?? "nebularnews://oauth/callback")
            ?? URL(string: "nebularnews://oauth/callback")!
        if let serverURL = bundle.stringValue(forInfoDictionaryKey: "MobileDefaultServerURL"),
           !serverURL.isEmpty,
           let url = URL(string: serverURL) {
            self.mobileDefaultServerURL = url
        } else {
            self.mobileDefaultServerURL = URL(string: "https://app.nebularnews.com")!
        }
    }
}

private extension Bundle {
    func stringValue(forInfoDictionaryKey key: String) -> String? {
        object(forInfoDictionaryKey: key).flatMap { value in
            let trimmed = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

}

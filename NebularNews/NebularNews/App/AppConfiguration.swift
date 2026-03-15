import Foundation

struct AppConfiguration {
    static let shared = AppConfiguration(bundle: .main)

    let bundleIdentifier: String
    let keychainService: String
    let backgroundRefreshTaskIdentifier: String
    let backgroundProcessingTaskIdentifier: String
    let cloudKitEnabled: Bool
    let cloudKitContainerIdentifier: String?
    let mobileOAuthClientId: String
    let mobileOAuthClientName: String
    let mobileOAuthRedirectURI: URL
    let mobileDefaultServerURL: URL?

    init(bundle: Bundle) {
        let bundleIdentifier = bundle.bundleIdentifier ?? "com.example.nebularnews.ios"
        self.bundleIdentifier = bundleIdentifier
        self.keychainService = bundle.stringValue(forInfoDictionaryKey: "KeychainService") ?? bundleIdentifier
        self.backgroundRefreshTaskIdentifier =
            bundle.stringValue(forInfoDictionaryKey: "BackgroundRefreshTaskIdentifier")
            ?? "\(bundleIdentifier).feedRefresh"
        self.backgroundProcessingTaskIdentifier =
            bundle.stringValue(forInfoDictionaryKey: "BackgroundProcessingTaskIdentifier")
            ?? "\(bundleIdentifier).articleProcessing"
        self.cloudKitEnabled = bundle.boolValue(forInfoDictionaryKey: "CloudKitEnabled")
        self.cloudKitContainerIdentifier = bundle.stringValue(forInfoDictionaryKey: "CloudKitContainerIdentifier")
        self.mobileOAuthClientId = bundle.stringValue(forInfoDictionaryKey: "MobileOAuthClientId") ?? "nebular-news-ios"
        self.mobileOAuthClientName = bundle.stringValue(forInfoDictionaryKey: "MobileOAuthClientName") ?? "Nebular News iOS"
        self.mobileOAuthRedirectURI =
            URL(string: bundle.stringValue(forInfoDictionaryKey: "MobileOAuthRedirectURI") ?? "nebularnews://oauth/callback")
            ?? URL(string: "nebularnews://oauth/callback")!
        if let serverURL = bundle.stringValue(forInfoDictionaryKey: "MobileDefaultServerURL"), !serverURL.isEmpty {
            self.mobileDefaultServerURL = URL(string: serverURL)
        } else {
            self.mobileDefaultServerURL = nil
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

    func boolValue(forInfoDictionaryKey key: String) -> Bool {
        guard let value = object(forInfoDictionaryKey: key) else { return false }
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        default:
            switch String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                return false
            }
        }
    }
}

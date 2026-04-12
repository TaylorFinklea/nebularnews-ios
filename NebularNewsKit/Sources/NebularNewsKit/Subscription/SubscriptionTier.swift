import Foundation

/// The AI subscription tiers available in NebularNews.
public enum SubscriptionTier: String, Sendable, Codable, CaseIterable {
    case basic
    case pro

    /// StoreKit product identifier. Update these when products are created in App Store Connect.
    public var productId: String {
        switch self {
        case .basic: return "com.nebularnews.ai.basic"
        case .pro: return "com.nebularnews.ai.pro"
        }
    }

    public var displayName: String {
        switch self {
        case .basic: return "AI Basic"
        case .pro: return "AI Pro"
        }
    }

    public var description: String {
        switch self {
        case .basic: return "100K tokens/day, 500K/week"
        case .pro: return "500K tokens/day, 2.5M/week"
        }
    }

    /// All StoreKit product identifiers.
    public static var allProductIds: Set<String> {
        Set(allCases.map(\.productId))
    }

    /// Resolve from a StoreKit product ID.
    public static func from(productId: String) -> SubscriptionTier? {
        allCases.first { $0.productId == productId }
    }
}

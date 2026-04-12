import Foundation
import StoreKit
import os

/// Manages StoreKit 2 auto-renewable subscriptions for NebularNews AI.
///
/// Handles product loading, purchase, restore, and transaction listening.
/// After a successful purchase, sends the transaction to the server for validation.
@MainActor
public final class SubscriptionManager: ObservableObject {

    @Published public private(set) var availableProducts: [Product] = []
    @Published public private(set) var currentTier: SubscriptionTier?
    @Published public private(set) var isLoading = false
    @Published public private(set) var purchaseError: String?

    private let logger = Logger(subsystem: "com.nebularnews", category: "Subscription")
    private var transactionListener: Task<Void, Never>?

    public init() {
        transactionListener = listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    /// Fetch available subscription products from the App Store.
    public func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let products = try await Product.products(for: SubscriptionTier.allProductIds)
            availableProducts = products.sorted { ($0.price as NSDecimalNumber).doubleValue < ($1.price as NSDecimalNumber).doubleValue }
            logger.info("Loaded \(products.count) subscription products")
        } catch {
            logger.error("Failed to load products: \(error.localizedDescription)")
        }
    }

    // MARK: - Purchase

    /// Initiate a purchase for the given product.
    public func purchase(_ product: Product) async -> Bool {
        purchaseError = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updateCurrentEntitlement()
                await transaction.finish()
                logger.info("Purchase succeeded: \(product.id)")
                return true

            case .userCancelled:
                logger.info("Purchase cancelled by user")
                return false

            case .pending:
                logger.info("Purchase pending approval")
                return false

            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            logger.error("Purchase failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Restore

    /// Restore purchases (useful for device transfers).
    public func restorePurchases() async {
        try? await AppStore.sync()
        await updateCurrentEntitlement()
    }

    // MARK: - Entitlement Check

    /// Check current subscription status and update the tier.
    public func updateCurrentEntitlement() async {
        var activeTier: SubscriptionTier?

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }

            if let tier = SubscriptionTier.from(productId: transaction.productID) {
                // If user has multiple (unlikely), take the highest tier.
                if activeTier == nil || tier == .pro {
                    activeTier = tier
                }
            }
        }

        currentTier = activeTier
        logger.info("Current tier: \(activeTier?.rawValue ?? "none")")
    }

    /// Whether the user has any active AI subscription.
    public var hasActiveSubscription: Bool {
        currentTier != nil
    }

    // MARK: - Transaction Listener

    /// Listen for transaction updates (renewals, revocations, etc.)
    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self = self else { return }
                if let transaction = try? self.checkVerified(result) {
                    await self.updateCurrentEntitlement()
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: - Verification

    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }
}

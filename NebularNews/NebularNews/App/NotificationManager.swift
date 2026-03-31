import Foundation
import UserNotifications
import UIKit
import os

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.nebularnews.ios",
    category: "Notifications"
)

final class NotificationManager: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private var deviceToken: String?

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        self.deviceToken = token
        logger.info("APNs device token: \(token.prefix(12))…")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        logger.error("APNs registration failed: \(error.localizedDescription)")
    }

    // MARK: - Permission + Registration

    func requestPermissionAndRegister() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                logger.error("Notification auth error: \(error.localizedDescription)")
                return
            }
            guard granted else {
                logger.info("Notification permission denied")
                return
            }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    // MARK: - Token Upload (Supabase)

    func uploadTokenIfNeeded(supabase: SupabaseManager) async {
        guard let token = deviceToken else { return }
        do {
            try await supabase.registerDeviceToken(token: token)
            logger.info("Device token uploaded via Supabase")
        } catch {
            logger.error("Failed to upload device token via Supabase: \(error.localizedDescription)")
        }
    }

    func removeToken(supabase: SupabaseManager) async {
        guard let token = deviceToken else { return }
        do {
            try await supabase.removeDeviceToken(token: token)
            logger.info("Device token removed via Supabase")
        } catch {
            logger.error("Failed to remove device token via Supabase: \(error.localizedDescription)")
        }
    }

    // MARK: - Token Upload (Legacy MobileAPI)

    func uploadTokenIfNeeded(api: MobileAPIClient) async {
        guard let token = deviceToken else { return }
        do {
            try await api.registerDeviceToken(token: token)
            logger.info("Device token uploaded to server")
        } catch {
            logger.error("Failed to upload device token: \(error.localizedDescription)")
        }
    }

    func removeToken(api: MobileAPIClient) async {
        guard let token = deviceToken else { return }
        do {
            try await api.removeDeviceToken(token: token)
            logger.info("Device token removed from server")
        } catch {
            logger.error("Failed to remove device token: \(error.localizedDescription)")
        }
    }

    // MARK: - Foreground Notification Display

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Notification Tap Handling

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let articleId = userInfo["articleId"] as? String {
            NotificationCenter.default.post(
                name: .openArticleFromNotification,
                object: nil,
                userInfo: ["articleId": articleId]
            )
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let openArticleFromNotification = Notification.Name("openArticleFromNotification")
}

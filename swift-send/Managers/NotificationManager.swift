//
//  NotificationManager.swift
//  swift-send
//

import Foundation
import UserNotifications
import FirebaseAuth

class NotificationManager: NSObject {
    static let shared = NotificationManager()

    private let realtimeManager = RealtimeManager.shared

    override private init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    @MainActor
    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )

            if granted {
                print("✅ Notification permission granted")
            } else {
                print("❌ Notification permission denied")
            }
        } catch {
            print("Error requesting notification permission: \(error)")
        }
    }

    @MainActor
    func sendMessageNotification(
        from senderName: String,
        message: String,
        conversationId: String,
        isGroupChat: Bool
    ) async {
        let content = UNMutableNotificationContent()
        content.title = isGroupChat ? "New Group Message" : senderName
        content.body = isGroupChat ? "\(senderName): \(message)" : message
        content.sound = .default
        content.badge = 1

        // Add conversation ID for tap handling
        content.userInfo = ["conversationId": conversationId]

        // Create trigger (immediate)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)

        // Create request
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("📬 Notification sent: \(senderName)")
        } catch {
            print("Error sending notification: \(error)")
        }
    }

    @MainActor
    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {

    // Handle notifications when app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        print("📱 Received foreground notification: \(userInfo)")

        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        print("👆 Notification tapped: \(userInfo)")

        // Handle navigation based on notification data
        if let conversationId = userInfo["conversationId"] as? String {
            Task { @MainActor in
                // Post notification to navigate to conversation
                NotificationCenter.default.post(
                    name: NSNotification.Name("OpenConversation"),
                    object: nil,
                    userInfo: ["conversationId": conversationId]
                )
            }
        }

        completionHandler()
    }
}

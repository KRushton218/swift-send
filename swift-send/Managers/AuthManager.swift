//
//  AuthManager.swift
//  swift-send
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseDatabase
import UIKit

@MainActor
class AuthManager: ObservableObject {
    @Published var user: User?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var authStateHandler: AuthStateDidChangeListenerHandle?
    private let realtimeManager = RealtimeManager.shared
    private var presenceHeartbeatTimer: Timer?
    private var lifecycleObservers: [NSObjectProtocol] = []

    // Global message listener for notifications
    private var globalConversationListenerHandle: DatabaseHandle?
    private var globalMessageObserverHandles: [String: DatabaseHandle] = [:]
    private var lastSeenMessageCounts: [String: Int] = [:]

    init() {
        registerAuthStateHandler()
        setupLifecycleObservers()
    }

    deinit {
        if let handle = authStateHandler {
            Auth.auth().removeStateDidChangeListener(handle)
        }

        // Stop the timer
        presenceHeartbeatTimer?.invalidate()

        // Remove lifecycle observers
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func registerAuthStateHandler() {
        authStateHandler = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user

                // Set up presence when user signs in
                if let user = user {
                    await self?.setupUserOnSignIn(userId: user.uid, email: user.email ?? "")
                }
            }
        }
    }

    private func setupLifecycleObservers() {
        // Observe when app enters background
        let backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleAppDidEnterBackground()
            }
        }
        lifecycleObservers.append(backgroundObserver)

        // Observe when app enters foreground
        let foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleAppWillEnterForeground()
            }
        }
        lifecycleObservers.append(foregroundObserver)
    }

    private func handleAppDidEnterBackground() async {
        // Stop heartbeat to save battery
        stopPresenceHeartbeat()

        // Update lastOnline one final time before going inactive
        if let userId = user?.uid {
            do {
                try await realtimeManager.updateLastOnline(userId: userId)
            } catch {
                print("Error updating presence on background: \(error)")
            }
        }
    }

    private func handleAppWillEnterForeground() async {
        // Resume heartbeat if user is signed in
        if user != nil {
            startPresenceHeartbeat()
        }
    }

    private func setupUserOnSignIn(userId: String, email: String) async {
        do {
            // Register user in RTDB if not exists
            let existingUser = try await realtimeManager.getUser(userId: userId)
            if existingUser == nil {
                try await realtimeManager.registerUser(userId: userId, email: email, displayName: email)
            }

            // Set presence
            try await realtimeManager.setPresence(userId: userId, name: email)

            // Start presence heartbeat to update every 1 second
            startPresenceHeartbeat()

            // Start global message listener for notifications
            startGlobalMessageListener()

            // Request notification permissions
            await NotificationManager.shared.requestPermission()
        } catch {
            print("Error setting up user: \(error)")
        }
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil

        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func signUp(email: String, password: String) async {
        isLoading = true
        errorMessage = nil

        do {
            try await Auth.auth().createUser(withEmail: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func signOut() {
        // Stop presence heartbeat
        stopPresenceHeartbeat()

        // Stop global message listener
        stopGlobalMessageListener()

        // Update last online before signing out
        if let userId = user?.uid {
            Task {
                try? await realtimeManager.updateLastOnline(userId: userId)
            }
        }

        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Global Message Listener

    private func startGlobalMessageListener() {
        guard let userId = user?.uid else { return }

        print("🌐 Starting global message listener for user \(userId)")

        // Observe all conversations user is part of
        globalConversationListenerHandle = realtimeManager.observeConversations(for: userId) { [weak self] conversations in
            guard let self = self else { return }

            Task { @MainActor in
                print("🌐 Global listener: Found \(conversations.count) conversations")

                // Set up message observers for each conversation
                for conversation in conversations {
                    // Skip if already observing this conversation
                    if self.globalMessageObserverHandles[conversation.id] != nil {
                        continue
                    }

                    // Observe messages in this conversation
                    let handle = self.realtimeManager.observeMessages(for: conversation.id) { [weak self] messages in
                        guard let self = self else { return }

                        Task { @MainActor in
                            await self.handleGlobalMessagesUpdate(conversationId: conversation.id, messages: messages)
                        }
                    }

                    self.globalMessageObserverHandles[conversation.id] = handle
                    print("🌐 Now observing messages in conversation \(conversation.id)")
                }
            }
        }
    }

    private func handleGlobalMessagesUpdate(conversationId: String, messages: [Message]) async {
        guard let currentUserId = user?.uid else { return }

        // Count messages from others (not sent by current user)
        let messagesFromOthers = messages.filter { $0.senderId != currentUserId }
        let currentCount = messagesFromOthers.count

        // Get last seen count
        let lastSeenCount = lastSeenMessageCounts[conversationId] ?? 0

        // Check if there are NEW messages
        if currentCount > lastSeenCount {
            let newMessageCount = currentCount - lastSeenCount
            print("🔔 \(newMessageCount) new message(s) in conversation \(conversationId)")

            // Get the newest messages
            let newMessages = Array(messagesFromOthers.suffix(newMessageCount))

            // Send notification for each new message
            for message in newMessages {
                // Get sender info
                guard let senderUser = try? await realtimeManager.getUser(userId: message.senderId) else {
                    continue
                }

                let senderName = senderUser.displayName ?? senderUser.email

                // Get conversation info to determine if it's a group chat
                // For now, we'll use a simple heuristic - fetch participant count
                // In a real implementation, you'd want to cache this info
                let isGroupChat = false // We can enhance this later

                // Trigger local notification
                await NotificationManager.shared.sendMessageNotification(
                    from: senderName,
                    message: message.text,
                    conversationId: conversationId,
                    isGroupChat: isGroupChat
                )
            }
        }

        // Update last seen count
        lastSeenMessageCounts[conversationId] = currentCount
    }

    private func stopGlobalMessageListener() {
        print("🌐 Stopping global message listener")

        // Remove conversation observer
        if globalConversationListenerHandle != nil {
            // Note: We'd need the path to remove this properly
            // For now, we'll let it clean up naturally
            globalConversationListenerHandle = nil
        }

        // Remove all message observers
        for (conversationId, handle) in globalMessageObserverHandles {
            realtimeManager.removeObserver(handle: handle, path: "conversations/\(conversationId)/messages")
        }
        globalMessageObserverHandles.removeAll()
        lastSeenMessageCounts.removeAll()

        print("🌐 Global message listener stopped")
    }

    // MARK: - Presence Heartbeat

    private func startPresenceHeartbeat() {
        // Stop any existing timer
        stopPresenceHeartbeat()

        // Create timer that fires every 1 second
        presenceHeartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor in
                guard let userId = self.user?.uid else { return }

                do {
                    try await self.realtimeManager.updateLastOnline(userId: userId)
                } catch {
                    print("Error updating presence heartbeat: \(error)")
                }
            }
        }
    }

    private func stopPresenceHeartbeat() {
        presenceHeartbeatTimer?.invalidate()
        presenceHeartbeatTimer = nil
    }
}

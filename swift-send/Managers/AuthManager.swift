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
    @Published var activeConversationId: String? // Track which chat is currently active

    private var authStateHandler: AuthStateDidChangeListenerHandle?
    private let realtimeManager = RealtimeManager.shared
    nonisolated(unsafe) private var presenceHeartbeatTimer: Timer?
    private var lifecycleObservers: [NSObjectProtocol] = []

    // Global message listener for notifications
    private var globalConversationListenerHandle: DatabaseHandle?
    private var globalMessageObserverHandles: [String: DatabaseHandle] = [:]
    private var lastSeenMessageIds: [String: String] = [:] // conversationId: lastMessageId

    init() {
        registerAuthStateHandler()
        setupLifecycleObservers()
    }

    deinit {
        if let handle = authStateHandler {
            Auth.auth().removeStateDidChangeListener(handle)
        }

        // Stop presence heartbeat timer
        presenceHeartbeatTimer?.invalidate()

        // Remove lifecycle observers
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }

        // Stop global message listener (must be done synchronously in deinit)
        // Remove all message observers
        for (conversationId, handle) in globalMessageObserverHandles {
            realtimeManager.removeObserver(handle: handle, path: "conversations/\(conversationId)/messages")
        }
        // Note: globalConversationListenerHandle cleanup handled by Firebase automatically
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

        // Mark as offline before going inactive
        if let userId = user?.uid {
            do {
                try await realtimeManager.setOffline(userId: userId)
            } catch {
                print("Error setting offline on background: \(error)")
            }
        }
    }

    private func handleAppWillEnterForeground() async {
        // Mark as online and resume heartbeat if user is signed in
        if let userId = user?.uid {
            do {
                try await realtimeManager.setOnline(userId: userId)
            } catch {
                print("Error setting online on foreground: \(error)")
            }
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

        // Mark as offline before signing out
        if let userId = user?.uid {
            Task {
                try? await realtimeManager.setOffline(userId: userId)
            }
        }

        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Presence Heartbeat

    private func startPresenceHeartbeat() {
        // Stop any existing timer
        stopPresenceHeartbeat()

        // Create timer that fires every 1 second
        presenceHeartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let userId = self.user?.uid else { return }

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
                            await self.handleGlobalMessagesUpdate(
                                conversationId: conversation.id,
                                messages: messages,
                                participantCount: conversation.participants.count
                            )
                        }
                    }

                    self.globalMessageObserverHandles[conversation.id] = handle
                    print("🌐 Now observing messages in conversation \(conversation.id)")
                }
            }
        }
    }

    private func handleGlobalMessagesUpdate(
        conversationId: String,
        messages: [Message],
        participantCount: Int
    ) async {
        guard let currentUserId = user?.uid else { return }

        // Filter messages from others (not sent by current user)
        let messagesFromOthers = messages.filter { $0.senderId != currentUserId }

        // Get last seen message ID for this conversation
        let lastSeenMessageId = lastSeenMessageIds[conversationId]

        // Find new messages since last seen
        var newMessages: [Message] = []

        if let lastSeenId = lastSeenMessageId {
            // Find all messages after the last seen message
            if let lastSeenIndex = messagesFromOthers.firstIndex(where: { $0.id == lastSeenId }) {
                newMessages = Array(messagesFromOthers.suffix(from: lastSeenIndex + 1))
            } else {
                // Last seen message not found - might have been deleted
                // Only notify about the very latest message to avoid spam
                if let latestMessage = messagesFromOthers.last {
                    newMessages = [latestMessage]
                }
            }
        } else {
            // First time observing this conversation
            // Only notify about the very latest message to avoid spam on app launch
            if let latestMessage = messagesFromOthers.last {
                newMessages = [latestMessage]
            }
        }

        // ALWAYS update last seen message ID, even if we suppress notification
        // This prevents batching notifications when user leaves the conversation
        if let latestMessage = messagesFromOthers.last {
            lastSeenMessageIds[conversationId] = latestMessage.id
        }

        // Don't send notifications for the active conversation (but we still updated lastSeenMessageIds above)
        if activeConversationId == conversationId {
            if !newMessages.isEmpty {
                print("🔕 Suppressing \(newMessages.count) notification(s) - user is viewing conversation \(conversationId)")
            }
            return
        }

        // Send notification for each new message
        if !newMessages.isEmpty {
            print("🔔 \(newMessages.count) new message(s) in conversation \(conversationId)")

            for message in newMessages {
                // Get sender info
                guard let senderUser = try? await realtimeManager.getUser(userId: message.senderId) else {
                    continue
                }

                let senderName = senderUser.displayName ?? senderUser.email
                let isGroupChat = participantCount > 2

                // Trigger local notification
                await NotificationManager.shared.sendMessageNotification(
                    from: senderName,
                    message: message.text,
                    conversationId: conversationId,
                    isGroupChat: isGroupChat
                )
            }
        }
    }

    func stopGlobalMessageListener() {
        print("🌐 Stopping global message listener")

        // Remove all message observers
        for (conversationId, handle) in globalMessageObserverHandles {
            realtimeManager.removeObserver(handle: handle, path: "conversations/\(conversationId)/messages")
        }
        globalMessageObserverHandles.removeAll()
        lastSeenMessageIds.removeAll()

        // Note: Conversation observer is handled by RealtimeManager
        // We just clear the handle reference
        globalConversationListenerHandle = nil

        print("🌐 Global message listener stopped")
    }
}

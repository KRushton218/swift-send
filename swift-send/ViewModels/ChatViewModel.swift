//
//  ChatViewModel.swift
//  swift-send
//

import Foundation
import Combine
import FirebaseDatabase

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var messageText: String = ""
    @Published var isLoading = false
    @Published var participantInfo: [ParticipantInfo] = []
    @Published var isActive = false  // Track if this chat view is currently active
    @Published var typingUsers: [TypingIndicator] = []  // Who is currently typing
    @Published var isConnected: Bool = true  // Firebase connection status

    let conversationId: String
    let currentUserId: String
    let participants: [String]

    private var messagesObserverHandle: DatabaseHandle?
    private var presenceObserverHandles: [String: DatabaseHandle] = [:]
    private var typingObserverHandle: DatabaseHandle?
    private var connectionObserverHandle: DatabaseHandle?
    private let realtimeManager = RealtimeManager.shared
    private let presenceManager = PresenceManager.shared
    private var timerCancellable: AnyCancellable?
    private var typingTimer: Timer?
    private var lastTypingUpdate: Date?
    private let typingDebounceInterval: TimeInterval = 1.0  // Max 1 update per second
    private let typingTimeoutInterval: TimeInterval = 5.0   // Clear after 5 seconds of inactivity

    // Pending messages queue for offline support
    private var pendingMessages: [String: Message] = [:]  // messageId: message

    init(conversationId: String, currentUserId: String, participants: [String]) {
        self.conversationId = conversationId
        self.currentUserId = currentUserId
        self.participants = participants
        loadMessages()
        markMessagesAsRead()
        observeParticipantPresence()
        observeTypingIndicators()
        observeConnectionState()
        startPresenceTimer()
    }

    deinit {
        if let handle = messagesObserverHandle {
            realtimeManager.removeObserver(handle: handle, path: "conversations/\(conversationId)/messages")
        }

        // Remove all presence observers
        for (userId, handle) in presenceObserverHandles {
            realtimeManager.removeObserver(handle: handle, path: "presence/\(userId)")
        }

        // Remove typing observer
        if let handle = typingObserverHandle {
            realtimeManager.removeObserver(handle: handle, path: "typing/\(conversationId)")
        }

        // Remove connection observer
        if let handle = connectionObserverHandle {
            realtimeManager.removeObserver(handle: handle, path: ".info/connected")
        }

        // Cancel timers
        timerCancellable?.cancel()
        typingTimer?.invalidate()

        // Note: Typing state will be cleared automatically by Firebase's onDisconnect handler
        // set in RealtimeManager.setTyping(). We don't call clearTypingState() here to avoid
        // retain cycles from creating Tasks in deinit.
    }

    private func loadMessages() {
        messagesObserverHandle = realtimeManager.observeMessages(for: conversationId) { [weak self] firebaseMessages in
            guard let self = self else { return }
            Task { @MainActor in
                // Merge Firebase messages with pending local messages
                // Keep pending messages that are still sending or failed
                let pendingLocalMessages = self.messages.filter { message in
                    self.pendingMessages.keys.contains(message.id) &&
                    (message.status == .sending || message.status == .failed)
                }

                // Combine Firebase messages with pending local messages
                var allMessages = firebaseMessages
                for pending in pendingLocalMessages {
                    // Only add if not already in Firebase messages (by text/timestamp match)
                    let isDuplicate = firebaseMessages.contains { fb in
                        fb.text == pending.text &&
                        fb.senderId == pending.senderId &&
                        abs(fb.timestamp - pending.timestamp) < 5000 // Within 5 seconds
                    }

                    if !isDuplicate {
                        allMessages.append(pending)
                    } else {
                        // Firebase has it - remove from pending queue
                        self.pendingMessages.removeValue(forKey: pending.id)
                    }
                }

                // Sort by timestamp
                self.messages = allMessages.sorted { $0.timestamp < $1.timestamp }

                // Mark new messages as read when they arrive
                await self.markNewMessagesAsRead()
            }
        }
    }

    // NOTE: Notification handling is now done globally by AuthManager
    // This eliminates duplicate notifications and ensures notifications
    // work for all conversations, even those not currently open

    private func markNewMessagesAsRead() async {
        for message in messages where !message.isReadBy(userId: currentUserId) && message.senderId != currentUserId {
            do {
                try await realtimeManager.markMessageAsRead(
                    conversationId: conversationId,
                    messageId: message.id,
                    userId: currentUserId
                )
            } catch {
                // Silently fail - non-critical operation
            }
        }
    }

    func markMessagesAsRead() {
        Task {
            do {
                // Find the senderId - it's whoever is NOT the current user
                let otherParticipants = participants.filter { $0 != currentUserId }
                let senderId = otherParticipants.first ?? ""

                try await realtimeManager.markConversationMessagesAsRead(
                    conversationId: conversationId,
                    userId: currentUserId,
                    senderId: senderId
                )
            } catch {
                // Silently fail - non-critical operation
            }
        }
    }

    func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let text = messageText
        messageText = ""

        // Clear typing indicator when sending message
        Task {
            try? await clearTypingState()
        }

        // Create optimistic message with local ID
        let messageId = UUID().uuidString
        let optimisticMessage = Message(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            text: text,
            timestamp: Date().timeIntervalSince1970 * 1000, // Convert to milliseconds
            status: .sending,
            readBy: [currentUserId: Date().timeIntervalSince1970 * 1000]
        )

        // Show immediately in UI (optimistic update)
        messages.append(optimisticMessage)
        pendingMessages[messageId] = optimisticMessage

        // Actually send to Firebase
        Task {
            do {
                _ = try await realtimeManager.sendMessage(
                    conversationId: conversationId,
                    senderId: currentUserId,
                    text: text
                )

                // Success - remove from pending queue
                // Firebase observer will update the message with server data
                pendingMessages.removeValue(forKey: messageId)
                print("✅ Message sent successfully")

            } catch {
                // Failed - mark as failed
                var failedMessage = optimisticMessage
                failedMessage.status = .failed
                pendingMessages[messageId] = failedMessage

                // Update UI
                if let index = messages.firstIndex(where: { $0.id == messageId }) {
                    messages[index] = failedMessage
                }

                print("❌ Message failed to send: \(error.localizedDescription)")
            }
        }
    }

    func getReadByNames() async -> [String: String] {
        var names: [String: String] = [:]

        for userId in participants where userId != currentUserId {
            do {
                if let user = try await realtimeManager.getUser(userId: userId) {
                    names[userId] = user.displayName ?? user.email
                }
            } catch {
                // Silently fail - user name will show as Unknown
            }
        }

        return names
    }

    private func observeParticipantPresence() {
        // Observe presence for all participants except current user
        let otherParticipants = participants.filter { $0 != currentUserId }

        for userId in otherParticipants {
            let handle = realtimeManager.observePresence(userId: userId) { [weak self] presence in
                guard let self = self else { return }
                Task { @MainActor in
                    await self.updateParticipantInfo(userId: userId, presence: presence)
                }
            }
            presenceObserverHandles[userId] = handle
        }
    }

    private func updateParticipantInfo(userId: String, presence: Presence?) async {
        // Get user info
        guard let user = try? await realtimeManager.getUser(userId: userId) else {
            return
        }

        let name = user.displayName ?? user.email
        let isOnline = presence?.isOnline ?? false
        let lastOnline = presence?.lastOnline

        // Create participant info with explicit status
        let info = ParticipantInfo(
            id: userId,
            name: name,
            isOnline: isOnline,
            lastOnline: lastOnline
        )

        // Update or add participant info
        if let index = participantInfo.firstIndex(where: { $0.id == userId }) {
            participantInfo[index] = info
        } else {
            participantInfo.append(info)
        }
    }

    private func startPresenceTimer() {
        // Subscribe to the centralized presence timer
        // Every second, trigger a UI refresh to update "Last seen" text (e.g., "1m ago" → "2m ago")
        timerCancellable = presenceManager.timer
            .sink { [weak self] _ in
                guard let self = self else { return }
                // Force UI update to refresh relative timestamps
                self.objectWillChange.send()
            }
    }

    // MARK: - Lifecycle

    func onViewDisappear() {
        Task {
            try? await clearTypingState()
        }
    }

    // MARK: - Typing Indicators

    private func observeTypingIndicators() {
        typingObserverHandle = realtimeManager.observeTypingIndicators(conversationId: conversationId) { [weak self] typingIndicators in
            guard let self = self else { return }
            Task { @MainActor in
                // Filter out current user's typing indicator (don't show your own typing)
                self.typingUsers = typingIndicators.filter { $0.id != self.currentUserId }
                print("⌨️ Typing indicators updated: \(self.typingUsers.count) users typing")
                for user in self.typingUsers {
                    print("   - \(user.name) is typing")
                }
            }
        }
    }

    func onMessageTextChanged() {
        // Reset the auto-clear timer
        resetTypingTimer()

        // Debounce: only update if enough time has passed since last update
        let now = Date()
        if let lastUpdate = lastTypingUpdate,
           now.timeIntervalSince(lastUpdate) < typingDebounceInterval {
            print("⌨️ Typing update debounced (too soon)")
            return
        }

        lastTypingUpdate = now

        // Update typing state
        Task {
            guard let userName = await getUserDisplayName() else {
                print("⌨️ Could not get user display name for typing indicator")
                return
            }
            let isTyping = !messageText.isEmpty
            print("⌨️ Sending typing indicator: \(userName) isTyping=\(isTyping)")
            try? await realtimeManager.setTyping(
                conversationId: conversationId,
                userId: currentUserId,
                name: userName,
                isTyping: isTyping
            )
        }
    }

    private func clearTypingState() async {
        guard let userName = await getUserDisplayName() else { return }
        try? await realtimeManager.setTyping(
            conversationId: conversationId,
            userId: currentUserId,
            name: userName,
            isTyping: false
        )
        typingTimer?.invalidate()
        typingTimer = nil
        lastTypingUpdate = nil
    }

    private func resetTypingTimer() {
        typingTimer?.invalidate()
        typingTimer = Timer.scheduledTimer(withTimeInterval: typingTimeoutInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.clearTypingState()
            }
        }
    }

    private func getUserDisplayName() async -> String? {
        guard let user = try? await realtimeManager.getUser(userId: currentUserId) else {
            return nil
        }
        return user.displayName ?? user.email
    }

    // MARK: - Connection Monitoring & Message Retry

    private func observeConnectionState() {
        connectionObserverHandle = realtimeManager.observeConnectionState { [weak self] connected in
            guard let self = self else { return }
            Task { @MainActor in
                self.isConnected = connected
                print("🌐 Connection state: \(connected ? "✅ Online" : "❌ Offline")")

                // Auto-retry pending messages when reconnected
                if connected {
                    await self.retryPendingMessages()
                }
            }
        }
    }

    private func retryPendingMessages() async {
        guard !pendingMessages.isEmpty else { return }

        print("🔄 Retrying \(pendingMessages.count) pending messages")

        for (messageId, var message) in pendingMessages {
            do {
                // Try to send the message
                _ = try await realtimeManager.sendMessage(
                    conversationId: conversationId,
                    senderId: currentUserId,
                    text: message.text
                )

                // Success - remove from pending queue
                pendingMessages.removeValue(forKey: messageId)
                print("✅ Message \(messageId) sent successfully")

            } catch {
                // Still failed - mark as failed
                message.status = .failed
                pendingMessages[messageId] = message

                // Update UI
                if let index = messages.firstIndex(where: { $0.id == messageId }) {
                    messages[index] = message
                }

                print("❌ Message \(messageId) failed to send: \(error.localizedDescription)")
            }
        }
    }

    func retryMessage(_ message: Message) {
        Task {
            var updatedMessage = message
            updatedMessage.status = .sending

            // Update UI immediately
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index] = updatedMessage
            }

            do {
                // Try to send
                _ = try await realtimeManager.sendMessage(
                    conversationId: conversationId,
                    senderId: currentUserId,
                    text: message.text
                )

                // Success - remove from pending queue
                pendingMessages.removeValue(forKey: message.id)
                print("✅ Retry successful for message \(message.id)")

            } catch {
                // Failed again
                updatedMessage.status = .failed
                pendingMessages[message.id] = updatedMessage

                if let index = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[index] = updatedMessage
                }

                print("❌ Retry failed for message \(message.id): \(error.localizedDescription)")
            }
        }
    }
}

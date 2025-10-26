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

    let conversationId: String
    let currentUserId: String
    let participants: [String]

    private var messagesObserverHandle: DatabaseHandle?
    private var presenceObserverHandles: [String: DatabaseHandle] = [:]
    private var typingObserverHandle: DatabaseHandle?
    private let realtimeManager = RealtimeManager.shared
    private let presenceManager = PresenceManager.shared
    private var timerCancellable: AnyCancellable?
    private var typingTimer: Timer?
    private var lastTypingUpdate: Date?
    private let typingDebounceInterval: TimeInterval = 1.0  // Max 1 update per second
    private let typingTimeoutInterval: TimeInterval = 5.0   // Clear after 5 seconds of inactivity

    init(conversationId: String, currentUserId: String, participants: [String]) {
        self.conversationId = conversationId
        self.currentUserId = currentUserId
        self.participants = participants
        loadMessages()
        markMessagesAsRead()
        observeParticipantPresence()
        observeTypingIndicators()
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

        // Cancel timers
        timerCancellable?.cancel()
        typingTimer?.invalidate()

        // Note: Typing state will be cleared automatically by Firebase's onDisconnect handler
        // set in RealtimeManager.setTyping(). We don't call clearTypingState() here to avoid
        // retain cycles from creating Tasks in deinit.
    }

    private func loadMessages() {
        messagesObserverHandle = realtimeManager.observeMessages(for: conversationId) { [weak self] messages in
            guard let self = self else { return }
            Task { @MainActor in
                self.messages = messages

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
        isLoading = true

        // Clear typing indicator when sending message
        Task {
            try? await clearTypingState()
        }

        Task {
            do {
                _ = try await realtimeManager.sendMessage(
                    conversationId: conversationId,
                    senderId: currentUserId,
                    text: text
                )
            } catch {
                // Restore message text on error
                await MainActor.run {
                    messageText = text
                }
            }
            isLoading = false
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
}

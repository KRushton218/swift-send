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

    let conversationId: String
    let currentUserId: String
    let participants: [String]

    private var messagesObserverHandle: DatabaseHandle?
    private var presenceObserverHandles: [String: DatabaseHandle] = [:]
    private let realtimeManager = RealtimeManager.shared
    private let presenceManager = PresenceManager.shared
    private var timerCancellable: AnyCancellable?

    init(conversationId: String, currentUserId: String, participants: [String]) {
        self.conversationId = conversationId
        self.currentUserId = currentUserId
        self.participants = participants
        loadMessages()
        markMessagesAsRead()
        observeParticipantPresence()
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

        // Cancel timer subscription
        timerCancellable?.cancel()
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
}

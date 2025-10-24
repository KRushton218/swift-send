//
//  ChatViewModel.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//  Updated for hybrid architecture on 10/23/25.
//

import Foundation
import FirebaseDatabase
import Combine
import OSLog

@MainActor
class ChatViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.swiftsend.app", category: "ChatViewModel")
    @Published var messages: [Message] = []
    @Published var messageText: String = ""
    @Published var isLoading = false
    @Published var currentUserProfile: UserProfile?
    @Published var typingUsers: [String] = []
    @Published var onlineMembers: Set<String> = []
    @Published var conversation: Conversation?
    @Published var hasMoreMessages = true
    
    private var messagingManager = MessagingManager()
    private var profileManager = UserProfileManager()
    private var presenceManager = PresenceManager()
    private var messageHandles: [DatabaseHandle] = []
    private var typingHandle: DatabaseHandle?
    private var presenceHandles: [String: DatabaseHandle] = [:]
    private var conversationId: String
    private var userId: String
    private var typingTimer: Timer?
    private var isCurrentlyTyping = false
    private var markAsReadTask: Task<Void, Never>?
    private var lastMarkAsReadTime: Date?
    private let markAsReadDebounceInterval: TimeInterval = 2.0 // Minimum 2 seconds between mark as read calls
    private var processedReadMessageIds: Set<String> = []
    
    init(conversationId: String, userId: String) {
        self.conversationId = conversationId
        self.userId = userId
        logger.info("🚀 ChatViewModel initialized for conversation: \(conversationId), user: \(userId)")
    }
    
    func setup() {
        logger.info("⚙️ Setting up ChatViewModel for conversation: \(self.conversationId)")
        processedReadMessageIds.removeAll()
        loadMessages()
        loadConversation()
        loadCurrentUserProfile()
        setupTypingIndicators()
        setupPresenceMonitoring()
        markAsRead()
    }
    
    func cleanup() {
        logger.info("🧹 Cleaning up ChatViewModel for conversation: \(self.conversationId)")
        stopListening()
    }
    
    // MARK: - Load Data
    
    func loadCurrentUserProfile() {
        Task {
            do {
                let profile = try await profileManager.getUserProfile(userId: userId)
                self.currentUserProfile = profile
            } catch {
                print("Error loading user profile: \(error.localizedDescription)")
            }
        }
    }
    
    func loadConversation() {
        Task {
            do {
                let firestoreManager = FirestoreManager()
                let conv = try await firestoreManager.getConversation(id: conversationId)
                self.conversation = conv
                
                // Set up presence for members
                if let memberIds = conv?.memberIds {
                    await setupPresenceForMembers(memberIds: memberIds)
                }
            } catch {
                print("Error loading conversation: \(error.localizedDescription)")
            }
        }
    }
    
    func loadMessages() {
        logger.debug("📥 Loading messages for conversation: \(self.conversationId)")
        isLoading = true
        
        // Observe active messages from RTDB (real-time)
        messageHandles = messagingManager.observeActiveMessages(conversationId: conversationId) { [weak self] messages in
            guard let self = self else { return }
            Task { @MainActor in
                self.logger.info("📨 Received \(messages.count) messages for conversation")
                self.messages = messages
                self.isLoading = false
                
                // Mark new messages as delivered
                await self.markNewMessagesAsDelivered(messages)
                await self.markNewMessagesAsRead(messages)
            }
        }
        logger.info("✅ Message observer set up with \(self.messageHandles.count) handles")
    }
    
    func loadOlderMessages() {
        guard let oldestMessage = messages.first else { return }
        guard hasMoreMessages else { return }
        
        Task {
            do {
                let olderMessages = try await messagingManager.loadOlderMessages(
                    conversationId: conversationId,
                    beforeTimestamp: oldestMessage.timestamp,
                    limit: 50
                )
                
                // If no messages returned, we've reached the end
                if olderMessages.isEmpty {
                    self.hasMoreMessages = false
                    logger.info("📭 No more earlier messages available")
                } else {
                    // Insert at the beginning
                    self.messages.insert(contentsOf: olderMessages, at: 0)
                    logger.info("📥 Loaded \(olderMessages.count) older messages")
                }
            } catch {
                logger.error("❌ Error loading older messages: \(error.localizedDescription)")
                print("Error loading older messages: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Send Message
    
    func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.debug("⚠️ Attempted to send empty message")
            return
        }
        
        let text = messageText
        messageText = "" // Clear input immediately
        
        logger.info("📤 Sending message to conversation: \(self.conversationId)")
        
        Task {
            do {
                _ = try await messagingManager.sendMessage(
                    conversationId: conversationId,
                    text: text
                )
                logger.info("✅ Message sent successfully")
            } catch {
                logger.error("❌ Error sending message: \(error.localizedDescription)")
                print("Error sending message: \(error.localizedDescription)")
                // Restore message text on error
                self.messageText = text
            }
        }
    }
    
    // MARK: - Message Actions
    
    func starMessage(_ message: Message) {
        Task {
            do {
                let conversationTitle = conversation?.name ?? "Chat"
                
                try await messagingManager.starMessage(
                    userId: userId,
                    messageId: message.id,
                    conversationId: conversationId,
                    conversationTitle: conversationTitle,
                    messageText: message.text,
                    senderId: message.senderId,
                    senderName: message.senderName
                )
            } catch {
                print("Error starring message: \(error.localizedDescription)")
            }
        }
    }
    
    func deleteMessage(_ message: Message) {
        print("🗑️ [ChatViewModel] User requested message deletion")
        print("   Message ID: \(message.id)")
        print("   Message text: \(message.text.prefix(50))...")
        
        Task {
            do {
                try await messagingManager.deleteMessageForUser(conversationId: conversationId, messageId: message.id)
                print("✅ [ChatViewModel] Message deletion completed")
                // Message will be filtered out automatically on next update
            } catch {
                print("❌ [ChatViewModel] Error deleting message: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Typing Indicators
    
    func setupTypingIndicators() {
        typingHandle = presenceManager.observeTypingIndicators(conversationId: conversationId) { [weak self] typingUserIds in
            guard let self = self else { return }
            Task { @MainActor in
                // Filter out current user - you should never see your own typing indicator
                self.typingUsers = typingUserIds.filter { $0 != self.userId }
            }
        }
    }
    
    func onTextChanged(_ newText: String) {
        messageText = newText
        
        let hasText = !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        if hasText && !isCurrentlyTyping {
            // User started typing
            isCurrentlyTyping = true
            Task {
                await setTyping(true)
            }
        } else if !hasText && isCurrentlyTyping {
            // User cleared text
            isCurrentlyTyping = false
            Task {
                await setTyping(false)
            }
        }
        
        // Reset timer
        typingTimer?.invalidate()
        if hasText {
            typingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.isCurrentlyTyping = false
                    await self.setTyping(false)
                }
            }
        }
    }
    
    private func setTyping(_ isTyping: Bool) async {
        try? await presenceManager.setTypingIndicator(conversationId: conversationId, isTyping: isTyping)
    }
    
    // MARK: - Presence Monitoring
    
    func setupPresenceMonitoring() {
        // Will be set up after conversation loads
    }
    
    private func setupPresenceForMembers(memberIds: [String]) async {
        for memberId in memberIds where memberId != userId {
            let handle = presenceManager.observePresence(userId: memberId) { [weak self] isOnline in
                guard let self = self else { return }
                Task { @MainActor in
                    if isOnline {
                        self.onlineMembers.insert(memberId)
                    } else {
                        self.onlineMembers.remove(memberId)
                    }
                }
            }
            presenceHandles[memberId] = handle
        }
    }
    
    // MARK: - Read Receipts
    
    private func markNewMessagesAsDelivered(_ messages: [Message]) async {
        // Batch delivery status updates to reduce database writes
        let pendingMessages = messages.filter { message in
            message.senderId != userId &&
            message.deliveryStateFor(userId: userId) == .pending
        }
        
        guard !pendingMessages.isEmpty else { return }
        
        // Only mark the most recent undelivered message as delivered
        // This is sufficient for the UI and reduces database writes
        if let mostRecentMessage = pendingMessages.max(by: { $0.timestamp < $1.timestamp }) {
            try? await messagingManager.markAsDelivered(
                conversationId: conversationId,
                messageId: mostRecentMessage.id
            )
        }
    }
    
    private func markNewMessagesAsRead(_ messages: [Message]) async {
        let unreadMessages = messages.filter { message in
            message.senderId != userId &&
            !message.wasReadBy(userId: userId) &&
            !processedReadMessageIds.contains(message.id)
        }
        
        guard !unreadMessages.isEmpty else {
            // No unread messages detected – still keep conversation status fresh
            markAsRead()
            return
        }
        
        let sortedMessages = unreadMessages.sorted { $0.timestamp < $1.timestamp }
        let messageIds = sortedMessages.map(\.id)
        let lastMessageId = sortedMessages.last?.id
        
        do {
            // Batch update: only write once to update conversation status
            // Individual message read receipts are handled by markMessagesAsRead
            try await messagingManager.markMessagesAsRead(
                conversationId: conversationId,
                messageIds: messageIds,
                lastReadMessageId: lastMessageId
            )
            processedReadMessageIds.formUnion(messageIds)
        } catch {
            logger.error("❌ Error marking messages as read: \(error.localizedDescription)")
        }
    }
    
    private func markAsRead() {
        // Cancel any pending mark as read task
        markAsReadTask?.cancel()
        
        // Check if we recently marked as read (debounce)
        if let lastTime = lastMarkAsReadTime,
           Date().timeIntervalSince(lastTime) < markAsReadDebounceInterval {
            logger.debug("⏭️ Skipping markAsRead - called too recently (debounced)")
            return
        }
        
        // Update the last mark as read time
        lastMarkAsReadTime = Date()
        
        markAsReadTask = Task {
            do {
                logger.debug("📖 Marking conversation as read: \(self.conversationId)")
                try await messagingManager.markConversationAsRead(conversationId: conversationId)
                logger.info("✅ Successfully marked conversation as read")
            } catch {
                logger.error("❌ Error marking conversation as read: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Cleanup
    
    func stopListening() {
        logger.debug("🔇 Stopping listeners for conversation: \(self.conversationId)")
        
        if !self.messageHandles.isEmpty {
            logger.debug("🔇 Removing \(self.messageHandles.count) message observers")
            messagingManager.removeMessageObserver(conversationId: conversationId, handles: self.messageHandles)
            self.messageHandles.removeAll()
        }
        
        if let handle = typingHandle {
            logger.debug("🔇 Removing typing observer")
            presenceManager.removeTypingObserver(conversationId: conversationId, handle: handle)
        }
        
        if !presenceHandles.isEmpty {
            logger.debug("🔇 Removing \(self.presenceHandles.count) presence observers")
        }
        for (memberId, handle) in presenceHandles {
            presenceManager.removePresenceObserver(userId: memberId, handle: handle)
        }
        presenceHandles.removeAll()
        
        typingTimer?.invalidate()
        typingTimer = nil
        
        // Cancel any pending mark as read task
        markAsReadTask?.cancel()
        markAsReadTask = nil
        processedReadMessageIds.removeAll()
        
        logger.info("✅ All listeners stopped for conversation: \(self.conversationId)")
    }
    
    deinit {
        // Note: Listener cleanup happens via stopListening() called from view's onDisappear
        // We can't call async manager methods from deinit due to Swift 6 concurrency rules
        typingTimer?.invalidate()
    }
}

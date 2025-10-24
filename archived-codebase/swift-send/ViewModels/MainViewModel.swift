//
//  MainViewModel.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//  Updated for hybrid architecture on 10/23/25.
//

import Foundation
import FirebaseDatabase
import FirebaseFirestore
import Combine
import OSLog

@MainActor
class MainViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.swiftsend.app", category: "MainViewModel")
    
    @Published var conversations: [Conversation] = [] {
        didSet {
            logger.info("🔄 conversations array changed: \(oldValue.count) → \(self.conversations.count)")
            if oldValue.count == conversations.count {
                logger.debug("   Same count, checking IDs...")
                let oldIds = oldValue.compactMap { $0.id }.sorted()
                let newIds = conversations.compactMap { $0.id }.sorted()
                if oldIds == newIds {
                    logger.warning("   ⚠️ SAME conversations, but array was reassigned!")
                }
            }
        }
    }
    @Published var userConversationStatuses: [String: UserConversationStatus] = [:]
    @Published var mentionedMessages: [MentionedMessage] = []
    @Published var isLoading = false
    
    private var realtimeManager = RealtimeManager()
    private var firestoreManager = FirestoreManager()
    private var messagingManager = MessagingManager()
    private var presenceManager = PresenceManager()
    
    private var conversationListener: ListenerRegistration?
    private var userConversationHandle: DatabaseHandle?
    private var mentionedMessagesHandle: DatabaseHandle?
    
    private var userId: String?
    
    func loadData(for userId: String) {
        self.userId = userId
        isLoading = true
        
        // Set up presence for this user
        presenceManager.setupPresence()
        
        // Listen to conversations from Firestore
        loadConversations(userId: userId)
        
        // Listen to user conversation statuses from RTDB
        loadUserConversationStatuses(userId: userId)
        
        // Listen to mentioned messages (legacy)
        loadMentionedMessages(userId: userId)
    }
    
    // MARK: - Load Conversations (Firestore)
    
    /// Check if conversations have meaningfully changed for inbox display
    /// Compares: IDs, names, participants, and last message (for preview and sorting)
    /// Excludes: read receipts, typing status, online presence (handled separately)
    private func conversationsHaveChanged(old: [Conversation], new: [Conversation]) -> Bool {
        // Different counts = changed
        if old.count != new.count {
            return true
        }
        
        // Create lookup dictionaries by ID
        let oldDict = Dictionary(uniqueKeysWithValues: old.compactMap { conv -> (String, Conversation)? in
            guard let id = conv.id else { return nil }
            return (id, conv)
        })
        
        let newDict = Dictionary(uniqueKeysWithValues: new.compactMap { conv -> (String, Conversation)? in
            guard let id = conv.id else { return nil }
            return (id, conv)
        })
        
        // Different IDs = changed
        if Set(oldDict.keys) != Set(newDict.keys) {
            return true
        }
        
        // Check if any conversation's structural properties changed
        for (id, newConv) in newDict {
            guard let oldConv = oldDict[id] else {
                logger.debug("   Conversation \(id) is new")
                return true // New conversation appeared
            }
            
            // Compare fields that affect inbox list display:
            // - name: Group name changes
            // - memberIds: Participants added/removed
            // - lastMessage: New messages (for preview and sorting)
            if oldConv.name != newConv.name {
                logger.info("   📝 Name changed for \(id): '\(oldConv.name ?? "nil")' → '\(newConv.name ?? "nil")'")
                return true
            }
            
            if oldConv.memberIds != newConv.memberIds {
                logger.info("   👥 Members changed for \(id): \(oldConv.memberIds.count) → \(newConv.memberIds.count)")
                return true
            }
            
            // Compare last message for preview and sorting updates
            if oldConv.lastMessage?.text != newConv.lastMessage?.text ||
               oldConv.lastMessage?.timestamp != newConv.lastMessage?.timestamp {
                logger.info("   💬 Last message changed for \(id)")
                return true
            }
        }
        
        logger.debug("   No structural changes detected")
        return false
    }
    
    private func loadConversations(userId: String) {
        conversationListener = firestoreManager.observeUserConversations(memberIds: [userId]) { [weak self] conversations in
            guard let self = self else { return }
            Task { @MainActor in
                self.logger.info("📥 Received \(conversations.count) conversations from Firestore")
                
                // Filter out hidden conversations
                let filtered = conversations.filter { conversation in
                    guard let conversationId = conversation.id else { return true }
                    let status = self.userConversationStatuses[conversationId]
                    return !(status?.isHidden ?? false)
                }
                
                // Check if conversations actually changed (IDs or content)
                if self.conversationsHaveChanged(old: self.conversations, new: filtered) {
                    self.logger.info("   Conversations changed, updating array")
                    self.conversations = filtered
                } else {
                    self.logger.debug("   Same conversations from Firestore, skipping array update")
                }
                
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Load User Conversation Statuses (RTDB)
    
    private func loadUserConversationStatuses(userId: String) {
        userConversationHandle = realtimeManager.observe(at: "userConversations/\(userId)") { [weak self] data in
            guard let self = self else { return }
            
            self.logger.info("📊 Received user conversation statuses update")
            
            var statuses: [String: UserConversationStatus] = [:]
            var hasHiddenStatusChanged = false
            
            for (conversationId, value) in data {
                if let statusData = value as? [String: Any],
                   let status = UserConversationStatus(from: statusData) {
                    
                    // Check if hidden status changed (only if we had a previous status)
                    let oldStatus = self.userConversationStatuses[conversationId]
                    if let oldStatus = oldStatus, oldStatus.isHidden != status.isHidden {
                        hasHiddenStatusChanged = true
                        self.logger.info("   🔄 Hidden status changed for \(conversationId): \(oldStatus.isHidden) → \(status.isHidden)")
                    }
                    
                    statuses[conversationId] = status
                }
            }
            
            Task { @MainActor in
                self.userConversationStatuses = statuses
                
                // ✅ ONLY filter if hidden status actually changed
                if hasHiddenStatusChanged {
                    self.logger.debug("   Calling filterConversations() due to hidden status change")
                    self.filterConversations()
                } else {
                    self.logger.debug("   Skipping filterConversations() - only read/count statuses changed")
                }
            }
        }
    }
    
    private func filterConversations() {
        self.logger.info("🔍 Filtering conversations (current count: \(self.conversations.count))")
        let beforeCount = conversations.count
        
        // Filter out hidden conversations based on current statuses
        conversations = conversations.filter { conversation in
            guard let conversationId = conversation.id else { return true }
            let status = userConversationStatuses[conversationId]
            let isHidden = status?.isHidden ?? false
            
            if isHidden {
                print("👻 [MainViewModel] Filtering out hidden conversation: \(conversationId)")
            }
            
            return !isHidden
        }
        
        let afterCount = conversations.count
        if beforeCount != afterCount {
            self.logger.info("   ✅ Filtered out \(beforeCount - afterCount) hidden conversations")
            print("📊 [MainViewModel] Conversation count: \(beforeCount) → \(afterCount)")
        } else {
            print("📊 [MainViewModel] No hidden conversations to filter")
        }
    }
    
    // MARK: - Load Mentioned Messages (Legacy)
    
    private func loadMentionedMessages(userId: String) {
        mentionedMessagesHandle = realtimeManager.observe(at: "users/\(userId)/mentionedMessages") { [weak self] data in
            guard let self = self else { return }
            
            let mentions = data.compactMap { (key, value) -> MentionedMessage? in
                guard let itemData = value as? [String: Any] else { return nil }
                return MentionedMessage(from: itemData, id: key)
            }.sorted { !$0.isRead && $1.isRead || $0.timestamp > $1.timestamp }
            
            Task { @MainActor in
                self.mentionedMessages = mentions
            }
        }
    }
    
    // MARK: - Conversation Validation
    
    /// Valid conversations with defensive filtering and sorting
    var validConversations: [Conversation] {
        let filtered = conversations.filter { conversation in
            // Filter out conversations with nil IDs
            guard conversation.id != nil else {
                print("⚠️ Filtering conversation with nil ID: type=\(conversation.type), createdBy=\(conversation.createdBy)")
                return false
            }
            
            // Filter out conversations with empty member lists
            guard !conversation.memberIds.isEmpty else {
                print("⚠️ Filtering conversation with empty memberIds: id=\(conversation.id ?? "nil")")
                return false
            }
            
            return true
        }
        
        // Sort by last message timestamp (most recent first)
        return filtered.sorted { conv1, conv2 in
            let timestamp1 = conv1.lastMessage?.timestamp ?? conv1.createdAt
            let timestamp2 = conv2.lastMessage?.timestamp ?? conv2.createdAt
            return timestamp1 > timestamp2
        }
    }
    
    // MARK: - Conversation Helpers
    
    /// Get display name for a conversation (uses safe accessor)
    func getConversationDisplayName(_ conversation: Conversation, currentUserId: String) -> String {
        return conversation.safeDisplayName(currentUserId: currentUserId)
    }
    
    /// Get display name with type prefix for conversation list
    func getConversationDisplayNameWithType(_ conversation: Conversation, currentUserId: String) -> String {
        let typePrefix = conversation.type == .group ? "Group" : "Direct"
        let name = conversation.safeDisplayName(currentUserId: currentUserId)
        return "\(typePrefix): \(name)"
    }
    
    /// Get photo URL for a conversation (uses safe accessor)
    func getConversationPhotoURL(_ conversation: Conversation, currentUserId: String) -> String? {
        return conversation.safePhotoURL(currentUserId: currentUserId)
    }
    
    /// Get unread count for a conversation
    func getUnreadCount(conversationId: String) -> Int {
        return userConversationStatuses[conversationId]?.unreadCount ?? 0
    }
    
    /// Get last message preview (uses enhanced preview)
    func getLastMessagePreview(_ conversation: Conversation) -> String {
        return conversation.enhancedLastMessagePreview()
    }
    
    /// Get last message timestamp
    func getLastMessageTimestamp(_ conversation: Conversation) -> Date {
        // Use RTDB data first (real-time, always current)
        if let conversationId = conversation.id,
           let status = userConversationStatuses[conversationId],
           status.lastMessageTimestamp > 0 {
            return Date(timeIntervalSince1970: status.lastMessageTimestamp / 1000)
        }
        
        // Fallback to Firestore (for initial load before RTDB connects)
        return conversation.lastMessage?.timestamp ?? conversation.createdAt
    }
    
    /// Format timestamp as relative time string
    func formatTimestamp(_ date: Date) -> String {
        let now = Date()
        let secondsAgo = now.timeIntervalSince(date)
        let minutesAgo = secondsAgo / 60
        let hoursAgo = minutesAgo / 60
        let daysAgo = hoursAgo / 24
        
        if secondsAgo < 60 {
            return "Just now"
        } else if minutesAgo < 60 {
            return "\(Int(minutesAgo))m ago"
        } else if hoursAgo < 24 {
            return "\(Int(hoursAgo))h ago"
        } else if daysAgo < 2 {
            return "Yesterday"
        } else {
            let calendar = Calendar.current
            let formatter = DateFormatter()
            
            if calendar.isDate(date, equalTo: now, toGranularity: .year) {
                formatter.dateFormat = "MMM d"
            } else {
                formatter.dateFormat = "MMM d, yyyy"
            }
            
            return formatter.string(from: date)
        }
    }
    
    // MARK: - Delete Operations
    
    func deleteConversation(_ conversation: Conversation) {
        guard let conversationId = conversation.id else {
            print("❌ [MainViewModel] Cannot delete conversation - no ID")
            return
        }
        
        print("👻 [MainViewModel] User requested conversation hide")
        print("   Conversation ID: \(conversationId)")
        print("   Conversation name: \(conversation.name ?? "Direct chat")")
        
        Task {
            do {
                try await messagingManager.hideConversationForUser(conversationId: conversationId)
                print("✅ [MainViewModel] Conversation hide completed")
                // Conversation will be filtered out automatically on next update
            } catch {
                print("❌ [MainViewModel] Error hiding conversation: \(error.localizedDescription)")
            }
        }
    }
    
    func deleteMentionedMessage(_ message: MentionedMessage) {
        guard let userId = userId else { return }
        
        Task {
            do {
                try await messagingManager.deleteMentionedMessage(userId: userId, mentionId: message.id)
            } catch {
                print("Error deleting mentioned message: \(error.localizedDescription)")
            }
        }
    }
    
    func markMentionAsRead(_ message: MentionedMessage) {
        guard let userId = userId else { return }
        
        Task {
            do {
                try await messagingManager.markMentionAsRead(userId: userId, mentionId: message.id)
            } catch {
                print("Error marking mention as read: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        // Remove all listeners first
        conversationListener?.remove()
        conversationListener = nil
        
        if let userId = userId {
            if let handle = userConversationHandle {
                realtimeManager.removeObserver(at: "userConversations/\(userId)", handle: handle)
            }
            if let handle = mentionedMessagesHandle {
                realtimeManager.removeObserver(at: "users/\(userId)/mentionedMessages", handle: handle)
            }
        }
        
        // Clear all handles
        userConversationHandle = nil
        mentionedMessagesHandle = nil
        
        // Clear presence
        presenceManager.cleanup()
        
        // Clear all data to prevent SwiftUI update issues during sign out
        conversations = []
        userConversationStatuses = [:]
        mentionedMessages = []
        userId = nil
        isLoading = false
    }
    
    deinit {
        // Note: Listener cleanup happens via cleanup() called when user signs out
        // We can't call async manager methods from deinit due to Swift 6 concurrency rules
        conversationListener?.remove()
    }
}

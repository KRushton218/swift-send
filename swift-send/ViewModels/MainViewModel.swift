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

@MainActor
class MainViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
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
    
    private func loadConversations(userId: String) {
        conversationListener = firestoreManager.observeUserConversations(memberIds: [userId]) { [weak self] conversations in
            guard let self = self else { return }
            Task { @MainActor in
                // Filter out hidden conversations
                self.conversations = conversations.filter { conversation in
                    guard let conversationId = conversation.id else { return true }
                    let status = self.userConversationStatuses[conversationId]
                    return !(status?.isHidden ?? false)
                }
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Load User Conversation Statuses (RTDB)
    
    private func loadUserConversationStatuses(userId: String) {
        userConversationHandle = realtimeManager.observe(at: "userConversations/\(userId)") { [weak self] data in
            guard let self = self else { return }
            
            var statuses: [String: UserConversationStatus] = [:]
            for (conversationId, value) in data {
                if let statusData = value as? [String: Any],
                   let status = UserConversationStatus(from: statusData) {
                    statuses[conversationId] = status
                }
            }
            
            Task { @MainActor in
                self.userConversationStatuses = statuses
                // Re-filter conversations when statuses change
                self.filterConversations()
            }
        }
    }
    
    private func filterConversations() {
        // Filter out hidden conversations based on current statuses
        conversations = conversations.filter { conversation in
            guard let conversationId = conversation.id else { return true }
            let status = userConversationStatuses[conversationId]
            return !(status?.isHidden ?? false)
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
        guard let conversationId = conversation.id else { return }
        
        Task {
            do {
                try await messagingManager.hideConversationForUser(conversationId: conversationId)
                // Conversation will be filtered out automatically on next update
            } catch {
                print("Error hiding conversation: \(error.localizedDescription)")
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

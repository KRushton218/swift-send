//
//  MessagingManager.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//  Updated for hybrid RTDB + Firestore architecture on 10/23/25.
//

import Foundation
import FirebaseDatabase
import FirebaseFirestore
import FirebaseAuth

/// Messaging manager with hybrid RTDB + Firestore architecture
/// - RTDB: Real-time message delivery, typing indicators, presence
/// - Firestore: Persistence, history, conversation metadata
class MessagingManager {
    private let realtimeManager = RealtimeManager()
    private let firestoreManager = FirestoreManager()
    private let presenceManager = PresenceManager()
    private let rtdb = Database.database().reference()
    
    // MARK: - Send Message (Hybrid Dual-Write)
    
    /// Send a message using hybrid architecture
    /// 1. Write to RTDB for instant delivery
    /// 2. Async write to Firestore for persistence
    /// 3. Update unread counts
    /// 4. Clear typing indicator
    func sendMessage(
        conversationId: String,
        text: String,
        type: MessageType = .text,
        replyToMessageId: String? = nil,
        mediaUrl: String? = nil
    ) async throws -> String {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "MessagingManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Get user profile for sender name
        let userProfileManager = UserProfileManager()
        let userProfile = try await userProfileManager.getUserProfile(userId: currentUserId)
        let currentUserName = userProfile?.displayName ?? "User"
        
        // Generate message ID
        let messageId = rtdb.child("conversations")
            .child(conversationId)
            .child("activeMessages")
            .childByAutoId().key ?? UUID().uuidString
        
        // Get conversation to determine members
        let conversation = try await firestoreManager.getConversation(id: conversationId)
        guard let memberIds = conversation?.memberIds else {
            throw NSError(domain: "MessagingManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Conversation not found"])
        }
        
        // Create message object
        let message = Message(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            senderName: currentUserName,
            text: text,
            type: type,
            mediaUrl: mediaUrl,
            replyToMessageId: replyToMessageId
        )
        
        // 1. WRITE TO RTDB (instant delivery)
        let rtdbMessageData = message.toRTDBDictionary(memberIds: memberIds)
        try await rtdb.child("conversations")
            .child(conversationId)
            .child("activeMessages")
            .child(messageId)
            .setValue(rtdbMessageData)
        
        // 2. UPDATE CONVERSATION METADATA IN RTDB
        try await rtdb.child("conversations")
            .child(conversationId)
            .child("metadata")
            .updateChildValues([
                "lastActivity": ServerValue.timestamp()
            ])
        
        // 3. UPDATE UNREAD COUNTS FOR OTHER MEMBERS
        try await updateUnreadCounts(
            conversationId: conversationId,
            excludeUserId: currentUserId,
            memberIds: memberIds
        )
        
        // 4. ASYNC WRITE TO FIRESTORE (for persistence/history)
        let lastMessage = Conversation.LastMessage(
            text: text,
            senderId: currentUserId,
            senderName: currentUserName,
            type: type.rawValue
        )
        
        Task.detached { [firestoreManager] in
            _ = try? await firestoreManager.archiveMessageAndUpdateConversation(
                conversationId: conversationId,
                message: message,
                lastMessage: lastMessage
            )
        }
        
        // 5. CLEAR TYPING INDICATOR
        try? await presenceManager.clearTypingIndicator(conversationId: conversationId)
        
        // 6. CHECK FOR @MENTIONS
        Task {
                let mentions = extractMentions(from: text)
            if !mentions.isEmpty {
                let mentionedUserIds = try? await findUserIdsByDisplayNames(mentions)
                
                let conversationTitle = conversation?.name ?? "Chat"
                
                for mentionedUserId in mentionedUserIds ?? [] {
                    if mentionedUserId != currentUserId {
                        _ = try? await createMentionedMessage(
                            userId: mentionedUserId,
                            messageId: messageId,
                            conversationId: conversationId,
                            conversationTitle: conversationTitle,
                            messageText: text,
                            senderId: currentUserId,
                            senderName: currentUserName,
                            reason: .mentioned
                        )
                    }
                }
            }
        }
        
        return messageId
    }
    
    // MARK: - Find Conversation
    
    /// Find existing conversation by exact participant match
    func findConversationByParticipants(memberIds: [String]) async throws -> Conversation? {
        // Sort member IDs for consistent comparison
        let sortedMemberIds = memberIds.sorted()
        
        // Query Firestore for conversations containing all these members
        let conversations = try await firestoreManager.findConversationsByMembers(memberIds: memberIds)
        
        // Filter to find exact match (same members, no more, no less)
        return conversations.first { conversation in
            let conversationMemberIds = conversation.memberIds.sorted()
            return conversationMemberIds == sortedMemberIds
        }
    }
    
    // MARK: - Create Conversation
    
    /// Create a new conversation AND send the first message atomically
    /// This ensures conversation + first message happen together
    /// Used by UnifiedMessageView for seamless conversation creation
    func createConversationAndSendMessage(
        type: ConversationType,
        name: String?,
        memberIds: [String],
        createdBy: String,
        messageText: String
    ) async throws -> (conversationId: String, messageId: String) {
        // 1. Create conversation
        let conversationId = try await createConversation(
            type: type,
            name: name,
            memberIds: memberIds,
            createdBy: createdBy
        )
        
        // 2. Send first message
        let messageId = try await sendMessage(
            conversationId: conversationId,
            text: messageText,
            type: .text
        )
        
        return (conversationId, messageId)
    }
    
    /// Create a new conversation (group or direct)
    func createConversation(
        type: ConversationType,
        name: String?,
        memberIds: [String],
        createdBy: String
    ) async throws -> String {
        // Get member details
        let userProfileManager = UserProfileManager()
        var memberDetails: [String: Conversation.MemberDetail] = [:]
        
        for memberId in memberIds {
            if let profile = try? await userProfileManager.getUserProfile(userId: memberId) {
                memberDetails[memberId] = Conversation.MemberDetail(
                    displayName: profile.displayName,
                    photoURL: profile.photoURL
                )
            }
        }
        
        // Create conversation in Firestore
        let conversation = Conversation(
            type: type,
            name: name,
            createdBy: createdBy,
            memberIds: memberIds,
            memberDetails: memberDetails
        )
        
        let conversationId = try await firestoreManager.createConversation(conversation)
        
        // Set up RTDB structure for conversation members
        // Write each member individually to satisfy security rules
        for memberId in memberIds {
            try await rtdb.child("conversationMembers")
                .child(conversationId)
                .child(memberId)
                .setValue(true)
        }
        
        // Add conversation to each member's userConversations in RTDB
        for memberId in memberIds {
            let userConvStatus = UserConversationStatus(
                conversationId: conversationId,
                unreadCount: 0,
                lastMessageTimestamp: Date().timeIntervalSince1970 * 1000
            )
            
            try await rtdb.child("userConversations")
                .child(memberId)
                .child(conversationId)
                .setValue(userConvStatus.toDictionary())
        }
        
        return conversationId
    }
    
    // MARK: - Observe Messages (RTDB Real-time)
    
    /// Observe active messages in RTDB (last 50 messages)
    /// Uses optimized subscription pattern: initial fetch + subscribe to new messages only
    func observeActiveMessages(
        conversationId: String,
        limit: Int = 50,
        completion: @escaping ([Message]) -> Void
    ) -> [DatabaseHandle] {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion([])
            return []
        }
        
        var messages: [String: Message] = [:]
        var handles: [DatabaseHandle] = []
        var isInitialLoad = true
        var initialLoadTimestamp: TimeInterval = 0
        
        let query = rtdb.child("conversations")
            .child(conversationId)
            .child("activeMessages")
            .queryLimited(toLast: UInt(limit))
        
        // PHASE 1: Initial load - fetch existing messages once
        // This fires for each existing message, but only during initial connection
        let addedHandle = query.observe(.childAdded) { snapshot in
            guard let messageDict = snapshot.value as? [String: Any],
                  var message = Message(rtdbData: messageDict) else { return }
            
            message.conversationId = conversationId
            
            // Filter out deleted messages
            if message.isDeletedForUser(currentUserId) {
                print("🚫 [OBSERVE] Filtering deleted message: \(snapshot.key)")
                print("   deletedFor: \(message.deletedFor ?? [])")
                return
            }
            
            messages[snapshot.key] = message
            
            // Track the latest timestamp during initial load
            if isInitialLoad {
                initialLoadTimestamp = max(initialLoadTimestamp, message.timestamp.timeIntervalSince1970)
            }
            
            // Only emit updates after initial load completes
            if !isInitialLoad {
                print("📨 [OBSERVE] New message added: \(snapshot.key)")
                completion(Array(messages.values).sorted { $0.timestamp < $1.timestamp })
            }
        }
        handles.append(addedHandle)
        
        // Complete initial load after a brief delay (allow all childAdded events to fire)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if isInitialLoad {
                isInitialLoad = false
                print("📥 Initial message load complete: \(messages.count) messages")
                completion(Array(messages.values).sorted { $0.timestamp < $1.timestamp })
            }
        }
        
        // PHASE 2: Subscribe to changes for existing messages
        // Only listen for meaningful changes (deletions, edits)
        let changedHandle = query.observe(.childChanged) { snapshot in
            guard !isInitialLoad else { return } // Skip during initial load
            
            guard let messageDict = snapshot.value as? [String: Any],
                  var message = Message(rtdbData: messageDict) else { return }
            
            message.conversationId = conversationId
            
            // Check if message was deleted for this user
            if message.isDeletedForUser(currentUserId) {
                print("🗑️ [OBSERVE] Message deleted, removing from local cache: \(snapshot.key)")
                print("   deletedFor: \(message.deletedFor ?? [])")
                messages.removeValue(forKey: snapshot.key)
            } else {
                // Only update if the message content actually changed
                let existingMessage = messages[snapshot.key]
                if existingMessage?.text != message.text || 
                   existingMessage?.mediaUrl != message.mediaUrl {
                    print("✏️ [OBSERVE] Message content changed: \(snapshot.key)")
                    messages[snapshot.key] = message
                } else {
                    // Skip updates for delivery/read status changes to reduce noise
                    return
                }
            }
            
            print("📤 [OBSERVE] Emitting updated message list (\(messages.count) messages)")
            completion(Array(messages.values).sorted { $0.timestamp < $1.timestamp })
        }
        handles.append(changedHandle)
        
        // PHASE 3: Handle message removals
        let removedHandle = query.observe(.childRemoved) { snapshot in
            guard !isInitialLoad else { return }
            print("🔥 [OBSERVE] Message removed from RTDB: \(snapshot.key)")
            messages.removeValue(forKey: snapshot.key)
            print("📤 [OBSERVE] Emitting updated message list (\(messages.count) messages)")
            completion(Array(messages.values).sorted { $0.timestamp < $1.timestamp })
        }
        handles.append(removedHandle)
        
        return handles
    }
    
    /// Remove message observer
    func removeMessageObserver(conversationId: String, handles: [DatabaseHandle]) {
        let ref = rtdb.child("conversations")
            .child(conversationId)
            .child("activeMessages")
        
        for handle in handles {
            ref.removeObserver(withHandle: handle)
        }
    }
    
    // MARK: - Load Older Messages (Firestore History)
    
    /// Load older messages from Firestore
    func loadOlderMessages(
        conversationId: String,
        beforeTimestamp: Date,
        limit: Int = 50
    ) async throws -> [Message] {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "MessagingManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        print("📚 [LOAD] Loading older messages from Firestore")
        print("   Conversation: \(conversationId)")
        print("   Before: \(beforeTimestamp)")
        print("   Limit: \(limit)")
        
        let messages = try await firestoreManager.getArchivedMessages(
            conversationId: conversationId,
            limit: limit,
            beforeTimestamp: beforeTimestamp
        )
        
        print("   Retrieved: \(messages.count) messages")
        
        // Filter out messages deleted by current user
        let filtered = messages.filter { !$0.isDeletedForUser(currentUserId) }
        let filteredCount = messages.count - filtered.count
        
        if filteredCount > 0 {
            print("🚫 [LOAD] Filtered out \(filteredCount) deleted messages")
        }
        print("✅ [LOAD] Returning \(filtered.count) messages")
        
        return filtered
    }
    
    // MARK: - Delivery & Read Status
    
    /// Mark message as delivered
    func markAsDelivered(conversationId: String, messageId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        try await rtdb.child("conversations")
            .child(conversationId)
            .child("activeMessages")
            .child(messageId)
            .child("deliveryStatus")
            .child(userId)
            .updateChildValues([
                "status": DeliveryState.delivered.rawValue,
                "timestamp": ServerValue.timestamp()
            ])
    }
    
    /// Mark a batch of messages as read for the current user
    /// Optimized to reduce database writes - only updates conversation status
    func markMessagesAsRead(
        conversationId: String,
        messageIds: [String],
        lastReadMessageId: String? = nil
    ) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        guard !messageIds.isEmpty else { return }
        
        // OPTIMIZATION: Instead of updating each message individually,
        // we only update the conversation status with the last read message ID.
        // Individual message read receipts can be inferred from lastReadMessageId + timestamp.
        // This reduces N database writes to just 1 write.
        
        var statusUpdates: [String: Any] = [
            "lastReadTimestamp": ServerValue.timestamp(),
            "unreadCount": 0
        ]
        
        if let lastReadMessageId = lastReadMessageId ?? messageIds.last {
            statusUpdates["lastReadMessageId"] = lastReadMessageId
        }
        
        try await rtdb.child("userConversations")
            .child(userId)
            .child(conversationId)
            .updateChildValues(statusUpdates)
        
        // Optional: Only update read receipt on the LAST message for UI display
        // This gives visual feedback without updating every single message
        if let lastMessageId = lastReadMessageId ?? messageIds.last {
            try? await rtdb.child("conversations")
                .child(conversationId)
                .child("activeMessages")
                .child(lastMessageId)
                .child("readBy")
                .child(userId)
                .setValue(ServerValue.timestamp())
        }
    }
    
    /// Mark message as read
    func markAsRead(conversationId: String, messageId: String) async throws {
        try await markMessagesAsRead(
            conversationId: conversationId,
            messageIds: [messageId],
            lastReadMessageId: messageId
        )
    }
    
    /// Mark all messages in conversation as read
    func markConversationAsRead(conversationId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ Cannot mark as read: No authenticated user")
            return
        }
        
        print("📖 Marking conversation \(conversationId) as read for user \(userId)")
        
        // First, check if there are unread messages
        let snapshot = try await rtdb.child("userConversations")
            .child(userId)
            .child(conversationId)
            .child("unreadCount")
            .getData()
        
        let currentUnreadCount = snapshot.value as? Int ?? 0
        print("📊 Current unread count: \(currentUnreadCount)")
        
        // Only update lastReadTimestamp if there are unread messages
        if currentUnreadCount > 0 {
            print("🔄 Resetting unread count from \(currentUnreadCount) to 0")
            try await rtdb.child("userConversations")
                .child(userId)
                .child(conversationId)
                .updateChildValues([
                    "unreadCount": 0,
                    "lastReadTimestamp": ServerValue.timestamp()
                ])
            print("✅ Successfully reset unread count to 0")
        } else {
            print("✓ Already at 0 unread, ensuring it stays 0")
            // Already caught up, just ensure unreadCount is 0 (no timestamp update)
            try await rtdb.child("userConversations")
                .child(userId)
                .child(conversationId)
                .updateChildValues([
                    "unreadCount": 0
                ])
        }
    }
    
    // MARK: - Delete Operations
    
    /// Delete a message for the current user (per-user soft delete)
    func deleteMessageForUser(conversationId: String, messageId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ [DELETE] Not authenticated")
            throw NSError(domain: "MessagingManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        print("🗑️ [DELETE] Starting message deletion")
        print("   User: \(userId)")
        print("   Conversation: \(conversationId)")
        print("   Message: \(messageId)")
        
        // 1. Update Firestore - add user to deletedFor array (permanent record)
        print("📝 [DELETE] Updating Firestore...")
        do {
            try await firestoreManager.deleteMessageForUser(
                conversationId: conversationId,
                messageId: messageId,
                userId: userId
            )
            print("✅ [DELETE] Firestore updated successfully")
        } catch {
            print("❌ [DELETE] Firestore update failed: \(error.localizedDescription)")
            throw error
        }
        
        // 2. Update RTDB - add user to deletedFor array (for real-time filtering)
        print("📝 [DELETE] Updating RTDB...")
        
        // Get current deletedFor array
        let snapshot = try await rtdb.child("conversations")
            .child(conversationId)
            .child("activeMessages")
            .child(messageId)
            .child("deletedFor")
            .getData()
        
        var deletedFor = snapshot.value as? [String] ?? []
        print("   Current deletedFor: \(deletedFor)")
        
        if !deletedFor.contains(userId) {
            deletedFor.append(userId)
            print("   New deletedFor: \(deletedFor)")
            
            // Update RTDB with new deletedFor array
            do {
                try await rtdb.child("conversations")
                    .child(conversationId)
                    .child("activeMessages")
                    .child(messageId)
                    .updateChildValues([
                        "deletedFor": deletedFor
                    ])
                print("✅ [DELETE] RTDB updated successfully")
                print("🎉 [DELETE] Message deletion complete!")
            } catch {
                print("❌ [DELETE] RTDB update failed: \(error.localizedDescription)")
                throw error
            }
        } else {
            print("ℹ️ [DELETE] User already in deletedFor array, skipping RTDB update")
            print("🎉 [DELETE] Message deletion complete!")
        }
    }
    
    /// Hide conversation for the current user
    func hideConversationForUser(conversationId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ [HIDE] Not authenticated")
            throw NSError(domain: "MessagingManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        print("👻 [HIDE] Starting conversation hide")
        print("   User: \(userId)")
        print("   Conversation: \(conversationId)")
        
        // Set hidden flag in RTDB
        do {
            try await rtdb.child("userConversations")
                .child(userId)
                .child(conversationId)
                .updateChildValues([
                    "isHidden": true
                ])
            print("✅ [HIDE] Conversation hidden successfully")
            print("🎉 [HIDE] Conversation hide complete!")
        } catch {
            print("❌ [HIDE] Failed to hide conversation: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Legacy Delete Operations (kept for backward compatibility)
    
    /// Delete a message (soft delete in Firestore, remove from RTDB)
    @available(*, deprecated, message: "Use deleteMessageForUser instead")
    func deleteMessage(conversationId: String, messageId: String) async throws {
        // Remove from RTDB
        try await rtdb.child("conversations")
            .child(conversationId)
            .child("activeMessages")
            .child(messageId)
            .removeValue()
        
        // Soft delete in Firestore
        try? await firestoreManager.deleteMessage(conversationId: conversationId, messageId: messageId)
    }
    
    /// Delete conversation for a user
    @available(*, deprecated, message: "Use hideConversationForUser instead")
    func deleteConversation(conversationId: String, userId: String) async throws {
        // Remove from user's conversation list in RTDB
        try await rtdb.child("userConversations")
            .child(userId)
            .child(conversationId)
            .removeValue()
    }
    
    // MARK: - Mentioned Messages (Legacy Support)
    
    func createMentionedMessage(
        userId: String,
        messageId: String,
        conversationId: String,
        conversationTitle: String,
        messageText: String,
        senderId: String,
        senderName: String,
        reason: MentionedMessage.Reason
    ) async throws -> String {
        let mention = MentionedMessage(
            messageId: messageId,
            conversationId: conversationId,
            conversationTitle: conversationTitle,
            messageText: messageText,
            senderId: senderId,
            senderName: senderName,
            reason: reason
        )
        
        return try await realtimeManager.createItem(
            at: "users/\(userId)/mentionedMessages",
            data: mention.toDictionary()
        )
    }
    
    func starMessage(
        userId: String,
        messageId: String,
        conversationId: String,
        conversationTitle: String,
        messageText: String,
        senderId: String,
        senderName: String
    ) async throws {
        _ = try await createMentionedMessage(
            userId: userId,
            messageId: messageId,
            conversationId: conversationId,
            conversationTitle: conversationTitle,
            messageText: messageText,
            senderId: senderId,
            senderName: senderName,
            reason: .starred
        )
    }
    
    func deleteMentionedMessage(userId: String, mentionId: String) async throws {
        try await realtimeManager.deleteData(at: "users/\(userId)/mentionedMessages/\(mentionId)")
    }
    
    func markMentionAsRead(userId: String, mentionId: String) async throws {
        try await realtimeManager.updateData(
            at: "users/\(userId)/mentionedMessages/\(mentionId)",
            data: ["isRead": true]
        )
    }
    
    // MARK: - Helper Methods
    
    private func updateUnreadCounts(
        conversationId: String,
        excludeUserId: String,
        memberIds: [String]
    ) async throws {
        for memberId in memberIds where memberId != excludeUserId {
            _ = try? await rtdb.child("userConversations")
                .child(memberId)
                .child(conversationId)
                .child("unreadCount")
                .setValue(ServerValue.increment(1))
        }
    }
    
    private func extractMentions(from text: String) -> [String] {
        let pattern = "@([a-zA-Z0-9._-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }
    
    private func findUserIdsByDisplayNames(_ displayNames: [String]) async throws -> [String] {
        var userIds: [String] = []
        
        let snapshot = try await Database.database().reference().child("userProfiles").getData()
        guard let profiles = snapshot.value as? [String: [String: Any]] else {
            return []
        }
        
        for (userId, profileData) in profiles {
            if let displayName = profileData["displayName"] as? String,
               displayNames.contains(where: { $0.lowercased() == displayName.lowercased() }) {
                userIds.append(userId)
            }
        }
        
        return userIds
    }
    
}

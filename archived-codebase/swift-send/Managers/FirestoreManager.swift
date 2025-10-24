//
//  FirestoreManager.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/23/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Manager for Firestore operations (persistence layer)
/// Handles conversations and archived messages
class FirestoreManager {
    private let db = Firestore.firestore()
    
    // MARK: - Conversation Operations
    
    /// Create a new conversation in Firestore
    func createConversation(_ conversation: Conversation) async throws -> String {
        let ref = try db.collection("conversations").addDocument(from: conversation)
        return ref.documentID
    }
    
    /// Get a conversation by ID
    func getConversation(id: String) async throws -> Conversation? {
        let document = try await db.collection("conversations").document(id).getDocument()
        return try? document.data(as: Conversation.self)
    }
    
    /// Update conversation data
    func updateConversation(id: String, data: [String: Any]) async throws {
        try await db.collection("conversations").document(id).updateData(data)
    }
    
    /// Update conversation's last message
    func updateLastMessage(conversationId: String, lastMessage: Conversation.LastMessage) async throws {
        try await db.collection("conversations")
            .document(conversationId)
            .updateData([
                "lastMessage.text": lastMessage.text,
                "lastMessage.senderId": lastMessage.senderId,
                "lastMessage.senderName": lastMessage.senderName,
                "lastMessage.timestamp": Timestamp(date: lastMessage.timestamp),
                "lastMessage.type": lastMessage.type
            ])
    }
    
    /// Increment total message count
    func incrementMessageCount(conversationId: String) async throws {
        try await db.collection("conversations")
            .document(conversationId)
            .updateData([
                "metadata.totalMessages": FieldValue.increment(Int64(1))
            ])
    }
    
    /// Find conversations by member IDs (for checking existing conversations)
    /// Note: This queries for conversations where the CURRENT user is a member,
    /// then filters client-side for exact participant match
    func findConversationsByMembers(memberIds: [String]) async throws -> [Conversation] {
        // Query only for conversations where current user is a member
        // This satisfies the security rule: request.auth.uid in resource.data.memberIds
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "FirestoreManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let snapshot = try await db.collection("conversations")
            .whereField("memberIds", arrayContains: currentUserId)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc -> Conversation? in
            try? doc.data(as: Conversation.self)
        }
    }
    
    /// Observe a single conversation in real-time
    /// Used by UnifiedMessageView to watch for conversation changes as recipients are added/removed
    func observeConversation(
        id: String,
        completion: @escaping (Conversation?) -> Void
    ) -> ListenerRegistration {
        return db.collection("conversations")
            .document(id)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error observing conversation: \(error.localizedDescription)")
                    completion(nil)
                    return
                }
                
                guard let snapshot = snapshot, snapshot.exists else {
                    completion(nil)
                    return
                }
                
                let conversation = try? snapshot.data(as: Conversation.self)
                completion(conversation)
            }
    }
    
    /// Listen to conversations for a user (returns listener registration)
    func observeUserConversations(memberIds: [String], completion: @escaping ([Conversation]) -> Void) -> ListenerRegistration {
        // Use arrayContains with the first (current) user ID to satisfy security rules
        // Security rule requires: request.auth.uid in resource.data.memberIds
        guard let currentUserId = memberIds.first else {
            // Return empty listener if no user ID provided
            return db.collection("conversations").limit(to: 0).addSnapshotListener { _, _ in
                completion([])
            }
        }
        
        return db.collection("conversations")
            .whereField("memberIds", arrayContains: currentUserId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    let nsError = error as NSError
                    print("Error fetching conversations: \(error.localizedDescription)")
                    
                    // Check if it's an index error
                    if nsError.domain == "FIRFirestoreErrorDomain" {
                        if nsError.code == 9 { // FAILED_PRECONDITION
                            print("⚠️  Firestore index required. Check the error message for the index creation link.")
                        } else if nsError.code == 7 { // PERMISSION_DENIED
                            print("⚠️  Firestore permissions denied. Check your firestore.rules file.")
                        }
                    }
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([])
                    return
                }
                
                // Get conversations and sort them by last message timestamp in memory
                var conversations = documents.compactMap { doc -> Conversation? in
                    try? doc.data(as: Conversation.self)
                }
                
                // Sort by last message timestamp (most recent first)
                conversations.sort { conv1, conv2 in
                    let time1 = conv1.lastMessage?.timestamp ?? conv1.createdAt
                    let time2 = conv2.lastMessage?.timestamp ?? conv2.createdAt
                    return time1 > time2
                }
                
                completion(conversations)
            }
    }
    
    // MARK: - Message Operations (Archived Messages)
    
    /// Archive a message to Firestore (for persistence/history)
    func archiveMessage(conversationId: String, message: Message) async throws {
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(message.id)
        
        let messageData: [String: Any] = [
            "id": message.id,
            "conversationId": conversationId,
            "senderId": message.senderId,
            "senderName": message.senderName,
            "text": message.text,
            "type": message.type.rawValue,
            "timestamp": FieldValue.serverTimestamp(),
            "isDeleted": false,
            "isEdited": false
        ]
        
        var finalData = messageData
        
        if let mediaUrl = message.mediaUrl {
            finalData["mediaUrl"] = mediaUrl
        }
        if let replyToMessageId = message.replyToMessageId {
            finalData["replyToMessageId"] = replyToMessageId
        }
        
        try await messageRef.setData(finalData)
    }
    
    /// Update message with final delivery status
    func updateMessageWithFinalDeliveryStatus(
        conversationId: String,
        messageId: String,
        deliveryStatus: [String: DeliveryStatus],
        readBy: [String: Double]
    ) async throws {
        let delivered = deliveryStatus.filter { $0.value.status == .delivered }.map { $0.key }
        let failed = deliveryStatus.filter { $0.value.status == .failed }.map { $0.key }
        let read = Array(readBy.keys)
        
        try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .updateData([
                "finalDeliveryStatus.delivered": delivered,
                "finalDeliveryStatus.failed": failed,
                "finalDeliveryStatus.read": read
            ])
    }
    
    /// Get archived messages (paginated)
    func getArchivedMessages(
        conversationId: String,
        limit: Int = 50,
        beforeTimestamp: Date? = nil
    ) async throws -> [Message] {
        var query = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
        
        if let beforeTimestamp = beforeTimestamp {
            query = query.whereField("timestamp", isLessThan: Timestamp(date: beforeTimestamp))
        }
        
        let snapshot = try await query.getDocuments()
        
        return snapshot.documents.compactMap { doc -> Message? in
            let data = doc.data()
            guard let id = data["id"] as? String,
                  let senderId = data["senderId"] as? String,
                  let senderName = data["senderName"] as? String,
                  let text = data["text"] as? String,
                  let timestamp = (data["timestamp"] as? Timestamp)?.dateValue(),
                  let typeString = data["type"] as? String,
                  let type = MessageType(rawValue: typeString) else {
                return nil
            }
            
            return Message(
                id: id,
                conversationId: conversationId,
                senderId: senderId,
                senderName: senderName,
                text: text,
                timestamp: timestamp,
                type: type,
                mediaUrl: data["mediaUrl"] as? String,
                replyToMessageId: data["replyToMessageId"] as? String,
                isDeleted: data["isDeleted"] as? Bool ?? false,
                isEdited: data["isEdited"] as? Bool ?? false,
                deletedFor: data["deletedFor"] as? [String]
            )
        }.reversed()  // Return in chronological order
    }
    
    /// Delete a message (soft delete)
    func deleteMessage(conversationId: String, messageId: String) async throws {
        try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .updateData([
                "isDeleted": true
            ])
    }
    
    /// Delete a message for a specific user (per-user soft delete)
    func deleteMessageForUser(conversationId: String, messageId: String, userId: String) async throws {
        print("📝 [FirestoreManager] Updating message deletedFor array")
        print("   Conversation: \(conversationId)")
        print("   Message: \(messageId)")
        print("   User: \(userId)")
        
        do {
            try await db.collection("conversations")
                .document(conversationId)
                .collection("messages")
                .document(messageId)
                .updateData([
                    "deletedFor": FieldValue.arrayUnion([userId])
                ])
            print("✅ [FirestoreManager] Firestore message updated successfully")
        } catch {
            print("❌ [FirestoreManager] Firestore update failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Edit a message
    func editMessage(conversationId: String, messageId: String, newText: String) async throws {
        try await db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(messageId)
            .updateData([
                "text": newText,
                "isEdited": true,
                "editedAt": FieldValue.serverTimestamp()
            ])
    }
    
    // MARK: - Batch Operations
    
    /// Archive message and update conversation in a single batch
    func archiveMessageAndUpdateConversation(
        conversationId: String,
        message: Message,
        lastMessage: Conversation.LastMessage
    ) async throws {
        let batch = db.batch()
        
        // Archive message
        let messageRef = db.collection("conversations")
            .document(conversationId)
            .collection("messages")
            .document(message.id)
        
        let messageData: [String: Any] = [
            "id": message.id,
            "conversationId": conversationId,
            "senderId": message.senderId,
            "senderName": message.senderName,
            "text": message.text,
            "type": message.type.rawValue,
            "timestamp": FieldValue.serverTimestamp(),
            "mediaUrl": message.mediaUrl ?? NSNull(),
            "replyToMessageId": message.replyToMessageId ?? NSNull(),
            "isDeleted": false,
            "isEdited": false
        ]
        
        batch.setData(messageData, forDocument: messageRef)
        
        // Update conversation's lastMessage
        let conversationRef = db.collection("conversations").document(conversationId)
        batch.updateData([
            "lastMessage.text": lastMessage.text,
            "lastMessage.senderId": lastMessage.senderId,
            "lastMessage.senderName": lastMessage.senderName,
            "lastMessage.timestamp": Timestamp(date: lastMessage.timestamp),
            "lastMessage.type": lastMessage.type,
            "metadata.totalMessages": FieldValue.increment(Int64(1))
        ], forDocument: conversationRef)
        
        try await batch.commit()
    }
    
    // MARK: - Member Management
    
    /// Add member to conversation
    func addMemberToConversation(
        conversationId: String,
        userId: String,
        memberDetail: Conversation.MemberDetail
    ) async throws {
        try await db.collection("conversations")
            .document(conversationId)
            .updateData([
                "memberIds": FieldValue.arrayUnion([userId]),
                "memberDetails.\(userId)": [
                    "displayName": memberDetail.displayName,
                    "photoURL": memberDetail.photoURL as Any,
                    "joinedAt": Timestamp(date: memberDetail.joinedAt)
                ]
            ])
    }
    
    /// Remove member from conversation
    func removeMemberFromConversation(conversationId: String, userId: String) async throws {
        try await db.collection("conversations")
            .document(conversationId)
            .updateData([
                "memberIds": FieldValue.arrayRemove([userId]),
                "memberDetails.\(userId)": FieldValue.delete()
            ])
    }
}


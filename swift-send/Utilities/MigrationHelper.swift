//
//  MigrationHelper.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/23/25.
//

import Foundation
import FirebaseDatabase
import FirebaseFirestore
import FirebaseAuth

/// Helper for migrating data from legacy structure to new hybrid architecture
class MigrationHelper {
    private let rtdb = Database.database().reference()
    private let db = Firestore.firestore()
    
    // MARK: - Migrate User's Chats to Conversations
    
    /// Migrate all legacy chats for a user to the new conversation structure
    func migrateLegacyChats(userId: String) async throws {
        print("Starting migration for user: \(userId)")
        
        // Get all legacy chats
        let snapshot = try await rtdb.child("users").child(userId).child("chats").getData()
        
        guard let chatsData = snapshot.value as? [String: [String: Any]] else {
            print("No legacy chats found")
            return
        }
        
        for (chatId, chatData) in chatsData {
            do {
                try await migrateSingleChat(chatId: chatId, chatData: chatData, userId: userId)
                print("Migrated chat: \(chatId)")
            } catch {
                print("Error migrating chat \(chatId): \(error.localizedDescription)")
            }
        }
        
        print("Migration completed for user: \(userId)")
    }
    
    private func migrateSingleChat(chatId: String, chatData: [String: Any], userId: String) async throws {
        // Check if conversation already exists in Firestore
        let conversationRef = db.collection("conversations").document(chatId)
        let conversationDoc = try await conversationRef.getDocument()
        
        if conversationDoc.exists {
            print("Conversation \(chatId) already exists, skipping")
            return
        }
        
        // Get chat metadata from RTDB
        let metadataSnapshot = try await rtdb.child("chats").child(chatId).child("metadata").getData()
        guard let metadata = metadataSnapshot.value as? [String: Any],
              let participants = metadata["participants"] as? [String] else {
            print("Missing metadata for chat \(chatId)")
            return
        }
        
        // Get member details
        var memberDetails: [String: Conversation.MemberDetail] = [:]
        for participantId in participants {
            let profileSnapshot = try? await rtdb.child("userProfiles").child(participantId).getData()
            if let profileData = profileSnapshot?.value as? [String: Any],
               let displayName = profileData["displayName"] as? String {
                memberDetails[participantId] = Conversation.MemberDetail(
                    displayName: displayName,
                    photoURL: profileData["photoURL"] as? String
                )
            }
        }
        
        // Determine conversation type
        let type: ConversationType = participants.count > 2 ? .group : .direct
        let name: String? = type == .group ? (chatData["title"] as? String) : nil
        
        // Get last message
        let lastMessageText = chatData["lastMessage"] as? String ?? ""
        let lastMessageTimestamp = chatData["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
        
        let lastMessage = Conversation.LastMessage(
            text: lastMessageText,
            senderId: userId,
            senderName: memberDetails[userId]?.displayName ?? "User",
            timestamp: Date(timeIntervalSince1970: lastMessageTimestamp),
            type: "text"
        )
        
        // Create conversation in Firestore
        let conversation = Conversation(
            id: chatId,
            type: type,
            name: name,
            createdAt: Date(timeIntervalSince1970: metadata["createdAt"] as? TimeInterval ?? Date().timeIntervalSince1970),
            createdBy: metadata["createdBy"] as? String ?? userId,
            memberIds: participants,
            memberDetails: memberDetails,
            lastMessage: lastMessage
        )
        
        try db.collection("conversations").document(chatId).setData(from: conversation)
        
        // Set up RTDB structure for conversation members
        try await rtdb.child("conversationMembers")
            .child(chatId)
            .setValue(Dictionary(uniqueKeysWithValues: participants.map { ($0, true) }))
        
        // Create user conversation status for each member
        for participantId in participants {
            let userConvStatus = UserConversationStatus(
                conversationId: chatId,
                unreadCount: 0,
                lastMessageTimestamp: lastMessageTimestamp * 1000
            )
            
            _ = try? await rtdb.child("userConversations")
                .child(participantId)
                .child(chatId)
                .setValue(userConvStatus.toDictionary())
        }
        
        // Migrate messages
        try await migrateMessages(chatId: chatId)
    }
    
    private func migrateMessages(chatId: String) async throws {
        let messagesSnapshot = try await rtdb.child("chats").child(chatId).child("messages").getData()
        
        guard let messagesData = messagesSnapshot.value as? [String: [String: Any]] else {
            return
        }
        
        // Archive first 50 messages to Firestore
        let sortedMessages = messagesData.sorted { (m1, m2) in
            let t1 = m1.value["timestamp"] as? TimeInterval ?? 0
            let t2 = m2.value["timestamp"] as? TimeInterval ?? 0
            return t1 < t2
        }
        
        let messagesToArchive = Array(sortedMessages.prefix(50))
        let messagesToKeepInRTDB = Array(sortedMessages.suffix(50))
        
        // Archive older messages to Firestore
        for (messageId, messageData) in messagesToArchive {
            guard let text = messageData["text"] as? String,
                  let senderId = messageData["senderId"] as? String,
                  let senderName = messageData["senderName"] as? String else {
                continue
            }
            
            let timestamp = messageData["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
            let typeString = messageData["type"] as? String ?? "text"
            
            let firestoreMessage: [String: Any] = [
                "id": messageId,
                "conversationId": chatId,
                "senderId": senderId,
                "senderName": senderName,
                "text": text,
                "type": typeString,
                "timestamp": Timestamp(date: Date(timeIntervalSince1970: timestamp)),
                "isDeleted": false,
                "isEdited": false
            ]
            
            _ = try? await db.collection("conversations")
                .document(chatId)
                .collection("messages")
                .document(messageId)
                .setData(firestoreMessage)
        }
        
        // Keep recent messages in RTDB activeMessages
        for (messageId, messageData) in messagesToKeepInRTDB {
            _ = try? await rtdb.child("conversations")
                .child(chatId)
                .child("activeMessages")
                .child(messageId)
                .setValue(messageData)
        }
    }
    
    // MARK: - Clean Up Old Data
    
    /// Clean up old RTDB data after migration (use with caution!)
    func cleanUpLegacyData(userId: String, dryRun: Bool = true) async throws {
        if dryRun {
            print("DRY RUN - No data will be deleted")
        }
        
        // Get all legacy chats
        let snapshot = try await rtdb.child("users").child(userId).child("chats").getData()
        
        guard let chatsData = snapshot.value as? [String: [String: Any]] else {
            print("No legacy chats found")
            return
        }
        
        for chatId in chatsData.keys {
            // Verify conversation exists in Firestore before deleting
            let conversationDoc = try await db.collection("conversations").document(chatId).getDocument()
            
            if conversationDoc.exists {
                if !dryRun {
                    // Delete legacy chat data
                    _ = try? await rtdb.child("chats").child(chatId).child("messages").removeValue()
                    print("Deleted legacy messages for chat: \(chatId)")
                } else {
                    print("Would delete legacy messages for chat: \(chatId)")
                }
            }
        }
    }
}


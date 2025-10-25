//
//  RealtimeManager.swift
//  swift-send
//

import Foundation
import FirebaseDatabase
import Combine

class RealtimeManager {
    static let shared = RealtimeManager()
    nonisolated private let db = Database.database().reference()

    private init() {}

    // MARK: - User Registration

    func registerUser(userId: String, email: String, displayName: String? = nil) async throws {
        let userData: [String: Any] = [
            "email": email,
            "displayName": displayName ?? email
        ]

        try await db.child("registeredUsers").child(userId).setValue(userData)
    }

    func getUser(userId: String) async throws -> UserProfile? {
        let snapshot = try await db.child("registeredUsers").child(userId).getData()

        guard let data = snapshot.value as? [String: Any],
              let email = data["email"] as? String else {
            return nil
        }

        return UserProfile(
            id: userId,
            email: email,
            displayName: data["displayName"] as? String
        )
    }

    func getAllUsers() async throws -> [UserProfile] {
        let snapshot = try await db.child("registeredUsers").getData()

        guard let usersDict = snapshot.value as? [String: [String: Any]] else {
            return []
        }

        return usersDict.compactMap { userId, userData in
            guard let email = userData["email"] as? String else { return nil }
            return UserProfile(
                id: userId,
                email: email,
                displayName: userData["displayName"] as? String
            )
        }
    }

    // MARK: - Presence

    func setPresence(userId: String, name: String) async throws {
        let presenceData: [String: Any] = [
            "name": name,
            "lastOnline": ServerValue.timestamp()
        ]

        try await db.child("presence").child(userId).setValue(presenceData)

        // Set up disconnect handler to update lastOnline when user goes offline
        try await db.child("presence").child(userId).child("lastOnline").onDisconnectSetValue(ServerValue.timestamp())
    }

    func updateLastOnline(userId: String) async throws {
        try await db.child("presence").child(userId).child("lastOnline").setValue(ServerValue.timestamp())
    }

    func observePresence(userId: String, completion: @escaping (Presence?) -> Void) -> DatabaseHandle {
        return db.child("presence").child(userId).observe(.value) { snapshot in
            guard let data = snapshot.value as? [String: Any],
                  let name = data["name"] as? String,
                  let lastOnline = data["lastOnline"] as? TimeInterval else {
                completion(nil)
                return
            }

            completion(Presence(name: name, lastOnline: lastOnline))
        }
    }

    // MARK: - Conversations

    func getOrCreateConversation(participants: [String]) async throws -> String {
        let sortedParticipants = participants.sorted()

        // Search for existing conversation
        let snapshot = try await db.child("conversations").getData()

        if let conversationsDict = snapshot.value as? [String: [String: Any]] {
            for (conversationId, conversationData) in conversationsDict {
                if let existingParticipants = conversationData["participants"] as? [String],
                   existingParticipants.sorted() == sortedParticipants {
                    return conversationId
                }
            }
        }

        // Create new conversation
        let conversationRef = db.child("conversations").childByAutoId()
        guard let conversationId = conversationRef.key else {
            throw NSError(domain: "RealtimeManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate conversation ID"])
        }

        let conversationData: [String: Any] = [
            "participants": sortedParticipants,
            "createdAt": ServerValue.timestamp()
        ]

        try await conversationRef.setValue(conversationData)
        return conversationId
    }

    func observeConversations(for userId: String, completion: @escaping ([Conversation]) -> Void) -> DatabaseHandle {
        return db.child("conversations").observe(.value) { snapshot in
            guard let conversationsDict = snapshot.value as? [String: [String: Any]] else {
                completion([])
                return
            }

            var conversations: [Conversation] = []

            for (conversationId, conversationData) in conversationsDict {
                guard let participants = conversationData["participants"] as? [String],
                      participants.contains(userId),
                      let createdAt = conversationData["createdAt"] as? TimeInterval else {
                    continue
                }

                let conversation = Conversation(
                    id: conversationId,
                    participants: participants,
                    createdAt: createdAt,
                    lastMessage: conversationData["lastMessage"] as? String,
                    lastMessageTimestamp: conversationData["lastMessageTimestamp"] as? TimeInterval
                )

                conversations.append(conversation)
            }

            // Sort by last message timestamp
            conversations.sort { ($0.lastMessageTimestamp ?? 0) > ($1.lastMessageTimestamp ?? 0) }

            completion(conversations)
        }
    }

    // MARK: - Messages

    func sendMessage(conversationId: String, senderId: String, text: String) async throws -> String {
        let messageRef = db.child("conversations").child(conversationId).child("messages").childByAutoId()

        guard let messageId = messageRef.key else {
            throw NSError(domain: "RealtimeManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate message ID"])
        }

        let messageData: [String: Any] = [
            "conversationId": conversationId,
            "senderId": senderId,
            "text": text,
            "timestamp": ServerValue.timestamp(),
            "status": MessageStatus.delivered.rawValue,
            "readBy": [senderId: ServerValue.timestamp()] // Sender auto-reads their message
        ]

        try await messageRef.setValue(messageData)

        // Update conversation's last message
        try await db.child("conversations").child(conversationId).updateChildValues([
            "lastMessage": text,
            "lastMessageTimestamp": ServerValue.timestamp()
        ])

        return messageId
    }

    func observeMessages(for conversationId: String, completion: @escaping ([Message]) -> Void) -> DatabaseHandle {
        return db.child("conversations").child(conversationId).child("messages").observe(.value) { snapshot in
            guard let messagesDict = snapshot.value as? [String: [String: Any]] else {
                completion([])
                return
            }

            var messages: [Message] = []

            for (messageId, messageData) in messagesDict {
                guard let conversationId = messageData["conversationId"] as? String,
                      let senderId = messageData["senderId"] as? String,
                      let text = messageData["text"] as? String,
                      let timestamp = messageData["timestamp"] as? TimeInterval,
                      let statusString = messageData["status"] as? String,
                      let status = MessageStatus(rawValue: statusString) else {
                    continue
                }

                var readBy: [String: TimeInterval] = [:]
                if let readByDict = messageData["readBy"] as? [String: TimeInterval] {
                    readBy = readByDict
                }

                let message = Message(
                    id: messageId,
                    conversationId: conversationId,
                    senderId: senderId,
                    text: text,
                    timestamp: timestamp,
                    status: status,
                    readBy: readBy
                )

                messages.append(message)
            }

            // Sort by timestamp
            messages.sort { $0.timestamp < $1.timestamp }

            completion(messages)
        }
    }

    func markMessageAsRead(conversationId: String, messageId: String, userId: String) async throws {
        try await db.child("conversations")
            .child(conversationId)
            .child("messages")
            .child(messageId)
            .child("readBy")
            .child(userId)
            .setValue(ServerValue.timestamp())

        // Update status to read
        try await db.child("conversations")
            .child(conversationId)
            .child("messages")
            .child(messageId)
            .child("status")
            .setValue(MessageStatus.read.rawValue)
    }

    func markConversationMessagesAsRead(conversationId: String, userId: String, senderId: String) async throws {
        let snapshot = try await db.child("conversations").child(conversationId).child("messages").getData()

        guard let messagesDict = snapshot.value as? [String: [String: Any]] else {
            return
        }

        for (messageId, messageData) in messagesDict {
            guard let messageSenderId = messageData["senderId"] as? String else { continue }

            // Don't mark sender's own messages as read by them
            if messageSenderId == userId {
                continue
            }

            // Check if already read by this user
            if let readByDict = messageData["readBy"] as? [String: Any],
               readByDict[userId] != nil {
                continue
            }

            // Mark as read
            try await markMessageAsRead(conversationId: conversationId, messageId: messageId, userId: userId)
        }
    }

    func getUnreadMessageCount(conversationId: String, userId: String) async throws -> Int {
        let snapshot = try await db.child("conversations").child(conversationId).child("messages").getData()

        guard let messagesDict = snapshot.value as? [String: [String: Any]] else {
            return 0
        }

        var unreadCount = 0

        for (_, messageData) in messagesDict {
            guard let messageSenderId = messageData["senderId"] as? String else { continue }

            // Skip messages sent by the current user
            if messageSenderId == userId {
                continue
            }

            // Check if message has been read by this user
            if let readByDict = messageData["readBy"] as? [String: Any],
               readByDict[userId] != nil {
                // Already read, skip
                continue
            }

            // Message is unread
            unreadCount += 1
        }

        return unreadCount
    }

    // MARK: - User Preferences

    func getUserPreferences(userId: String) async throws -> UserPreferences? {
        let snapshot = try await db.child("userPreferences").child(userId).getData()

        guard snapshot.exists(),
              let data = snapshot.value as? [String: Any] else {
            return nil
        }

        let preferredLanguage = data["preferredLanguage"] as? String ?? "en"
        let autoTranslate = data["autoTranslate"] as? Bool ?? false
        let showLanguageBadges = data["showLanguageBadges"] as? Bool ?? true

        return UserPreferences(
            preferredLanguage: preferredLanguage,
            autoTranslate: autoTranslate,
            showLanguageBadges: showLanguageBadges
        )
    }

    func saveUserPreferences(userId: String, preferences: UserPreferences) async throws {
        let data: [String: Any] = [
            "preferredLanguage": preferences.preferredLanguage,
            "autoTranslate": preferences.autoTranslate,
            "showLanguageBadges": preferences.showLanguageBadges
        ]

        try await db.child("userPreferences").child(userId).setValue(data)
    }

    // MARK: - Remove Observers

    nonisolated func removeObserver(handle: DatabaseHandle, path: String) {
        db.child(path).removeObserver(withHandle: handle)
    }

    nonisolated func removeAllObservers() {
        db.removeAllObservers()
    }
}

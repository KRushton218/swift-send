//
//  RealtimeManager.swift
//  swift-send
//
//  MVVM ARCHITECTURE - SERVICE LAYER
//  ==================================
//  Firebase Realtime Database gateway. Singleton providing async/await interface to Firebase.
//  All Firebase operations go through this manager - no direct Firebase calls elsewhere.
//
//  Key Patterns:
//  1. Observer pattern for real-time updates (observeMessages, observeConversations, etc.)
//  2. Async/await throughout for clean async code
//  3. Offline persistence enabled (writes queue automatically when offline)
//  4. Server timestamps for clock skew protection (ServerValue.timestamp())
//  5. Disconnect handlers for automatic cleanup (onDisconnectSetValue)
//
//  Usage:
//  ViewModels call RealtimeManager methods which return data as Models.
//  No business logic here - pure data access layer.
//

import Foundation
import FirebaseDatabase
import Combine

class RealtimeManager {
    static let shared = RealtimeManager()
    nonisolated private let db = Database.database().reference()

    /// Server time offset in milliseconds (handles clock skew between client and server)
    private(set) var serverTimeOffset: TimeInterval = 0

    private init() {
        // Sync server time offset on init for accurate timestamp comparisons
        db.child(".info/serverTimeOffset").observe(.value) { [weak self] snapshot in
            if let offset = snapshot.value as? TimeInterval {
                self?.serverTimeOffset = offset
                print("📡 Server time offset: \(offset)ms")
            }
        }
    }

    // MARK: - User Registration

    func registerUser(userId: String, email: String, displayName: String? = nil) async throws {
        // Always set email (write operations work offline and sync later)
        try await db.child("registeredUsers").child(userId).child("email").setValue(email)

        // Try to check if user exists before setting displayName
        // This prevents overwriting a user's custom displayName
        do {
            let snapshot = try await db.child("registeredUsers").child(userId).child("displayName").getData()

            if !snapshot.exists() {
                // displayName doesn't exist - this is a new user, set it
                try await db.child("registeredUsers").child(userId).child("displayName").setValue(displayName ?? email)
                print("✅ New user \(userId) registered")
            } else {
                print("✅ User \(userId) already exists, skipping displayName")
            }
        } catch {
            // getData() failed - likely offline or no cache
            // We'll optimistically set displayName anyway since writes work offline
            // Risk: might overwrite custom displayName, but unlikely on every sign-in
            print("⚠️ Cannot verify user existence (likely offline), setting displayName anyway")

            try await db.child("registeredUsers").child(userId).child("displayName").setValue(displayName ?? email)
        }
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

    /// Sets user as online and configures Firebase disconnect handlers
    /// Disconnect handlers automatically update presence when connection lost (app close, network failure)
    func setPresence(userId: String, name: String) async throws {
        let presenceData: [String: Any] = [
            "name": name,
            "isOnline": true,
            "lastOnline": ServerValue.timestamp()  // Server timestamp prevents clock skew
        ]

        try await db.child("presence").child(userId).setValue(presenceData)

        // Firebase disconnect handlers: auto-update when connection lost
        try await db.child("presence").child(userId).child("isOnline").onDisconnectSetValue(false)
        try await db.child("presence").child(userId).child("lastOnline").onDisconnectSetValue(ServerValue.timestamp())
    }

    func updateLastOnline(userId: String) async throws {
        try await db.child("presence").child(userId).child("lastOnline").setValue(ServerValue.timestamp())
    }

    func setOnline(userId: String) async throws {
        let updates: [String: Any] = [
            "isOnline": true,
            "lastOnline": ServerValue.timestamp()
        ]
        try await db.child("presence").child(userId).updateChildValues(updates)

        // Re-register disconnect handlers to handle reconnections
        // This ensures that if we disconnect again, we'll be marked offline
        try await db.child("presence").child(userId).child("isOnline").onDisconnectSetValue(false)
        try await db.child("presence").child(userId).child("lastOnline").onDisconnectSetValue(ServerValue.timestamp())
    }

    func setOffline(userId: String) async throws {
        let updates: [String: Any] = [
            "isOnline": false,
            "lastOnline": ServerValue.timestamp()
        ]
        try await db.child("presence").child(userId).updateChildValues(updates)
    }

    func observePresence(userId: String, completion: @escaping (Presence?) -> Void) -> DatabaseHandle {
        return db.child("presence").child(userId).observe(.value) { snapshot in
            guard let data = snapshot.value as? [String: Any],
                  let name = data["name"] as? String,
                  let isOnline = data["isOnline"] as? Bool,
                  let lastOnline = data["lastOnline"] as? TimeInterval else {
                completion(nil)
                return
            }

            completion(Presence(name: name, isOnline: isOnline, lastOnline: lastOnline))
        }
    }

    // MARK: - Typing Indicators

    func setTyping(conversationId: String, userId: String, name: String, isTyping: Bool) async throws {
        let typingPath = db.child("typing").child(conversationId).child(userId)

        if isTyping {
            let typingData: [String: Any] = [
                "name": name,
                "timestamp": ServerValue.timestamp(),
                "isTyping": true
            ]

            print("⌨️ [RTDB] Writing typing indicator: /typing/\(conversationId)/\(userId)")
            try await typingPath.setValue(typingData)

            // Auto-clear typing indicator on disconnect
            try await typingPath.onDisconnectRemoveValue()
        } else {
            // Remove typing indicator when user stops typing
            print("⌨️ [RTDB] Removing typing indicator: /typing/\(conversationId)/\(userId)")
            try await typingPath.removeValue()
        }
    }

    func observeTypingIndicators(conversationId: String, completion: @escaping ([TypingIndicator]) -> Void) -> DatabaseHandle {
        print("⌨️ [RTDB] Setting up typing indicator observer for conversation: \(conversationId)")
        return db.child("typing").child(conversationId).observe(.value) { snapshot in
            print("⌨️ [RTDB] Typing indicator update received. Snapshot exists: \(snapshot.exists())")

            guard let typingDict = snapshot.value as? [String: [String: Any]] else {
                print("⌨️ [RTDB] No typing users or invalid data format")
                completion([])
                return
            }

            print("⌨️ [RTDB] Raw typing data: \(typingDict)")

            var typingUsers: [TypingIndicator] = []

            for (userId, typingData) in typingDict {
                guard let name = typingData["name"] as? String,
                      let timestamp = typingData["timestamp"] as? TimeInterval,
                      let isTyping = typingData["isTyping"] as? Bool,
                      isTyping else {
                    print("⌨️ [RTDB] Skipping invalid typing data for user \(userId)")
                    continue
                }

                print("⌨️ [RTDB] Found typing user: \(name) (id: \(userId))")

                typingUsers.append(TypingIndicator(
                    id: userId,
                    name: name,
                    timestamp: timestamp,
                    isTyping: isTyping
                ))
            }

            print("⌨️ [RTDB] Returning \(typingUsers.count) typing users")
            completion(typingUsers)
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
                    readBy: readBy,
                    embeddingId: messageData["embeddingId"] as? String,
                    translatedText: messageData["translatedText"] as? String,
                    detectedLanguage: messageData["detectedLanguage"] as? String,
                    translatedTo: messageData["translatedTo"] as? String
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

        guard let data = snapshot.value as? [String: Any] else {
            return nil
        }

        let preferredLanguage = data["preferredLanguage"] as? String ?? "en"
        let autoTranslate = data["autoTranslate"] as? Bool ?? false
        let showLanguageBadges = data["showLanguageBadges"] as? Bool ?? true
        let showTranslationExtras = data["showTranslationExtras"] as? Bool ?? true

        return UserPreferences(
            preferredLanguage: preferredLanguage,
            autoTranslate: autoTranslate,
            showLanguageBadges: showLanguageBadges,
            showTranslationExtras: showTranslationExtras
        )
    }

    func saveUserPreferences(userId: String, preferences: UserPreferences) async throws {
        let preferencesData: [String: Any] = [
            "preferredLanguage": preferences.preferredLanguage,
            "autoTranslate": preferences.autoTranslate,
            "showLanguageBadges": preferences.showLanguageBadges,
            "showTranslationExtras": preferences.showTranslationExtras
        ]

        try await db.child("userPreferences").child(userId).setValue(preferencesData)
    }

    // MARK: - Connection Monitoring

    /// Observe Firebase RTDB connection state
    /// This is the single source of truth for connection status
    /// Multiple observers can listen to this instead of creating duplicate .info/connected observers
    func observeConnectionState(completion: @escaping (Bool) -> Void) -> DatabaseHandle {
        return db.child(".info/connected").observe(.value) { snapshot in
            let connected = snapshot.value as? Bool ?? false
            completion(connected)
        }
    }

    // MARK: - Observer Lifecycle Management

    /// CRITICAL: Remove observer to prevent memory leaks
    /// Must be called in deinit with the SAME path used during registration
    /// Each active observer maintains an open connection to Firebase until removed
    ///
    /// Pattern:
    /// 1. Register: handle = observeMessages(...) → Store handle
    /// 2. Use: Callback fires on data changes
    /// 3. Cleanup: removeObserver(handle, path) in deinit
    nonisolated func removeObserver(handle: DatabaseHandle, path: String) {
        db.child(path).removeObserver(withHandle: handle)
    }

    /// Nuclear option: removes ALL observers for entire database reference
    /// Use sparingly - typically only on app termination
    nonisolated func removeAllObservers() {
        db.removeAllObservers()
    }
}

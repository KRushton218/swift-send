//
//  Models.swift
//  swift-send
//
//  MVVM ARCHITECTURE - MODEL LAYER
//  Pure data structures with no business logic.
//  Flow: Firebase RTDB → RealtimeManager → Models → ViewModels → Views
//

import Foundation

// MARK: - User Profile
/// Registered user model. Stored in Firebase at /users/{userId}
struct UserProfile: Identifiable, Codable {
    var id: String
    var email: String
    var displayName: String?

    var userId: String {
        id
    }
}

// MARK: - Presence
/// Real-time online/offline status. Updated via heartbeat every 1s (AuthManager)
struct Presence: Codable {
    var name: String
    var isOnline: Bool
    var lastOnline: TimeInterval  // Server timestamp in milliseconds
}

// MARK: - Typing Indicator
/// Ephemeral typing status. Auto-expires after 5s via Firebase disconnect handlers
struct TypingIndicator: Codable, Identifiable {
    var id: String  // userId
    var name: String
    var timestamp: TimeInterval
    var isTyping: Bool
}

// MARK: - Message Status
/// Message delivery state for optimistic UI pattern
enum MessageStatus: String, Codable {
    case sending    // Optimistic - shown immediately before Firebase confirms
    case delivered  // Confirmed by Firebase observer
    case read       // At least one recipient read it
    case failed     // Send failed, user can retry
}

// MARK: - Message
/// Core message model with optimistic UI support and translation
/// Flow: User types → optimistic Message(status: .sending) → Firebase → observer confirms → status: .delivered
struct Message: Identifiable, Codable {
    var id: String
    var conversationId: String
    var senderId: String
    var text: String
    var timestamp: TimeInterval
    var status: MessageStatus
    var readBy: [String: TimeInterval]  // userId: timestamp when read
    var embeddingId: String?  // Pinecone vector ID for semantic search/RAG

    // Translation fields (populated by TranslationManager, persisted in Firebase)
    var translatedText: String?
    var detectedLanguage: String?
    var translatedTo: String?

    var hasTranslation: Bool {
        translatedText != nil && detectedLanguage != nil && translatedTo != nil
    }

    func isReadBy(userId: String) -> Bool {
        readBy.keys.contains(userId)
    }

    func readByUsers(excluding senderId: String) -> [String] {
        readBy.keys.filter { $0 != senderId }
    }
}

// MARK: - Conversation
/// Conversation between 2+ users. Stored in Firebase at /conversations/{conversationId}
struct Conversation: Identifiable, Codable {
    var id: String
    var participants: [String]  // Array of user IDs
    var createdAt: TimeInterval
    var lastMessage: String?
    var lastMessageTimestamp: TimeInterval?

    var conversationId: String {
        id
    }

    var isGroupChat: Bool {
        participants.count > 2
    }
}

// MARK: - User Preferences
/// User settings for translation features. Stored in Firebase at /user_preferences/{userId}
struct UserPreferences: Codable, Equatable {
    var preferredLanguage: String
    var autoTranslate: Bool
    var showLanguageBadges: Bool
    var showTranslationExtras: Bool  // Show sparkles button for cultural context/slang

    static var defaultPreferences: UserPreferences {
        UserPreferences(
            preferredLanguage: "en",
            autoTranslate: false,
            showLanguageBadges: true,
            showTranslationExtras: true
        )
    }
}

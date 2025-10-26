//
//  Models.swift
//  swift-send
//

import Foundation

// MARK: - User Profile
struct UserProfile: Identifiable, Codable {
    var id: String
    var email: String
    var displayName: String?

    var userId: String {
        id
    }
}

// MARK: - Presence
struct Presence: Codable {
    var name: String
    var isOnline: Bool
    var lastOnline: TimeInterval
}

// MARK: - Typing Indicator
struct TypingIndicator: Codable, Identifiable {
    var id: String // userId
    var name: String
    var timestamp: TimeInterval
    var isTyping: Bool
}

// MARK: - Message Status
enum MessageStatus: String, Codable {
    case sending
    case delivered
    case read
}

// MARK: - Message
struct Message: Identifiable, Codable {
    var id: String
    var conversationId: String
    var senderId: String
    var text: String
    var timestamp: TimeInterval
    var status: MessageStatus
    var readBy: [String: TimeInterval] // userId: timestamp when read
    var embeddingId: String? // Pinecone vector ID for RAG

    // Translation fields
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
struct Conversation: Identifiable, Codable {
    var id: String
    var participants: [String]
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
struct UserPreferences: Codable, Equatable {
    var preferredLanguage: String
    var autoTranslate: Bool
    var showLanguageBadges: Bool

    static var defaultPreferences: UserPreferences {
        UserPreferences(
            preferredLanguage: "en",
            autoTranslate: false,
            showLanguageBadges: true
        )
    }
}

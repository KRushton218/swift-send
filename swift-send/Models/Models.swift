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
    var lastOnline: TimeInterval
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

    // AI Features
    var detectedLanguage: String?
    var translatedText: String?
    var translatedTo: String?
    var embeddingId: String? // Pinecone vector ID

    func isReadBy(userId: String) -> Bool {
        readBy.keys.contains(userId)
    }

    func readByUsers(excluding senderId: String) -> [String] {
        readBy.keys.filter { $0 != senderId }
    }

    // Check if message has a translation
    var hasTranslation: Bool {
        translatedText != nil && !translatedText!.isEmpty
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
    var preferredLanguage: String // Language code (e.g., "en", "es")
    var autoTranslate: Bool
    var showLanguageBadges: Bool

    static let defaultPreferences = UserPreferences(
        preferredLanguage: "en",
        autoTranslate: false,
        showLanguageBadges: true
    )
}

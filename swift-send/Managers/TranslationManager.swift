//
//  TranslationManager.swift
//  swift-send
//
//  Manager for handling message translations
//

import Foundation
import Combine
import FirebaseDatabase

@MainActor
class TranslationManager: ObservableObject {
    static let shared = TranslationManager()

    @Published var isTranslating: [String: Bool] = [:] // messageId: isTranslating
    @Published var translationErrors: [String: String] = [:] // messageId: error
    @Published var translations: [String: TranslationData] = [:] // messageId: translation data

    private let aiService = AIServiceManager.shared
    private let realtimeManager = RealtimeManager.shared

    private init() {}

    struct TranslationData {
        let translatedText: String
        let detectedLanguage: String
        let targetLanguage: String
    }

    // Supported languages with display names
    let supportedLanguages: [String: String] = [
        "en": "English",
        "zh": "Chinese",
        "es": "Spanish",
        "fr": "French",
        "de": "German",
        "ja": "Japanese",
        "ko": "Korean",
        "pt": "Portuguese",
        "ru": "Russian",
        "ar": "Arabic"
    ]

    /// Translate a message and store the result in RTDB
    func translateMessage(
        _ message: Message,
        to targetLanguage: String
    ) async throws {
        let messageId = message.id

        print("🔄 [TranslationManager] Starting translation")
        print("   MessageID: \(messageId)")
        print("   ConversationID: \(message.conversationId)")
        print("   Target Language: \(targetLanguage)")

        // Set loading state
        isTranslating[messageId] = true
        translationErrors[messageId] = nil

        defer {
            isTranslating[messageId] = false
            print("🔄 [TranslationManager] Loading state cleared")
        }

        do {
            // Call Cloud Function
            print("📞 [TranslationManager] Calling AIService...")
            let response = try await aiService.translateMessage(
                messageId: messageId,
                text: message.text,
                targetLanguage: targetLanguage
            )

            // Store translation in memory for immediate UI update
            print("💾 [TranslationManager] Storing translation in memory...")
            translations[messageId] = TranslationData(
                translatedText: response.translatedText,
                detectedLanguage: response.detectedLanguage,
                targetLanguage: targetLanguage
            )

            // Also update RTDB for persistence
            print("💾 [TranslationManager] Updating RTDB...")
            try await updateMessageTranslation(
                conversationId: message.conversationId,
                messageId: messageId,
                translatedText: response.translatedText,
                detectedLanguage: response.detectedLanguage,
                targetLanguage: targetLanguage
            )

            print("✅ [TranslationManager] Translation complete!")

        } catch {
            // Store error for UI to display
            print("❌ [TranslationManager] Error: \(error)")
            print("   LocalizedDescription: \(error.localizedDescription)")
            translationErrors[messageId] = error.localizedDescription
            throw error
        }
    }

    /// Update message translation fields in RTDB
    private func updateMessageTranslation(
        conversationId: String,
        messageId: String,
        translatedText: String,
        detectedLanguage: String,
        targetLanguage: String
    ) async throws {
        let db = Database.database().reference()
        let messageRef = db.child("conversations/\(conversationId)/messages/\(messageId)")

        let updates: [String: Any] = [
            "translatedText": translatedText,
            "detectedLanguage": detectedLanguage,
            "translatedTo": targetLanguage
        ]

        print("   RTDB path: conversations/\(conversationId)/messages/\(messageId)")
        print("   Updates: \(updates)")

        try await messageRef.updateChildValues(updates)
        print("   ✅ RTDB update successful")
    }

    /// Clear translation for a message
    func clearTranslation(
        conversationId: String,
        messageId: String
    ) async throws {
        // Remove from memory first for immediate UI update
        translations.removeValue(forKey: messageId)

        // Also clear from RTDB
        let db = Database.database().reference()
        let messageRef = db.child("conversations/\(conversationId)/messages/\(messageId)")

        let updates: [String: Any?] = [
            "translatedText": nil,
            "detectedLanguage": nil,
            "translatedTo": nil
        ]

        try await messageRef.updateChildValues(updates as [AnyHashable: Any])
    }

    /// Get language display name
    func getLanguageName(code: String) -> String {
        supportedLanguages[code] ?? code.uppercased()
    }

    /// Detect if translation is needed based on user preferences
    func shouldAutoTranslate(
        message: Message,
        currentUserId: String,
        preferences: UserPreferences
    ) -> Bool {
        // Don't translate own messages
        if message.senderId == currentUserId {
            return false
        }

        // Don't translate if already translated
        if message.hasTranslation {
            return false
        }

        // Check if auto-translate is enabled
        return preferences.autoTranslate
    }

    /// Generate embeddings for messages in batch
    func generateEmbeddingsForMessages(
        _ messages: [Message]
    ) async {
        // Process in batches of 5 to avoid overwhelming the API
        let batchSize = 5

        for i in stride(from: 0, to: messages.count, by: batchSize) {
            let batch = Array(messages[i..<min(i + batchSize, messages.count)])

            await withTaskGroup(of: Void.self) { group in
                for message in batch {
                    // Skip if already has embedding
                    if message.embeddingId != nil {
                        continue
                    }

                    group.addTask {
                        do {
                            let response = try await self.aiService.generateEmbedding(
                                messageId: message.id,
                                conversationId: message.conversationId,
                                text: message.text
                            )

                            // Update message with embedding ID
                            try await self.updateMessageEmbedding(
                                conversationId: message.conversationId,
                                messageId: message.id,
                                embeddingId: response.vectorId
                            )
                        } catch {
                            print("Failed to generate embedding for message \(message.id): \(error)")
                        }
                    }
                }
            }

            // Small delay between batches
            if i + batchSize < messages.count {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
        }
    }

    /// Update message embedding ID in RTDB
    private func updateMessageEmbedding(
        conversationId: String,
        messageId: String,
        embeddingId: String
    ) async throws {
        let db = Database.database().reference()
        let messageRef = db.child("conversations/\(conversationId)/messages/\(messageId)")

        try await messageRef.updateChildValues(["embeddingId": embeddingId])
    }
}

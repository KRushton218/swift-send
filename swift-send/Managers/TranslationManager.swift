//
//  TranslationManager.swift
//  swift-send
//
//  SERVICE LAYER - Translation Management
//  =======================================
//  Singleton managing message translation with dual-layer caching.
//  Calls AIServiceManager (Cloud Functions) for translation, caches in-memory and Firebase.
//
//  Caching Strategy:
//  1. In-memory cache (translations dict) - immediate UI updates
//  2. Firebase persistence - survives app restart
//
//  Flow:
//  User taps translate → Call Cloud Function → Store in memory → Store in Firebase
//  Next app launch → Load from Firebase → Populate memory cache
//

import Foundation
import Combine
import FirebaseDatabase

@MainActor
class TranslationManager: ObservableObject {
    static let shared = TranslationManager()

    @Published var isTranslating: [String: Bool] = [:]  // messageId: loading state
    @Published var translationErrors: [String: String] = [:]  // messageId: error message
    @Published var translations: [String: TranslationData] = [:]  // messageId: cached translation

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

    /// Translate a message and store the result in per-user RTDB location
    func translateMessage(
        _ message: Message,
        to targetLanguage: String,
        userId: String
    ) async throws {
        let messageId = message.id

        print("🔄 [TranslationManager] Starting translation")
        print("   MessageID: \(messageId)")
        print("   UserID: \(userId)")
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

            // Store in per-user RTDB location for persistence
            print("💾 [TranslationManager] Updating RTDB (per-user)...")
            try await saveUserTranslation(
                userId: userId,
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

    /// Save translation to per-user RTDB location
    /// Path: user_translations/{userId}/{messageId}
    private func saveUserTranslation(
        userId: String,
        messageId: String,
        translatedText: String,
        detectedLanguage: String,
        targetLanguage: String
    ) async throws {
        let db = Database.database().reference()
        let translationRef = db.child("user_translations/\(userId)/\(messageId)")

        let translationData: [String: Any] = [
            "translatedText": translatedText,
            "detectedLanguage": detectedLanguage,
            "targetLanguage": targetLanguage,
            "timestamp": ServerValue.timestamp()
        ]

        print("   RTDB path: user_translations/\(userId)/\(messageId)")
        print("   Data: \(translationData)")

        try await translationRef.setValue(translationData)
        print("   ✅ User translation saved successfully")
    }

    /// Clear translation for a message (per-user)
    func clearTranslation(
        userId: String,
        messageId: String
    ) async throws {
        // Remove from memory first for immediate UI update
        translations.removeValue(forKey: messageId)

        // Also clear from per-user RTDB location
        let db = Database.database().reference()
        let translationRef = db.child("user_translations/\(userId)/\(messageId)")

        try await translationRef.removeValue()
        print("   ✅ User translation cleared from RTDB")
    }

    /// Get language display name
    func getLanguageName(code: String) -> String {
        supportedLanguages[code] ?? code.uppercased()
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

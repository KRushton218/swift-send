//
//  AIServiceManager.swift
//  swift-send
//
//  Manager for calling Firebase Cloud Functions AI endpoints
//

import Foundation
import Combine
import FirebaseAuth

// MARK: - Request/Response Types

struct TranslateRequest: Codable {
    let messageId: String
    let text: String
    let targetLanguage: String
    let userId: String
}

struct TranslateResponse: Codable {
    let translatedText: String
    let detectedLanguage: String
    let targetLanguage: String
    let fromCache: Bool
}

struct EmbeddingRequest: Codable {
    let messageId: String
    let conversationId: String
    let text: String
    let userId: String
}

struct EmbeddingResponse: Codable {
    let vectorId: String
    let dimensions: Int
    let success: Bool
}

struct SemanticSearchRequest: Codable {
    let conversationId: String
    let query: String
    let topK: Int?
    let userId: String
}

struct SearchResult: Codable {
    let messageId: String
    let text: String
    let score: Double
    let timestamp: TimeInterval
}

struct SemanticSearchResponse: Codable {
    let results: [SearchResult]
}

struct InsightsRequest: Codable {
    let conversationId: String
    let query: String
    let userId: String
}

struct RelevantMessage: Codable {
    let messageId: String
    let text: String
}

struct InsightsResponse: Codable {
    let insight: String
    let relevantMessages: [RelevantMessage]
}

struct ErrorResponse: Codable {
    let error: String
    let retryAfter: Int?
}

// MARK: - AI Service Manager

@MainActor
class AIServiceManager: ObservableObject {
    static let shared = AIServiceManager()

    // Firebase Cloud Functions base URL
    private let functionsBaseURL = "https://us-central1-swift-send-bbb98.cloudfunctions.net"

    private init() {}

    // MARK: - Translation

    /// Translate a message to the target language
    func translateMessage(
        messageId: String,
        text: String,
        targetLanguage: String
    ) async throws -> TranslateResponse {
        print("🌍 [TRANSLATE] Starting translation request")
        print("   MessageID: \(messageId)")
        print("   Text: '\(text)'")
        print("   Target Language: \(targetLanguage)")

        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ [TRANSLATE] Not authenticated")
            throw AIServiceError.notAuthenticated
        }

        print("   UserID: \(userId)")

        let request = TranslateRequest(
            messageId: messageId,
            text: text,
            targetLanguage: targetLanguage,
            userId: userId
        )

        let response = try await callCloudFunction(
            endpoint: "translateMessage",
            request: request,
            responseType: TranslateResponse.self
        )

        print("✅ [TRANSLATE] Success!")
        print("   Translated: '\(response.translatedText)'")
        print("   Detected Language: \(response.detectedLanguage)")
        print("   From Cache: \(response.fromCache)")

        return response
    }

    // MARK: - Embeddings

    /// Generate and store an embedding for a message
    func generateEmbedding(
        messageId: String,
        conversationId: String,
        text: String
    ) async throws -> EmbeddingResponse {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw AIServiceError.notAuthenticated
        }

        let request = EmbeddingRequest(
            messageId: messageId,
            conversationId: conversationId,
            text: text,
            userId: userId
        )

        return try await callCloudFunction(
            endpoint: "generateEmbedding",
            request: request,
            responseType: EmbeddingResponse.self
        )
    }

    // MARK: - Semantic Search

    /// Search for semantically similar messages in a conversation
    func semanticSearch(
        conversationId: String,
        query: String,
        topK: Int = 5
    ) async throws -> SemanticSearchResponse {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw AIServiceError.notAuthenticated
        }

        let request = SemanticSearchRequest(
            conversationId: conversationId,
            query: query,
            topK: topK,
            userId: userId
        )

        return try await callCloudFunction(
            endpoint: "semanticSearch",
            request: request,
            responseType: SemanticSearchResponse.self
        )
    }

    // MARK: - Insights

    /// Generate AI insights from conversation using RAG
    func generateInsights(
        conversationId: String,
        query: String
    ) async throws -> InsightsResponse {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw AIServiceError.notAuthenticated
        }

        let request = InsightsRequest(
            conversationId: conversationId,
            query: query,
            userId: userId
        )

        return try await callCloudFunction(
            endpoint: "generateInsights",
            request: request,
            responseType: InsightsResponse.self
        )
    }

    // MARK: - Generic Cloud Function Caller

    private func callCloudFunction<Request: Encodable, Response: Decodable>(
        endpoint: String,
        request: Request,
        responseType: Response.Type
    ) async throws -> Response {
        print("📡 [API] Calling endpoint: \(endpoint)")

        guard let url = URL(string: "\(functionsBaseURL)/\(endpoint)") else {
            print("❌ [API] Invalid URL")
            throw AIServiceError.invalidURL
        }
        print("   URL: \(url)")

        // Get auth token
        guard let user = Auth.auth().currentUser else {
            print("❌ [API] Not authenticated")
            throw AIServiceError.notAuthenticated
        }

        let token = try await user.getIDToken()
        print("   Auth token obtained")

        // Create request
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        // Encode body
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        urlRequest.httpBody = try encoder.encode(request)

        if let bodyData = urlRequest.httpBody, let bodyString = String(data: bodyData, encoding: .utf8) {
            print("   Request body: \(bodyString)")
        }

        // Make request
        print("   Sending request...")
        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [API] Invalid response type")
            throw AIServiceError.invalidResponse
        }

        print("   Response status: \(httpResponse.statusCode)")

        if let responseString = String(data: data, encoding: .utf8) {
            print("   Response body: \(responseString)")
        }

        // Handle rate limiting
        if httpResponse.statusCode == 429 {
            let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            print("⚠️ [API] Rate limited - retry after \(errorResponse?.retryAfter ?? 60)s")
            throw AIServiceError.rateLimited(retryAfter: errorResponse?.retryAfter ?? 60)
        }

        // Handle errors
        if httpResponse.statusCode != 200 {
            let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            let errorMsg = errorResponse?.error ?? "Unknown error"
            print("❌ [API] Error \(httpResponse.statusCode): \(errorMsg)")
            throw AIServiceError.serverError(
                message: errorMsg,
                statusCode: httpResponse.statusCode
            )
        }

        // Decode response
        let decoder = JSONDecoder()
        let decodedResponse = try decoder.decode(responseType, from: data)
        print("✅ [API] Response decoded successfully")
        return decodedResponse
    }
}

// MARK: - Errors

enum AIServiceError: LocalizedError {
    case notAuthenticated
    case invalidURL
    case invalidResponse
    case rateLimited(retryAfter: Int)
    case serverError(message: String, statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to use AI features"
        case .invalidURL:
            return "Invalid service URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .rateLimited(let retryAfter):
            return "Rate limit exceeded. Please try again in \(retryAfter) seconds"
        case .serverError(let message, let statusCode):
            return "Server error (\(statusCode)): \(message)"
        }
    }
}

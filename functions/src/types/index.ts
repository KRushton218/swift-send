/**
 * Type definitions for swift-send Cloud Functions
 */

// Request/Response types for Cloud Functions
export interface TranslateMessageRequest {
  messageId: string;
  text: string;
  targetLanguage: string;
  userId: string;
}

export interface TranslateMessageResponse {
  translatedText: string;
  detectedLanguage: string;
  targetLanguage: string;
  fromCache: boolean;
}

export interface GenerateEmbeddingRequest {
  messageId: string;
  conversationId: string;
  text: string;
  userId: string;
}

export interface GenerateEmbeddingResponse {
  vectorId: string;
  dimensions: number;
  success: boolean;
}

export interface SemanticSearchRequest {
  conversationId: string;
  query: string;
  topK?: number;
  userId: string;
}

export interface SemanticSearchResponse {
  results: Array<{
    messageId: string;
    text: string;
    score: number;
    timestamp: number;
  }>;
}

export interface GenerateInsightsRequest {
  conversationId: string;
  query: string;
  userId: string;
}

export interface GenerateInsightsResponse {
  insight: string;
  relevantMessages: Array<{
    messageId: string;
    text: string;
  }>;
}

// Internal types
export interface CachedTranslation {
  translatedText: string;
  detectedLanguage: string;
  targetLanguage: string;
  timestamp: number;
}

export interface RateLimitData {
  count: number;
  resetTime: number;
}

// OpenAI types
export interface OpenAIMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

// Pinecone types
export interface PineconeVector {
  id: string;
  values: number[];
  metadata: {
    messageId: string;
    conversationId: string;
    text: string;
    timestamp: number;
    userId: string;
  };
}

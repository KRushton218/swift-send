/**
 * Firebase Cloud Functions for swift-send AI features
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import {
  TranslateMessageRequest,
  TranslateMessageResponse,
  GenerateEmbeddingRequest,
  GenerateEmbeddingResponse,
  SemanticSearchRequest,
  SemanticSearchResponse,
  GenerateInsightsRequest,
  GenerateInsightsResponse,
  CachedTranslation,
} from './types';
import {getOpenAIService} from './services/openai.service';
import {getPineconeService} from './services/pinecone.service';
import {
  generateTranslationCacheKey,
  checkRateLimit,
  verifyAuthToken,
  sanitizeText,
  formatError,
} from './utils';
import {config, validateConfig} from './config';

// Initialize Firebase Admin
admin.initializeApp();

// Validate configuration on startup
console.log('🚀 Cloud Functions initializing...');
const configValidation = validateConfig();
if (!configValidation.valid) {
  console.error('⚠️ WARNING: Configuration errors detected:', configValidation.errors);
  console.error('⚠️ Functions may not work correctly without proper configuration');
}

/**
 * Translate a message with caching and rate limiting
 */
export const translateMessage = functions.https.onRequest(
  async (req, res) => {
    console.log('🌍 translateMessage called');

    // CORS headers
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

    if (req.method === 'OPTIONS') {
      console.log('✅ OPTIONS request - returning 204');
      res.status(204).send('');
      return;
    }

    if (req.method !== 'POST') {
      console.log('❌ Invalid method:', req.method);
      res.status(405).json({error: 'Method not allowed'});
      return;
    }

    try {
      console.log('🔐 Verifying authentication...');
      // Verify authentication
      const user = await verifyAuthToken(req.headers.authorization);
      if (!user) {
        console.log('❌ Authentication failed');
        res.status(401).json({error: 'Unauthorized'});
        return;
      }
      console.log('✅ User authenticated:', user.uid);

      const body = req.body as TranslateMessageRequest;
      console.log('📝 Request body:', {
        messageId: body.messageId,
        textLength: body.text?.length,
        targetLanguage: body.targetLanguage,
      });

      // Validate request
      if (!body.text || !body.targetLanguage) {
        console.log('❌ Missing required fields');
        res.status(400).json({error: 'Missing required fields'});
        return;
      }

      // Check rate limit
      console.log('⏱️ Checking rate limit...');
      const rateLimitCheck = await checkRateLimit(user.uid, 'translation');
      if (!rateLimitCheck.allowed) {
        console.log('❌ Rate limit exceeded');
        res.status(429).json({
          error: 'Rate limit exceeded',
          retryAfter: rateLimitCheck.retryAfter,
        });
        return;
      }
      console.log('✅ Rate limit OK');

      const sanitizedText = sanitizeText(body.text);
      const cacheKey = generateTranslationCacheKey(
        sanitizedText,
        body.targetLanguage
      );
      console.log('🔑 Cache key generated:', cacheKey);

      // Check cache first
      console.log('💾 Checking cache...');
      const db = admin.database();
      const cacheRef = db.ref(`translationCache/${cacheKey}`);
      const cacheSnapshot = await cacheRef.get();

      if (cacheSnapshot.exists()) {
        const cached: CachedTranslation = cacheSnapshot.val();

        // Check if cache is still valid
        const cacheAge = Date.now() - cached.timestamp;
        if (cacheAge < config.translation.cacheTTL) {
          console.log('✅ Cache hit! Age:', Math.floor(cacheAge / 1000), 'seconds');
          const response: TranslateMessageResponse = {
            translatedText: cached.translatedText,
            detectedLanguage: cached.detectedLanguage,
            targetLanguage: body.targetLanguage,
            fromCache: true,
          };
          res.status(200).json(response);
          return;
        }
        console.log('⚠️ Cache expired, age:', Math.floor(cacheAge / 1000), 'seconds');
      } else {
        console.log('ℹ️ Cache miss');
      }

      // Perform translation
      console.log('🤖 Calling OpenAI for translation...');
      const openai = getOpenAIService();
      const result = await openai.translateText(
        sanitizedText,
        body.targetLanguage
      );
      console.log('✅ Translation complete:', {
        detectedLanguage: result.detectedLanguage,
        translatedLength: result.translatedText.length,
      });

      // Store in cache
      console.log('💾 Storing in cache...');
      const cacheData: CachedTranslation = {
        translatedText: result.translatedText,
        detectedLanguage: result.detectedLanguage,
        targetLanguage: body.targetLanguage,
        timestamp: Date.now(),
      };
      await cacheRef.set(cacheData);
      console.log('✅ Cache stored');

      const response: TranslateMessageResponse = {
        translatedText: result.translatedText,
        detectedLanguage: result.detectedLanguage,
        targetLanguage: body.targetLanguage,
        fromCache: false,
      };

      console.log('✅ Translation successful');
      res.status(200).json(response);
    } catch (error) {
      console.error('❌ Translation function error:', error);
      console.error('Error stack:', error instanceof Error ? error.stack : 'No stack');
      res.status(500).json(formatError(error));
    }
  }
);

/**
 * Generate embedding for a message and store in Pinecone
 */
export const generateEmbedding = functions.https.onRequest(
  async (req, res) => {
    // CORS headers
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }

    if (req.method !== 'POST') {
      res.status(405).json({error: 'Method not allowed'});
      return;
    }

    try {
      // Verify authentication
      const user = await verifyAuthToken(req.headers.authorization);
      if (!user) {
        res.status(401).json({error: 'Unauthorized'});
        return;
      }

      const body = req.body as GenerateEmbeddingRequest;

      // Validate request
      if (!body.messageId || !body.conversationId || !body.text) {
        res.status(400).json({error: 'Missing required fields'});
        return;
      }

      // Check rate limit
      const rateLimitCheck = await checkRateLimit(user.uid, 'embedding');
      if (!rateLimitCheck.allowed) {
        res.status(429).json({
          error: 'Rate limit exceeded',
          retryAfter: rateLimitCheck.retryAfter,
        });
        return;
      }

      const sanitizedText = sanitizeText(body.text);

      // Generate embedding
      const openai = getOpenAIService();
      const embedding = await openai.generateEmbedding(sanitizedText);

      // Store in Pinecone
      const pinecone = getPineconeService();
      const vectorId = await pinecone.storeEmbedding(
        body.messageId,
        body.conversationId,
        sanitizedText,
        embedding,
        user.uid,
        Date.now()
      );

      const response: GenerateEmbeddingResponse = {
        vectorId,
        dimensions: embedding.length,
        success: true,
      };

      res.status(200).json(response);
    } catch (error) {
      console.error('Generate embedding function error:', error);
      res.status(500).json(formatError(error));
    }
  }
);

/**
 * Semantic search over conversation messages
 */
export const semanticSearch = functions.https.onRequest(async (req, res) => {
  // CORS headers
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json({error: 'Method not allowed'});
    return;
  }

  try {
    // Verify authentication
    const user = await verifyAuthToken(req.headers.authorization);
    if (!user) {
      res.status(401).json({error: 'Unauthorized'});
      return;
    }

    const body = req.body as SemanticSearchRequest;

    // Validate request
    if (!body.conversationId || !body.query) {
      res.status(400).json({error: 'Missing required fields'});
      return;
    }

    const sanitizedQuery = sanitizeText(body.query);
    const topK = body.topK || config.rag.defaultTopK;

    // Generate query embedding
    const openai = getOpenAIService();
    const queryEmbedding = await openai.generateEmbedding(sanitizedQuery);

    // Search Pinecone
    const pinecone = getPineconeService();
    const results = await pinecone.searchSimilar(
      body.conversationId,
      queryEmbedding,
      topK
    );

    const response: SemanticSearchResponse = {
      results,
    };

    res.status(200).json(response);
  } catch (error) {
    console.error('Semantic search function error:', error);
    res.status(500).json(formatError(error));
  }
});

/**
 * Generate insights from conversation using RAG
 */
export const generateInsights = functions.https.onRequest(async (req, res) => {
  // CORS headers
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  if (req.method !== 'POST') {
    res.status(405).json({error: 'Method not allowed'});
    return;
  }

  try {
    // Verify authentication
    const user = await verifyAuthToken(req.headers.authorization);
    if (!user) {
      res.status(401).json({error: 'Unauthorized'});
      return;
    }

    const body = req.body as GenerateInsightsRequest;

    // Validate request
    if (!body.conversationId || !body.query) {
      res.status(400).json({error: 'Missing required fields'});
      return;
    }

    // Check rate limit
    const rateLimitCheck = await checkRateLimit(user.uid, 'insights');
    if (!rateLimitCheck.allowed) {
      res.status(429).json({
        error: 'Rate limit exceeded',
        retryAfter: rateLimitCheck.retryAfter,
      });
      return;
    }

    const sanitizedQuery = sanitizeText(body.query);

    // Generate query embedding
    const openai = getOpenAIService();
    const queryEmbedding = await openai.generateEmbedding(sanitizedQuery);

    // Search for relevant messages
    const pinecone = getPineconeService();
    const searchResults = await pinecone.searchSimilar(
      body.conversationId,
      queryEmbedding,
      config.rag.maxContextMessages
    );

    if (searchResults.length === 0) {
      res.status(200).json({
        insight:
          'I couldn\'t find any relevant messages to answer your question.',
        relevantMessages: [],
      });
      return;
    }

    // Generate insights using GPT
    const contextMessages = searchResults.map((result) => ({
      text: result.text,
      timestamp: result.timestamp,
    }));

    const insight = await openai.generateInsights(
      sanitizedQuery,
      contextMessages
    );

    const response: GenerateInsightsResponse = {
      insight,
      relevantMessages: searchResults.map((result) => ({
        messageId: result.messageId,
        text: result.text,
      })),
    };

    res.status(200).json(response);
  } catch (error) {
    console.error('Generate insights function error:', error);
    res.status(500).json(formatError(error));
  }
});

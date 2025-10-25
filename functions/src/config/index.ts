/**
 * Configuration for AI services
 * API keys should be set via Firebase Functions config
 */

import * as functions from 'firebase-functions';

export const config = {
  // OpenAI Configuration
  openai: {
    apiKey: functions.config().openai?.api_key || '',
    chatModel: 'gpt-4o-mini', // Cost-effective for translation
    embeddingModel: 'text-embedding-3-small', // 1536 dimensions
    maxTokens: 1000,
    temperature: 0.3, // Lower for more consistent translations
  },

  // Pinecone Configuration (v1.1.x)
  pinecone: {
    apiKey: functions.config().pinecone?.api_key || '',
    environment: functions.config().pinecone?.environment || 'us-east-1-aws',
    indexName: 'swift-send-messages',
    dimensions: 1536, // Must match embedding model
  },

  // Translation Settings
  translation: {
    supportedLanguages: {
      en: 'English',
      zh: 'Chinese',
      es: 'Spanish',
      fr: 'French',
      de: 'German',
      ja: 'Japanese',
      ko: 'Korean',
      pt: 'Portuguese',
      ru: 'Russian',
      ar: 'Arabic',
    },
    cacheTTL: 30 * 24 * 60 * 60 * 1000, // 30 days in milliseconds
  },

  // Rate Limiting
  rateLimit: {
    translationPerMinute: 10,
    embeddingPerMinute: 20,
    insightsPerMinute: 5,
    windowMs: 60 * 1000, // 1 minute
  },

  // RAG Configuration
  rag: {
    maxContextMessages: 20,
    similarityThreshold: 0.7,
    defaultTopK: 5,
  },
};

// Validation helper
export function validateConfig(): { valid: boolean; errors: string[] } {
  const errors: string[] = [];

  console.log('🔍 Validating configuration...');
  console.log('Config values:', {
    openaiKeySet: !!config.openai.apiKey,
    openaiKeyPrefix: config.openai.apiKey?.substring(0, 7) || 'NOT SET',
    pineconeKeySet: !!config.pinecone.apiKey,
    pineconeEnvSet: !!config.pinecone.environment,
    pineconeEnv: config.pinecone.environment,
  });

  if (!config.openai.apiKey || config.openai.apiKey === '') {
    console.error('❌ OPENAI_API_KEY not set');
    errors.push('OPENAI_API_KEY not set');
  } else {
    console.log('✅ OpenAI API key is set');
  }

  if (!config.pinecone.apiKey || config.pinecone.apiKey === '') {
    console.error('❌ PINECONE_API_KEY not set');
    errors.push('PINECONE_API_KEY not set');
  } else {
    console.log('✅ Pinecone API key is set');
  }

  if (!config.pinecone.environment || config.pinecone.environment === '') {
    console.error('❌ PINECONE_ENVIRONMENT not set');
    errors.push('PINECONE_ENVIRONMENT not set');
  } else {
    console.log('✅ Pinecone environment is set');
  }

  if (errors.length === 0) {
    console.log('✅ All configuration valid');
  } else {
    console.error('❌ Configuration errors:', errors);
  }

  return {
    valid: errors.length === 0,
    errors,
  };
}

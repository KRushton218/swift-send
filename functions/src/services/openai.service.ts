/**
 * OpenAI Service
 * Handles all interactions with OpenAI API
 */

import OpenAI from 'openai';
import {config} from '../config';
import {OpenAIMessage} from '../types';

export class OpenAIService {
  private client: OpenAI;

  constructor() {
    this.client = new OpenAI({
      apiKey: config.openai.apiKey,
    });
  }

  /**
   * Translate text and detect source language
   */
  async translateText(
    text: string,
    targetLanguage: string
  ): Promise<{ translatedText: string; detectedLanguage: string }> {
    console.log('🔧 OpenAI translateText called:', {
      textLength: text.length,
      targetLanguage,
      apiKeySet: !!config.openai.apiKey,
      apiKeyPrefix: config.openai.apiKey?.substring(0, 7),
    });

    const targetLangName =
      config.translation.supportedLanguages[
        targetLanguage as keyof typeof config.translation.supportedLanguages
      ] || targetLanguage;

    const systemPrompt = `You are a professional translator. Your task is to:
1. Detect the source language of the text
2. Translate it to ${targetLangName}
3. Preserve the tone, style, and intent of the original message
4. For informal messages (like chats), keep the casual tone

Respond in this exact JSON format:
{
  "detectedLanguage": "language_code",
  "translatedText": "translated message here"
}

Language codes: en (English), zh (Chinese), es (Spanish), fr (French), de (German), ja (Japanese), ko (Korean), pt (Portuguese), ru (Russian), ar (Arabic)`;

    const messages: OpenAIMessage[] = [
      {role: 'system', content: systemPrompt},
      {role: 'user', content: text},
    ];

    try {
      console.log('🚀 Sending request to OpenAI...');
      const response = await this.client.chat.completions.create({
        model: config.openai.chatModel,
        messages: messages,
        temperature: config.openai.temperature,
        max_tokens: config.openai.maxTokens,
        response_format: {type: 'json_object'},
      });

      console.log('✅ OpenAI response received');
      const content = response.choices[0]?.message?.content;
      if (!content) {
        console.error('❌ No content in OpenAI response');
        throw new Error('No response from OpenAI');
      }

      console.log('📦 Parsing JSON response...');
      const result = JSON.parse(content);
      console.log('✅ Translation parsed successfully');
      return {
        translatedText: result.translatedText,
        detectedLanguage: result.detectedLanguage,
      };
    } catch (error) {
      console.error('❌ OpenAI translation error:', error);
      console.error('Error details:', {
        name: error instanceof Error ? error.name : 'unknown',
        message: error instanceof Error ? error.message : 'unknown',
        stack: error instanceof Error ? error.stack : 'no stack',
      });
      throw new Error(
        `Translation failed: ${
          error instanceof Error ? error.message : 'Unknown error'
        }`
      );
    }
  }

  /**
   * Generate text embedding for semantic search
   */
  async generateEmbedding(text: string): Promise<number[]> {
    try {
      const response = await this.client.embeddings.create({
        model: config.openai.embeddingModel,
        input: text,
        encoding_format: 'float',
      });

      const embedding = response.data[0]?.embedding;
      if (!embedding) {
        throw new Error('No embedding returned from OpenAI');
      }

      return embedding;
    } catch (error) {
      console.error('OpenAI embedding error:', error);
      throw new Error(
        `Embedding generation failed: ${
          error instanceof Error ? error.message : 'Unknown error'
        }`
      );
    }
  }

  /**
   * Generate insights from conversation context using RAG
   */
  async generateInsights(
    query: string,
    contextMessages: Array<{ text: string; timestamp: number }>
  ): Promise<string> {
    const systemPrompt = `You are an AI assistant helping users analyze their conversation history.
Based on the relevant messages provided, answer the user's question accurately and concisely.

Guidelines:
- Be specific and reference actual content from the messages
- If the information isn't in the messages, say so
- Keep responses conversational and helpful
- For timeline questions, reference timestamps`;

    const contextText = contextMessages
      .map(
        (msg, idx) =>
          `[Message ${idx + 1}, ${new Date(msg.timestamp).toLocaleString()}]: ${
            msg.text
          }`
      )
      .join('\n\n');

    const userPrompt = `Context from conversation:
${contextText}

User question: ${query}`;

    const messages: OpenAIMessage[] = [
      {role: 'system', content: systemPrompt},
      {role: 'user', content: userPrompt},
    ];

    try {
      const response = await this.client.chat.completions.create({
        model: config.openai.chatModel,
        messages: messages,
        temperature: 0.7, // Higher for more natural insights
        max_tokens: 500,
      });

      const insight = response.choices[0]?.message?.content;
      if (!insight) {
        throw new Error('No response from OpenAI');
      }

      return insight;
    } catch (error) {
      console.error('OpenAI insights error:', error);
      throw new Error(
        `Insight generation failed: ${
          error instanceof Error ? error.message : 'Unknown error'
        }`
      );
    }
  }
}

// Singleton instance
let openAIServiceInstance: OpenAIService | null = null;

export function getOpenAIService(): OpenAIService {
  if (!openAIServiceInstance) {
    openAIServiceInstance = new OpenAIService();
  }
  return openAIServiceInstance;
}

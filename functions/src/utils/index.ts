/**
 * Utility functions for Cloud Functions
 */

import * as crypto from 'crypto';
import * as admin from 'firebase-admin';
import {RateLimitData} from '../types';
import {config} from '../config';

/**
 * Generate a cache key for translation
 */
export function generateTranslationCacheKey(
  text: string,
  targetLanguage: string
): string {
  const hash = crypto
    .createHash('sha256')
    .update(`${text}:${targetLanguage}`)
    .digest('hex');
  return hash.substring(0, 32); // Shorten for Firebase path
}

/**
 * Check and update rate limit for a user
 */
export async function checkRateLimit(
  userId: string,
  action: 'translation' | 'embedding' | 'insights'
): Promise<{ allowed: boolean; retryAfter?: number }> {
  const db = admin.database();
  const rateLimitRef = db.ref(`rateLimits/${userId}/${action}`);

  const limits = {
    translation: config.rateLimit.translationPerMinute,
    embedding: config.rateLimit.embeddingPerMinute,
    insights: config.rateLimit.insightsPerMinute,
  };

  const limit = limits[action];
  const now = Date.now();

  try {
    const snapshot = await rateLimitRef.get();
    const data: RateLimitData | null = snapshot.val();

    if (!data || now > data.resetTime) {
      // Reset or initialize
      await rateLimitRef.set({
        count: 1,
        resetTime: now + config.rateLimit.windowMs,
      });
      return {allowed: true};
    }

    if (data.count >= limit) {
      // Rate limit exceeded
      return {
        allowed: false,
        retryAfter: Math.ceil((data.resetTime - now) / 1000),
      };
    }

    // Increment count
    await rateLimitRef.update({
      count: data.count + 1,
    });

    return {allowed: true};
  } catch (error) {
    console.error('Rate limit check failed:', error);
    // Allow on error to not block users
    return {allowed: true};
  }
}

/**
 * Verify Firebase Auth token from request
 */
export async function verifyAuthToken(
  authHeader: string | undefined
): Promise<{ uid: string } | null> {
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return null;
  }

  const token = authHeader.split('Bearer ')[1];

  try {
    const decodedToken = await admin.auth().verifyIdToken(token);
    return {uid: decodedToken.uid};
  } catch (error) {
    console.error('Token verification failed:', error);
    return null;
  }
}

/**
 * Detect language from text using simple heuristics
 * (OpenAI will do the actual detection, this is for logging)
 */
export function detectLanguageHeuristic(text: string): string | null {
  // Chinese characters
  if (/[\u4e00-\u9fa5]/.test(text)) return 'zh';

  // Japanese characters (Hiragana/Katakana)
  if (/[\u3040-\u309f\u30a0-\u30ff]/.test(text)) return 'ja';

  // Korean characters
  if (/[\uac00-\ud7af]/.test(text)) return 'ko';

  // Arabic characters
  if (/[\u0600-\u06ff]/.test(text)) return 'ar';

  // Cyrillic (Russian)
  if (/[\u0400-\u04ff]/.test(text)) return 'ru';

  // Default to null (will let OpenAI detect)
  return null;
}

/**
 * Sanitize text for safe storage and processing
 */
export function sanitizeText(text: string): string {
  return text
    .trim()
    .replace(/[\x00-\x1F\x7F-\x9F]/g, '') // Remove control characters
    .substring(0, 10000); // Max length 10k chars
}

/**
 * Format error for client response
 */
export function formatError(error: unknown): {error: string} {
  if (error instanceof Error) {
    return {
      error: error.message,
    };
  }

  return {
    error: 'An unknown error occurred',
  };
}

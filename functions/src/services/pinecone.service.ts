/**
 * Pinecone Service
 * Handles vector storage and semantic search
 * Using Pinecone v1.1.x API
 */

import {Pinecone} from '@pinecone-database/pinecone';
import {config} from '../config';
import {PineconeVector} from '../types';

export class PineconeService {
  private client: Pinecone;
  private indexName: string;

  constructor() {
    // v1.1.x requires both apiKey and environment
    this.client = new Pinecone({
      apiKey: config.pinecone.apiKey,
      environment: config.pinecone.environment,
    });
    this.indexName = config.pinecone.indexName;
  }

  /**
   * Initialize or get the index
   */
  private async getIndex() {
    try {
      // List existing indexes (v1.1.x API)
      const indexList = await this.client.listIndexes();

      // Check if our index exists (indexes is array of objects with 'name' property)
      const indexExists = indexList?.some(
        (idx) => idx.name === this.indexName
      );

      if (!indexExists) {
        console.log(`Creating Pinecone index: ${this.indexName}`);

        // Create index (v1.1.x pod-based spec)
        await this.client.createIndex({
          name: this.indexName,
          dimension: config.pinecone.dimensions,
          metric: 'cosine',
        });

        // Wait for index to be ready
        console.log('Waiting for index to initialize...');
        await new Promise((resolve) => setTimeout(resolve, 60000)); // 60 seconds for pod-based
      }

      return this.client.index(this.indexName);
    } catch (error) {
      console.error('Error getting Pinecone index:', error);
      throw error;
    }
  }

  /**
   * Store a message embedding
   */
  async storeEmbedding(
    messageId: string,
    conversationId: string,
    text: string,
    embedding: number[],
    userId: string,
    timestamp: number
  ): Promise<string> {
    try {
      const index = await this.getIndex();

      const vectorId = `${conversationId}_${messageId}`;

      const vector: PineconeVector = {
        id: vectorId,
        values: embedding,
        metadata: {
          messageId,
          conversationId,
          text: text.substring(0, 1000), // Limit metadata size
          timestamp,
          userId,
        },
      };

      await index.upsert([vector]);

      return vectorId;
    } catch (error) {
      console.error('Error storing embedding in Pinecone:', error);
      throw new Error(
        `Failed to store embedding: ${
          error instanceof Error ? error.message : 'Unknown error'
        }`
      );
    }
  }

  /**
   * Search for similar messages using semantic search
   */
  async searchSimilar(
    conversationId: string,
    queryEmbedding: number[],
    topK: number = config.rag.defaultTopK
  ): Promise<
    Array<{
      messageId: string;
      text: string;
      score: number;
      timestamp: number;
    }>
  > {
    try {
      const index = await this.getIndex();

      const queryResponse = await index.query({
        vector: queryEmbedding,
        topK: topK * 2, // Get more to filter by conversation
        includeMetadata: true,
      });

      // Filter by conversation and threshold
      const results = queryResponse.matches
        .filter(
          (match) =>
            match.metadata?.conversationId === conversationId &&
            match.score !== undefined &&
            match.score >= config.rag.similarityThreshold
        )
        .slice(0, topK)
        .map((match) => ({
          messageId: match.metadata?.messageId as string,
          text: match.metadata?.text as string,
          score: match.score!,
          timestamp: match.metadata?.timestamp as number,
        }));

      return results;
    } catch (error) {
      console.error('Error searching Pinecone:', error);
      throw new Error(
        `Semantic search failed: ${
          error instanceof Error ? error.message : 'Unknown error'
        }`
      );
    }
  }

  /**
   * Delete embeddings for a conversation (cleanup)
   */
  async deleteConversationEmbeddings(
    conversationId: string
  ): Promise<void> {
    try {
      const index = await this.getIndex();

      // Query all vectors for this conversation
      const queryResponse = await index.query({
        vector: new Array(config.pinecone.dimensions).fill(0),
        topK: 10000,
        filter: {conversationId: {$eq: conversationId}},
        includeMetadata: false,
      });

      const vectorIds = queryResponse.matches.map((match) => match.id);

      if (vectorIds.length > 0) {
        await index.deleteMany(vectorIds);
      }
    } catch (error) {
      console.error('Error deleting conversation embeddings:', error);
      // Don't throw - this is cleanup, failures are acceptable
    }
  }
}

// Singleton instance
let pineconeServiceInstance: PineconeService | null = null;

export function getPineconeService(): PineconeService {
  if (!pineconeServiceInstance) {
    pineconeServiceInstance = new PineconeService();
  }
  return pineconeServiceInstance;
}

# AI Features & Deletion Policy

## Overview
This document outlines how to handle deleted messages when implementing AI features in the future.

## Core Principle
**"Deleted means deleted"** - If a user deletes a message, it should be excluded from all AI processing for that user.

## Implementation Guidelines

### 1. Message Filtering for AI Features

Always filter messages before AI processing:

```swift
// Example: AI Summary Feature
func generateConversationSummary(conversationId: String, userId: String) async throws -> String {
    let allMessages = try await messagingManager.loadOlderMessages(
        conversationId: conversationId,
        beforeTimestamp: Date(),
        limit: 1000
    )
    
    // Messages are already filtered by loadOlderMessages()
    // but be explicit for AI features
    let visibleMessages = allMessages.filter { !$0.isDeletedForUser(userId) }
    
    // Process only visible messages
    return try await aiService.summarize(visibleMessages)
}
```

### 2. Search & Indexing

```swift
// Example: Message Search
func searchMessages(query: String, userId: String) async throws -> [Message] {
    let results = try await searchIndex.search(query)
    
    // Filter out deleted messages from results
    return results.filter { !$0.isDeletedForUser(userId) }
}
```

### 3. Smart Replies / Suggestions

```swift
// Example: Smart Reply Suggestions
func generateSmartReplies(conversationId: String, userId: String) async throws -> [String] {
    // Only use last N visible messages for context
    let recentMessages = try await messagingManager.loadOlderMessages(
        conversationId: conversationId,
        beforeTimestamp: Date(),
        limit: 10
    )
    
    // Already filtered, but verify
    let visibleMessages = recentMessages.filter { !$0.isDeletedForUser(userId) }
    
    return try await aiService.generateReplies(context: visibleMessages)
}
```

### 4. Analytics & Insights

```swift
// Example: Conversation Analytics
func analyzeConversationSentiment(conversationId: String, userId: String) async throws -> SentimentScore {
    let messages = try await messagingManager.loadOlderMessages(
        conversationId: conversationId,
        beforeTimestamp: Date(),
        limit: 500
    )
    
    // Use only visible messages for analysis
    let visibleMessages = messages.filter { !$0.isDeletedForUser(userId) }
    
    return try await aiService.analyzeSentiment(visibleMessages)
}
```

## Privacy & Disclosure

### User-Facing Policy

Include in your Privacy Policy and Terms of Service:

```
AI Features & Deleted Content:

1. Deleted messages are excluded from AI features (summaries, search, suggestions)
2. Messages deleted by you are not used to generate AI content for you
3. Other participants may still see AI features based on messages you deleted 
   (until they also delete those messages)
4. AI-generated content (summaries, insights) is regenerated if source messages 
   are deleted
5. We do not use your messages to train AI models
6. AI processing happens in real-time; no message history is permanently stored 
   for AI purposes
```

### In-App Disclosure

When introducing AI features, show a one-time disclosure:

```
AI Features Notice:

Swift Send uses AI to enhance your messaging experience with features like:
- Smart summaries
- Message search
- Reply suggestions

Your deleted messages are never used for AI features. AI processing respects 
your deletion choices.

[Learn More] [Got It]
```

## Cache Management

### Invalidate AI-Generated Content

When messages are deleted, invalidate related AI content:

```swift
func deleteMessageForUser(conversationId: String, messageId: String) async throws {
    // Existing deletion logic
    try await messagingManager.deleteMessageForUser(
        conversationId: conversationId, 
        messageId: messageId
    )
    
    // Invalidate AI cache
    await aiCacheManager.invalidateSummary(conversationId: conversationId, userId: userId)
    await aiCacheManager.invalidateSearchIndex(messageId: messageId, userId: userId)
}
```

### Cache Expiration

Set reasonable TTLs for AI-generated content:

```swift
struct AICacheConfig {
    static let summaryTTL: TimeInterval = 3600 // 1 hour
    static let searchIndexTTL: TimeInterval = 86400 // 24 hours
    static let suggestionsTTL: TimeInterval = 300 // 5 minutes
}
```

## Model Training Policy

### Never Use User Messages for Training

**Important**: User messages should NEVER be used to train or fine-tune AI models.

```swift
// ❌ NEVER DO THIS
func trainModel() {
    let allMessages = getAllMessagesFromAllUsers() // NO!
    aiModel.train(on: allMessages) // NO!
}

// ✅ CORRECT APPROACH
// Use only:
// 1. Publicly available datasets
// 2. Synthetic data
// 3. Data from users who explicitly opted in with informed consent
```

### If You Must Collect Data

If you need to collect data for model improvement:

1. **Explicit Opt-In**: Separate, clear consent
2. **Anonymization**: Remove all PII before collection
3. **Aggregation**: Use only aggregated statistics
4. **Transparency**: Show exactly what data is collected
5. **Revocable**: Allow users to withdraw consent and delete data

```swift
struct DataCollectionConsent {
    var hasConsented: Bool = false
    var consentDate: Date?
    var dataTypes: [DataType] = []
    var canRevoke: Bool = true
}
```

## AI Feature Examples

### 1. Conversation Summary

```swift
class ConversationSummaryService {
    func generateSummary(conversationId: String, userId: String) async throws -> Summary {
        // Load visible messages
        let messages = try await messagingManager.loadOlderMessages(
            conversationId: conversationId,
            beforeTimestamp: Date(),
            limit: 100
        )
        
        // Double-check filtering
        let visibleMessages = messages.filter { !$0.isDeletedForUser(userId) }
        
        guard !visibleMessages.isEmpty else {
            return Summary(text: "No messages to summarize", isEmpty: true)
        }
        
        // Generate summary
        let summary = try await aiService.summarize(visibleMessages)
        
        // Cache with TTL
        await cacheManager.cacheSummary(
            summary, 
            conversationId: conversationId,
            userId: userId,
            ttl: AICacheConfig.summaryTTL
        )
        
        return summary
    }
}
```

### 2. Smart Search

```swift
class MessageSearchService {
    func search(query: String, userId: String) async throws -> [SearchResult] {
        // Search across all conversations user is in
        let conversations = try await getConversationsForUser(userId)
        
        var results: [SearchResult] = []
        
        for conversation in conversations {
            let messages = try await messagingManager.loadOlderMessages(
                conversationId: conversation.id,
                beforeTimestamp: Date(),
                limit: 1000
            )
            
            // Filter deleted messages
            let visibleMessages = messages.filter { !$0.isDeletedForUser(userId) }
            
            // Perform semantic search
            let matches = try await aiService.semanticSearch(
                query: query,
                in: visibleMessages
            )
            
            results.append(contentsOf: matches)
        }
        
        return results.sorted { $0.relevance > $1.relevance }
    }
}
```

### 3. Action Item Extraction

```swift
class ActionItemService {
    func extractActionItems(conversationId: String, userId: String) async throws -> [ActionItem] {
        // Load recent visible messages
        let messages = try await messagingManager.loadOlderMessages(
            conversationId: conversationId,
            beforeTimestamp: Date(),
            limit: 50
        )
        
        let visibleMessages = messages.filter { !$0.isDeletedForUser(userId) }
        
        // Extract action items using AI
        let actionItems = try await aiService.extractActionItems(from: visibleMessages)
        
        // Link back to source messages (that still exist)
        return actionItems.filter { actionItem in
            // Ensure source message wasn't deleted
            !actionItem.sourceMessage.isDeletedForUser(userId)
        }
    }
}
```

## Testing AI Features with Deletion

### Test Cases

1. **Delete Before AI Processing**
   - Delete message
   - Generate summary
   - Verify deleted message not in summary

2. **Delete After AI Processing**
   - Generate summary
   - Delete message
   - Regenerate summary
   - Verify deleted message not in new summary

3. **Partial Deletion**
   - User A deletes message
   - User B generates summary
   - Verify User A doesn't see message in their summary
   - Verify User B sees message in their summary

4. **Search Exclusion**
   - Delete message containing keyword
   - Search for keyword
   - Verify deleted message not in results

5. **Cache Invalidation**
   - Generate AI content
   - Delete source message
   - Verify cache invalidated
   - Verify regenerated content excludes deleted message

## Performance Considerations

### Filtering Strategy

```swift
// ✅ GOOD: Filter at database level when possible
func getVisibleMessages(conversationId: String, userId: String) async throws -> [Message] {
    // Firestore query with compound filter
    let messages = try await db.collection("conversations")
        .document(conversationId)
        .collection("messages")
        .whereField("deletedFor", notContains: userId) // If Firestore supports
        .getDocuments()
    
    return messages
}

// ✅ ACCEPTABLE: Filter in application layer (current implementation)
func getVisibleMessages(conversationId: String, userId: String) async throws -> [Message] {
    let messages = try await loadAllMessages(conversationId)
    return messages.filter { !$0.isDeletedForUser(userId) }
}

// ❌ BAD: Load everything then filter multiple times
func getVisibleMessages(conversationId: String, userId: String) async throws -> [Message] {
    let messages = try await loadAllMessages(conversationId)
    var filtered = messages
    for message in messages {
        if message.isDeletedForUser(userId) {
            filtered.removeAll { $0.id == message.id }
        }
    }
    return filtered
}
```

### Caching Strategy

```swift
class AIFeatureCache {
    // Cache key includes userId to ensure per-user filtering
    func cacheKey(feature: String, conversationId: String, userId: String) -> String {
        return "\(feature)_\(conversationId)_\(userId)"
    }
    
    func invalidateForUser(userId: String, conversationId: String) async {
        let keys = [
            cacheKey(feature: "summary", conversationId: conversationId, userId: userId),
            cacheKey(feature: "search", conversationId: conversationId, userId: userId),
            cacheKey(feature: "suggestions", conversationId: conversationId, userId: userId)
        ]
        
        for key in keys {
            await cache.remove(key)
        }
    }
}
```

## Summary

When implementing AI features:

1. ✅ Always filter deleted messages before AI processing
2. ✅ Respect per-user deletion (User A's deletion doesn't affect User B)
3. ✅ Invalidate AI cache when messages are deleted
4. ✅ Be transparent about AI usage in privacy policy
5. ✅ Never use user messages for model training without explicit consent
6. ✅ Test deletion scenarios thoroughly
7. ✅ Set reasonable cache TTLs
8. ✅ Filter at the earliest possible point (database if possible)

The deletion system is already built to support this - just call the existing filtering methods before AI processing!


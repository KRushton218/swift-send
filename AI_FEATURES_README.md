# Swift-Send AI Features

Comprehensive guide for the RAG and AI-powered translation features in swift-send.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Setup Instructions](#setup-instructions)
- [Usage Guide](#usage-guide)
- [API Reference](#api-reference)
- [Cost Estimates](#cost-estimates)
- [Troubleshooting](#troubleshooting)

## Overview

Swift-send now includes powerful AI features powered by OpenAI GPT-4 and Pinecone vector database:

1. **Inline Translation**: Translate messages to your preferred language with manual "Translate" buttons
2. **Language Detection**: Automatic language detection with language badges
3. **RAG-Powered Insights**: Ask questions about conversation history using semantic search
4. **Translation Caching**: Reduce costs by caching translations for 30 days

All API keys are stored securely in Firebase Cloud Functions - never in the iOS app.

## Features

### 1. Message Translation

- **Manual Translation**: Tap "Translate" button on any message
- **Inline Display**: Translations appear below the original text in the same bubble
- **Language Badges**: Shows detected language (e.g., "Chinese", "Spanish")
- **Clear Translation**: Tap "Show original" to hide translation
- **Smart Caching**: Identical translations are cached to save costs

### 2. RAG Insights

- **Semantic Search**: Find relevant messages based on meaning, not just keywords
- **Conversation Analysis**: Ask questions like "What did we decide about the meeting?"
- **Context-Aware Responses**: AI provides answers based on actual conversation history
- **Source Citations**: Shows which messages the answer is based on

### 3. User Preferences

- **Preferred Language**: Set your default translation language
- **Language Badges**: Toggle language detection badges
- **Persistent Settings**: Preferences saved to Firebase RTDB

## Architecture

### Backend (Firebase Cloud Functions)

```
functions/
├── src/
│   ├── index.ts                 # Cloud Function exports
│   ├── config/index.ts          # Configuration (API keys via env vars)
│   ├── types/index.ts           # TypeScript interfaces
│   ├── services/
│   │   ├── openai.service.ts    # OpenAI API wrapper
│   │   └── pinecone.service.ts  # Pinecone vector DB wrapper
│   └── utils/index.ts           # Helpers (caching, rate limiting, auth)
└── package.json
```

**Cloud Functions:**
- `translateMessage` - Language detection + translation with caching
- `generateEmbedding` - Create vector embeddings for messages
- `semanticSearch` - Search similar messages
- `generateInsights` - RAG-powered conversation analysis

### iOS App

```
swift-send/
├── Models/
│   └── Models.swift                    # Updated Message + UserPreferences models
├── Managers/
│   ├── AIServiceManager.swift          # Cloud Functions client
│   ├── TranslationManager.swift        # Translation UI logic
│   └── RealtimeManager.swift           # Added user preferences methods
├── Views/
│   ├── Components/
│   │   └── MessageBubble.swift         # Updated with translation UI
│   ├── ChatView.swift                  # Added insights button
│   ├── InsightsView.swift              # RAG insights UI
│   ├── ProfileView.swift               # Added preferences link
│   └── LanguagePreferencesView.swift   # Language settings
```

### Data Flow

```
User taps "Translate"
    ↓
MessageBubble → TranslationManager
    ↓
AIServiceManager (with Firebase Auth token)
    ↓
Cloud Function: translateMessage
    ↓
Check Translation Cache (RTDB)
    ├─ Cache Hit → Return cached translation
    └─ Cache Miss → OpenAI API → Cache result → Return
    ↓
Update Message in RTDB
    ↓
Real-time observer updates UI
```

## Setup Instructions

### Prerequisites

- Firebase project with Realtime Database
- OpenAI API account ([https://platform.openai.com](https://platform.openai.com))
- Pinecone account ([https://www.pinecone.io](https://www.pinecone.io))
- Node.js 18+ installed
- Firebase CLI installed (`npm install -g firebase-tools`)

### Step 1: Get API Keys

#### OpenAI API Key

1. Go to [https://platform.openai.com/api-keys](https://platform.openai.com/api-keys)
2. Create a new API key
3. Copy the key (starts with `sk-...`)
4. Add billing information at [https://platform.openai.com/account/billing](https://platform.openai.com/account/billing)

#### Pinecone API Key

1. Sign up at [https://www.pinecone.io](https://www.pinecone.io)
2. Create a new project (choose Starter/Free tier)
3. Go to API Keys section
4. Copy your API key
5. Note your environment (e.g., `us-east-1-aws` or `gcp-starter`)

### Step 2: Configure Cloud Functions

```bash
cd /path/to/swift-send

# Log in to Firebase
firebase login

# Set API keys in Firebase Functions config
firebase functions:config:set openai.api_key="YOUR_OPENAI_API_KEY"
firebase functions:config:set pinecone.api_key="YOUR_PINECONE_API_KEY"
firebase functions:config:set pinecone.environment="YOUR_PINECONE_ENVIRONMENT"

# For local development, download config
cd functions
firebase functions:config:get > .runtimeconfig.json
```

### Step 3: Deploy Cloud Functions

```bash
# Install dependencies
cd functions
npm install

# Build TypeScript
npm run build

# Deploy to Firebase
firebase deploy --only functions

# You should see URLs like:
# - translateMessage: https://us-central1-YOUR_PROJECT.cloudfunctions.net/translateMessage
# - generateEmbedding: https://us-central1-YOUR_PROJECT.cloudfunctions.net/generateEmbedding
# - semanticSearch: https://us-central1-YOUR_PROJECT.cloudfunctions.net/semanticSearch
# - generateInsights: https://us-central1-YOUR_PROJECT.cloudfunctions.net/generateInsights
```

### Step 4: Update iOS App Configuration

1. Open `swift-send/Managers/AIServiceManager.swift`
2. Find the line: `private let functionsBaseURL = "https://us-central1-<YOUR_PROJECT_ID>.cloudfunctions.net"`
3. Replace `<YOUR_PROJECT_ID>` with your actual Firebase project ID
4. You can find your project ID in `.firebaserc` or Firebase Console

Example:
```swift
// If your project ID is "swift-send-12345"
private let functionsBaseURL = "https://us-central1-swift-send-12345.cloudfunctions.net"
```

### Step 5: Build and Run iOS App

```bash
# Open Xcode
open swift-send.xcodeproj

# Build and run (Cmd+R)
# Sign in to the app
# Start a conversation and test translation!
```

## Usage Guide

### For End Users

#### Translating Messages

1. Open any conversation
2. Tap the "Translate" button under a message from another user
3. The translation appears below the original text
4. Tap "Show original" to hide the translation

#### Changing Preferred Language

1. Tap your profile icon
2. Go to "Language & Translation"
3. Select your preferred language from the dropdown
4. Changes save automatically

#### Getting Conversation Insights

1. In any conversation, tap the lightbulb icon (💡) in the top right
2. Type a question about the conversation (e.g., "When did we discuss the project?")
3. Tap "Get Insight"
4. The AI will analyze your conversation history and provide an answer

**Note**: Insights require messages to have embeddings. Messages will automatically generate embeddings when you first use the insights feature.

### For Developers

#### Manually Trigger Embedding Generation

```swift
// In ChatViewModel or similar
let translationManager = TranslationManager.shared

Task {
    await translationManager.generateEmbeddingsForMessages(viewModel.messages)
}
```

#### Access Translation Programmatically

```swift
let aiService = AIServiceManager.shared

do {
    let response = try await aiService.translateMessage(
        messageId: "msg123",
        text: "Hello world",
        targetLanguage: "es"
    )
    print("Translation: \(response.translatedText)")
    print("Detected: \(response.detectedLanguage)")
} catch {
    print("Error: \(error)")
}
```

## API Reference

### Cloud Functions

#### `translateMessage`

Translates text with automatic language detection.

**Request:**
```json
{
  "messageId": "msg123",
  "text": "Hello, how are you?",
  "targetLanguage": "es",
  "userId": "user123"
}
```

**Response:**
```json
{
  "translatedText": "Hola, ¿cómo estás?",
  "detectedLanguage": "en",
  "targetLanguage": "es",
  "fromCache": false
}
```

**Rate Limit:** 10 requests/minute per user

#### `generateEmbedding`

Creates a vector embedding and stores it in Pinecone.

**Request:**
```json
{
  "messageId": "msg123",
  "conversationId": "conv456",
  "text": "Let's meet tomorrow at 3pm",
  "userId": "user123"
}
```

**Response:**
```json
{
  "vectorId": "conv456_msg123",
  "dimensions": 1536,
  "success": true
}
```

**Rate Limit:** 20 requests/minute per user

#### `semanticSearch`

Searches for similar messages using vector similarity.

**Request:**
```json
{
  "conversationId": "conv456",
  "query": "meeting time",
  "topK": 5,
  "userId": "user123"
}
```

**Response:**
```json
{
  "results": [
    {
      "messageId": "msg123",
      "text": "Let's meet tomorrow at 3pm",
      "score": 0.92,
      "timestamp": 1698765432000
    }
  ]
}
```

#### `generateInsights`

Generates AI insights using RAG over conversation history.

**Request:**
```json
{
  "conversationId": "conv456",
  "query": "What time are we meeting?",
  "userId": "user123"
}
```

**Response:**
```json
{
  "insight": "Based on your conversation, you agreed to meet tomorrow at 3pm.",
  "relevantMessages": [
    {
      "messageId": "msg123",
      "text": "Let's meet tomorrow at 3pm"
    }
  ]
}
```

**Rate Limit:** 5 requests/minute per user

### iOS Managers

#### `AIServiceManager`

```swift
class AIServiceManager {
    static let shared: AIServiceManager

    func translateMessage(messageId: String, text: String, targetLanguage: String) async throws -> TranslateResponse

    func generateEmbedding(messageId: String, conversationId: String, text: String) async throws -> EmbeddingResponse

    func semanticSearch(conversationId: String, query: String, topK: Int) async throws -> SemanticSearchResponse

    func generateInsights(conversationId: String, query: String) async throws -> InsightsResponse
}
```

#### `TranslationManager`

```swift
class TranslationManager: ObservableObject {
    static let shared: TranslationManager

    @Published var isTranslating: [String: Bool]
    @Published var translationErrors: [String: String]

    let supportedLanguages: [String: String]

    func translateMessage(_ message: Message, to targetLanguage: String) async throws
    func clearTranslation(conversationId: String, messageId: String) async throws
    func generateEmbeddingsForMessages(_ messages: [Message]) async
}
```

## Cost Estimates

Based on OpenAI and Pinecone pricing (as of 2024):

### Translation

- **Model**: `gpt-4o-mini`
- **Cost**: ~$0.15 per 1M input tokens, ~$0.60 per 1M output tokens
- **Average message**: ~50 tokens input, ~50 tokens output
- **Cost per translation**: ~$0.00005 ($0.000075 + $0.00003)
- **With 80% cache hit rate**: ~$0.00001 per message

**Example**: 1000 messages/day = ~$0.01/day = **~$3/month**

### Embeddings

- **Model**: `text-embedding-3-small`
- **Cost**: ~$0.02 per 1M tokens
- **Average message**: ~50 tokens
- **Cost per embedding**: ~$0.000001

**Example**: 1000 messages/day = ~$0.001/day = **~$0.30/month**

### Semantic Search (Pinecone)

- **Free tier**: 1M vectors, 100K queries/month
- **Typical usage**: <<100K queries/month
- **Cost**: **$0/month** (free tier sufficient)

### RAG Insights

- **Search**: Included in Pinecone free tier
- **GPT-4 generation**: ~$0.0001 per insight
- **Typical usage**: 100 insights/month
- **Cost**: **~$0.01/month**

### Total Monthly Cost (Estimate)

For a user sending 1000 messages/month:
- Translation: ~$3
- Embeddings: ~$0.30
- Insights: ~$0.01
- **Total: ~$3.31/month**

**Cost per active user per month: ~$3-5**

## Troubleshooting

### "Unauthorized" Errors

**Cause**: Firebase Auth token not being sent or invalid

**Fix**:
1. Make sure user is signed in
2. Check that `Authorization` header is being sent
3. Verify Firebase Auth is configured correctly in Cloud Functions

### "Rate limit exceeded"

**Cause**: User exceeded rate limits (10 translations/minute, 5 insights/minute)

**Fix**:
- Wait for rate limit window to reset (1 minute)
- Implement exponential backoff in client
- Increase rate limits in `functions/src/config/index.ts` if needed

### Translation Cache Not Working

**Cause**: Cache key generation issue or RTDB rules

**Fix**:
1. Check RTDB rules allow read/write to `translationCache/*`
2. Verify cache TTL hasn't expired (default 30 days)
3. Check Cloud Function logs: `firebase functions:log --only translateMessage`

### Pinecone Index Not Found

**Cause**: Index hasn't been created yet

**Fix**:
- The index is created automatically on first use
- Wait 5-10 seconds after first embedding request
- Check Pinecone dashboard to verify index exists
- Ensure index name matches: `swift-send-messages`

### Translation Appears for Current User's Messages

**Cause**: UI bug - translations should only show for other users' messages

**Fix**:
- Check `MessageBubble.swift` line 68: `if !isFromCurrentUser`
- Verify `isFromCurrentUser` is calculated correctly in `ChatView`

### Insights Return "No relevant messages"

**Cause**: Messages don't have embeddings yet

**Fix**:
1. Generate embeddings for existing messages:
   ```swift
   await translationManager.generateEmbeddingsForMessages(messages)
   ```
2. Wait a few seconds for embeddings to be indexed
3. Try asking the question again

### iOS App Can't Reach Cloud Functions

**Cause**: Incorrect `functionsBaseURL` in `AIServiceManager.swift`

**Fix**:
1. Open `swift-send/Managers/AIServiceManager.swift`
2. Verify project ID matches your Firebase project
3. Test URL in browser: `https://us-central1-YOUR_PROJECT.cloudfunctions.net/translateMessage`
4. Should return: `{"error":"Method not allowed"}` (expected for GET request)

## Security Best Practices

### API Keys

✅ **DO:**
- Store API keys in Firebase Functions config
- Use environment variables for local development
- Never commit `.runtimeconfig.json` to git

❌ **DON'T:**
- Hardcode API keys in source code
- Store API keys in iOS app
- Share API keys in documentation or commits

### Rate Limiting

The implementation includes built-in rate limiting:
- Translation: 10/minute
- Embedding: 20/minute
- Insights: 5/minute

Adjust in `functions/src/config/index.ts` if needed.

### Authentication

All Cloud Functions verify Firebase Auth tokens:
- Requires valid `Authorization: Bearer <token>` header
- Token must be from authenticated user
- Tokens expire after 1 hour (auto-refreshed by Firebase SDK)

## Future Enhancements

Potential features to add:

1. **Auto-translate mode**: Automatically translate all incoming messages
2. **Batch translation**: Translate multiple messages at once
3. **Custom languages**: Add support for more languages
4. **Translation history**: View all past translations
5. **Offline mode**: Cache translations locally for offline access
6. **Analytics**: Track translation usage and costs
7. **Language preferences per conversation**: Different languages for different chats

## Support

For issues or questions:
- Check [Troubleshooting](#troubleshooting) section
- Review Cloud Functions logs: `firebase functions:log`
- Check Firebase Console for errors
- Verify API keys are set correctly

## License

This implementation is part of the swift-send project.

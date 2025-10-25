# Swift-Send Cloud Functions

Firebase Cloud Functions for AI-powered translation and RAG features in swift-send.

## Setup

### 1. Install Dependencies

```bash
cd functions
npm install
```

### 2. Set API Keys

Set your API keys using Firebase Functions config:

```bash
# Set OpenAI API key
firebase functions:config:set openai.api_key="YOUR_OPENAI_API_KEY"

# Set Pinecone API key
firebase functions:config:set pinecone.api_key="YOUR_PINECONE_API_KEY"

# Set Pinecone environment (e.g., us-east-1-aws)
firebase functions:config:set pinecone.environment="YOUR_PINECONE_ENVIRONMENT"
```

### 3. Local Development

For local testing with the Firebase Emulator:

```bash
# Download the config to .runtimeconfig.json
firebase functions:config:get > .runtimeconfig.json

# Start emulators
npm run serve
```

## Available Functions

### `translateMessage`

Translates a message with automatic language detection and caching.

**Endpoint**: `POST /translateMessage`

**Request**:
```json
{
  "messageId": "msg123",
  "text": "Hello, how are you?",
  "targetLanguage": "es",
  "userId": "user123"
}
```

**Response**:
```json
{
  "translatedText": "Hola, ¿cómo estás?",
  "detectedLanguage": "en",
  "targetLanguage": "es",
  "fromCache": false
}
```

### `generateEmbedding`

Generates a vector embedding for a message and stores it in Pinecone.

**Endpoint**: `POST /generateEmbedding`

**Request**:
```json
{
  "messageId": "msg123",
  "conversationId": "conv456",
  "text": "Hello, how are you?",
  "userId": "user123"
}
```

**Response**:
```json
{
  "vectorId": "conv456_msg123",
  "dimensions": 1536,
  "success": true
}
```

### `semanticSearch`

Performs semantic search over conversation messages.

**Endpoint**: `POST /semanticSearch`

**Request**:
```json
{
  "conversationId": "conv456",
  "query": "When did we discuss the project?",
  "topK": 5,
  "userId": "user123"
}
```

**Response**:
```json
{
  "results": [
    {
      "messageId": "msg789",
      "text": "Let's meet tomorrow to discuss the project",
      "score": 0.89,
      "timestamp": 1698765432000
    }
  ]
}
```

### `generateInsights`

Generates AI insights from conversation using RAG.

**Endpoint**: `POST /generateInsights`

**Request**:
```json
{
  "conversationId": "conv456",
  "query": "What did we decide about the meeting time?",
  "userId": "user123"
}
```

**Response**:
```json
{
  "insight": "Based on the conversation, you decided to meet at 3 PM tomorrow.",
  "relevantMessages": [
    {
      "messageId": "msg789",
      "text": "Let's meet at 3 PM tomorrow"
    }
  ]
}
```

## Rate Limits

- Translation: 10 requests/minute per user
- Embedding: 20 requests/minute per user
- Insights: 5 requests/minute per user

## Security

- All functions require Firebase Authentication
- Auth token must be sent in `Authorization` header as `Bearer <token>`
- API keys are stored securely in Firebase Functions config (never in code)
- Rate limiting prevents abuse

## Cost Optimization

- **Translation caching**: Identical translations are cached for 30 days
- **Rate limiting**: Prevents excessive API usage
- **Efficient models**: Uses `gpt-4o-mini` and `text-embedding-3-small` for cost-effectiveness

## Deployment

```bash
# Build TypeScript
npm run build

# Deploy all functions
firebase deploy --only functions

# Deploy specific function
firebase deploy --only functions:translateMessage
```

## Monitoring

```bash
# View logs
npm run logs

# Or for specific function
firebase functions:log --only translateMessage
```

## Troubleshooting

### "OPENAI_API_KEY not set"

Make sure you've set the config:
```bash
firebase functions:config:set openai.api_key="your-key"
firebase deploy --only functions
```

### "Pinecone index not found"

The index will be created automatically on first use. Wait a few seconds after the first embedding request.

### Rate limit errors

Rate limits reset after 1 minute. Implement exponential backoff in your client.

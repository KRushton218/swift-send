# Backend Changes Needed for Cultural Context & Slang Features

## Overview
The frontend is now ready to receive and display cultural context and slang explanations. The Cloud Function `translateMessage` needs to be updated to return these additional fields.

## ⚡ IMPORTANT: Always Return Extras
**The backend should ALWAYS analyze and return cultural context/slang data for EVERY translation.** The frontend now has a user preference toggle (`showTranslationExtras`) that controls whether the sparkles button (✨) is shown, but the data should always be present so users can enable it at any time without re-translating.

## Required Changes to `translateMessage` Cloud Function

### Updated Response Schema

The function should return:

```typescript
{
  translatedText: string,
  detectedLanguage: string,
  targetLanguage: string,
  fromCache: boolean,
  culturalNotes?: string[],        // NEW - Optional array of cultural context
  slangExplanations?: Array<{      // NEW - Optional array of slang/idiom explanations
    term: string,                  // The slang term or idiom
    explanation: string,           // What it means
    literal?: string               // Optional literal translation
  }>
}
```

### Implementation Suggestions

#### 1. Enhance AI Prompt
When calling the translation AI (e.g., Google Translate API + GPT), add instructions to:

```
"Translate the following text to {targetLanguage}. Additionally:
1. Identify any cultural references, idioms, or context-specific meanings
2. Detect slang or informal language that might not translate directly
3. Return structured data with:
   - The translation
   - Cultural notes (array of strings explaining cultural context)
   - Slang explanations (array with term, explanation, and literal translation)
"
```

#### 2. Example Responses

**Example 1: Message with idiom**
```json
{
  "translatedText": "¡Mucha suerte en tu entrevista de mañana!",
  "detectedLanguage": "en",
  "targetLanguage": "es",
  "fromCache": false,
  "culturalNotes": [
    "\"Break a leg\" is an English idiom meaning \"good luck,\" especially in performance contexts",
    "Saying \"good luck\" directly is considered bad luck in theatrical tradition"
  ],
  "slangExplanations": [
    {
      "term": "Break a leg",
      "explanation": "Theatrical expression wishing good luck",
      "literal": "Rómpete una pierna"
    }
  ]
}
```

**Example 2: Message with slang**
```json
{
  "translatedText": "Ce film était génial",
  "detectedLanguage": "en",
  "targetLanguage": "fr",
  "fromCache": false,
  "slangExplanations": [
    {
      "term": "lit",
      "explanation": "Modern slang meaning \"amazing\" or \"exciting\"",
      "literal": "allumé"
    }
  ]
}
```

**Example 3: Regular message (no extras)**
```json
{
  "translatedText": "Bonjour, comment allez-vous?",
  "detectedLanguage": "en",
  "targetLanguage": "fr",
  "fromCache": true
}
```

### 3. Caching Considerations

- Cache the full response including `culturalNotes` and `slangExplanations`
- Cache key should include language pair and message content
- Consider if cultural context should always be generated or only on-demand

### 4. Rate Limiting

- Generating cultural context/slang explanations may require additional AI calls
- Consider:
  - Only generating extras for messages under N words
  - Offering "basic" vs "enhanced" translation modes
  - Implementing usage quotas per user

## Testing

### Test Cases Needed

1. **Idiom detection:**
   - "Break a leg"
   - "It's raining cats and dogs"
   - "Piece of cake"

2. **Slang detection:**
   - "That's lit"
   - "No cap"
   - "FOMO"

3. **Cultural references:**
   - Holiday mentions (Thanksgiving, Diwali, etc.)
   - Region-specific terms
   - Pop culture references

4. **Regular messages:**
   - "Hello, how are you?"
   - "The meeting is at 3pm"
   - Should return no extras (undefined or empty arrays)

## Frontend Behavior

✅ **Already Implemented:**
- Sparkles icon (✨) appears next to translations with extras (when user preference is enabled)
- User preference toggle in Language & Translation settings
  - "Show cultural context & slang" (default: ON)
  - Controls visibility of sparkles button, NOT whether data is generated
- Tapping sparkles opens `TranslationDetailsSheet` with formatted display
- Works with auto-translate feature
- Persists extras to RTDB at `user_translations/{userId}/{messageId}/`

**User Flow:**
1. Backend always returns cultural notes/slang for every translation
2. If user has "Show cultural context & slang" enabled → sparkles appears
3. If user has it disabled → no sparkles, but data is still in memory/RTDB
4. User can toggle preference on/off without re-translating messages

## Questions to Answer

1. ~~Should cultural context always be generated, or only when explicitly requested?~~ **ANSWERED: Always generate**
2. What's the cost/latency impact of adding these features?
3. Should we limit extras to certain message lengths or types?
4. ~~Do we need a user preference to enable/disable extras generation?~~ **ANSWERED: Yes, preference controls UI visibility, not generation**

---

**Status:** Frontend ready ✅ | Backend pending ⏳

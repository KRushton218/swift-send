# Backend Specification: Formality Adjuster

## Overview
The formality adjuster allows users to analyze and adjust the formality level of their message before sending. The frontend is complete and ready to receive formality analysis and variations.

---

## Required Cloud Function: `analyzeFormalityAndGenerate`

### Request Schema

```typescript
{
  text: string,      // The message text to analyze
  userId: string     // User ID for authentication
}
```

### Response Schema

```typescript
{
  originalText: string,

  analysis: {
    currentLevel: "casual" | "neutral" | "formal" | "business",
    score: number,  // 0-10 formality scale (0=very casual, 10=very formal)

    factors: {
      conjugations: string,      // Analysis of verb forms, contractions
      phrasing: string,          // Analysis of sentence structure
      figuresOfSpeech: string,   // Analysis of idioms, slang, metaphors
      verbChoice: string,        // Analysis of verb selection
      tone: string               // Overall tone assessment
    }
  },

  variations: {
    casual: string,      // Very informal, friendly (score ~2)
    neutral: string,     // Balanced, professional but approachable (score ~5)
    formal: string,      // Professional, polite (score ~7)
    business: string     // Very formal, corporate (score ~9)
  }
}
```

---

## Example Requests/Responses

### Example 1: Casual Message

**Request:**
```json
{
  "text": "Hey! Can you send me that doc? Thanks!",
  "userId": "user123"
}
```

**Response:**
```json
{
  "originalText": "Hey! Can you send me that doc? Thanks!",
  "analysis": {
    "currentLevel": "casual",
    "score": 2,
    "factors": {
      "conjugations": "Informal greeting 'Hey' with exclamation marks",
      "phrasing": "Direct question without please/softeners",
      "figuresOfSpeech": "Casual abbreviation 'doc' instead of 'document'",
      "verbChoice": "Simple, everyday verbs (send, can)",
      "tone": "Very friendly and relaxed"
    }
  },
  "variations": {
    "casual": "Hey! Can you send me that doc? Thanks!",
    "neutral": "Hi! Could you send me that document? Thanks!",
    "formal": "Hello. Would you be able to send me that document? Thank you.",
    "business": "Good morning. I would appreciate it if you could send me the document at your earliest convenience. Thank you."
  }
}
```

### Example 2: Formal Message

**Request:**
```json
{
  "text": "I would like to request the quarterly report.",
  "userId": "user123"
}
```

**Response:**
```json
{
  "originalText": "I would like to request the quarterly report.",
  "analysis": {
    "currentLevel": "formal",
    "score": 7,
    "factors": {
      "conjugations": "Formal auxiliary 'would like to' instead of 'want'",
      "phrasing": "Polite request structure with softeners",
      "figuresOfSpeech": "No colloquialisms or informal expressions",
      "verbChoice": "Formal verb choice (request, report)",
      "tone": "Professional and courteous"
    }
  },
  "variations": {
    "casual": "Can I get the quarterly report?",
    "neutral": "Could I get the quarterly report?",
    "formal": "I would like to request the quarterly report.",
    "business": "I am writing to formally request the quarterly report for review."
  }
}
```

### Example 3: Short Message

**Request:**
```json
{
  "text": "Thanks!",
  "userId": "user123"
}
```

**Response:**
```json
{
  "originalText": "Thanks!",
  "analysis": {
    "currentLevel": "casual",
    "score": 3,
    "factors": {
      "conjugations": "Contraction of 'thank you'",
      "phrasing": "Single exclamatory word",
      "figuresOfSpeech": "None present",
      "verbChoice": "Informal gratitude expression",
      "tone": "Friendly and quick"
    }
  },
  "variations": {
    "casual": "Thanks!",
    "neutral": "Thank you!",
    "formal": "Thank you.",
    "business": "Thank you very much for your assistance."
  }
}
```

---

## Implementation Guidelines

### Formality Score Mapping (0-10 scale):

- **0-2:** Very casual (slang, emojis, abbreviations)
- **3-4:** Casual (contractions, friendly tone)
- **5-6:** Neutral (balanced, professional but approachable)
- **7-8:** Formal (polite, professional, no contractions)
- **9-10:** Business (very formal, corporate language)

### Factor Analysis Guidelines:

**Conjugations:**
- Look for contractions (don't, can't, I'm)
- Auxiliary verb usage (would like to, could you, may I)
- Verb tense formality (gonna vs going to)

**Phrasing:**
- Question structure (Can you vs Would you be able to)
- Use of softeners (perhaps, maybe, possibly)
- Sentence complexity and length

**Figures of Speech:**
- Idioms and slang
- Colloquialisms
- Abbreviations (doc, info, ASAP)

**Verb Choice:**
- Simple vs complex verbs (get vs obtain)
- Everyday vs professional vocabulary
- Action directness

**Tone:**
- Overall feeling (friendly, professional, corporate)
- Use of emphasis (exclamation marks, all caps)
- Emotional markers

### Generation Guidelines:

**Casual Variation:**
- Use contractions freely
- Include friendly markers (Hey, Thanks!)
- Allow abbreviations
- Keep sentences short and direct

**Neutral Variation:**
- Minimal contractions
- Polite but not overly formal
- Clear and concise
- Balanced tone

**Formal Variation:**
- No contractions
- Polite request structures
- Complete sentences
- Professional vocabulary

**Business Variation:**
- Very formal language
- Complex sentence structures
- Corporate vocabulary
- Extremely polite and deferential

---

## Frontend Behavior (Already Implemented)

✅ **User Flow:**
1. User types message in text field
2. Taps formality adjuster button (slider icon)
3. Sheet opens with loading state
4. Analysis and variations displayed
5. User selects desired level
6. Taps "Use [Level]" → text updates
7. User can still edit before sending

✅ **UI Components:**
- Formality analysis breakdown with 5 factors
- 4 selectable formality level cards with radio buttons
- Original text always preserved
- "Cancel" discards changes
- "Use [Level]" applies selection

✅ **Edge Cases:**
- Empty messages: button disabled
- Loading state: shows spinner, button disabled
- Error handling: logs to console (TODO: show alert)

---

## Testing

### Test Cases:

1. **Very Casual Message:**
   - Input: "yo whats up?"
   - Should detect: informal greeting, abbreviation, no punctuation

2. **Business Email:**
   - Input: "I am writing to inform you of the policy update."
   - Should detect: formal structure, professional vocabulary

3. **Mixed Formality:**
   - Input: "Hi! I would like to request the docs ASAP"
   - Should detect: mix of casual (Hi!, docs) and formal (would like to)

4. **Questions:**
   - Input: "Can you help me?"
   - Test all variations maintain question format

5. **Multi-sentence:**
   - Input: "Hey! How are you? Can we meet tomorrow?"
   - Ensure all sentences adjust consistently

6. **Very Short:**
   - Input: "Yes"
   - Should still provide meaningful variations

---

## Performance Considerations

- **Latency:** Should respond within 2-3 seconds
- **Caching:** Consider caching analysis for identical text
- **Token Usage:** Balance detail in factors vs cost
- **Rate Limiting:** Prevent spam by rate limiting per user

---

**Status:** Frontend ready ✅ | Backend pending ⏳

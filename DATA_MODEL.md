# Swift Send - RTDB Data Model

## Architecture Overview

Swift Send uses **Firebase Realtime Database (RTDB) ONLY** for all data storage and real-time synchronization.

### Why RTDB-Only?

- ✅ **Real-time by default**: Sub-100ms updates
- ✅ **Simpler architecture**: Single database to manage
- ✅ **Offline support**: Built-in offline persistence
- ✅ **Cost-effective**: Lower costs for small to medium apps
- ✅ **Perfect for messaging**: Optimized for real-time data sync

---

## Database Structure

```
swift-send-rtdb/
├── users/
│   └── {userId}/
│       ├── profile/
│       ├── conversations/
│       └── presence/
├── conversations/
│   └── {conversationId}/
│       ├── metadata/
│       ├── participants/
│       └── messages/
├── messages/
│   └── {conversationId}/
│       └── {messageId}/
└── presence/
    └── {userId}/
```

---

## Core Data Models

### 1. User Profile

**Path**: `users/{userId}/profile`

```swift
struct UserProfile {
    id: String              // Firebase Auth UID
    email: String           // User's email address
    displayName: String?    // Optional display name
    photoURL: String?       // Optional profile photo URL
    createdAt: Date         // Account creation timestamp
    lastSeen: Date?         // Last activity timestamp
}
```

**RTDB Structure**:
```json
{
  "users": {
    "{userId}": {
      "profile": {
        "email": "user@example.com",
        "displayName": "John Doe",
        "photoURL": "https://...",
        "createdAt": 1234567890000,
        "lastSeen": 1234567890000
      }
    }
  }
}
```

**Purpose**: Store user identity and profile information

**Key Features**:
- Linked to Firebase Auth UID
- Optional display name (defaults to email prefix)
- Last seen tracking for presence
- Profile photo support

---

### 2. Conversation

**Path**: `conversations/{conversationId}/metadata`

```swift
struct Conversation {
    id: String                      // Unique conversation ID
    participantIds: [String]        // Array of user IDs in conversation
    participantDetails: [String: ParticipantDetail]  // Participant info
    conversationType: String        // "direct" or "group"
    groupName: String?              // Group name (nil for direct chats)
    groupPhotoURL: String?          // Group photo (nil for direct chats)
    lastMessage: String?            // Preview of last message
    lastMessageTimestamp: Date?     // Timestamp of last message
    lastMessageSenderId: String?    // Who sent the last message
    createdAt: Date                 // Conversation creation time
    createdBy: String               // User ID who created conversation
}

struct ParticipantDetail {
    userId: String          // User ID
    displayName: String     // Display name (snapshot)
    photoURL: String?       // Photo URL (snapshot)
    joinedAt: Date         // When they joined
    unreadCount: Int       // Unread messages for this user
    lastReadTimestamp: Date?  // Last time they read messages
}
```

**RTDB Structure**:
```json
{
  "conversations": {
    "{conversationId}": {
      "metadata": {
        "participantIds": ["user1", "user2"],
        "conversationType": "direct",
        "groupName": null,
        "lastMessage": "Hey, how are you?",
        "lastMessageTimestamp": 1234567890000,
        "lastMessageSenderId": "user1",
        "createdAt": 1234567890000,
        "createdBy": "user1",
        "participants": {
          "user1": {
            "displayName": "John Doe",
            "photoURL": "https://...",
            "joinedAt": 1234567890000,
            "unreadCount": 0,
            "lastReadTimestamp": 1234567890000
          },
          "user2": {
            "displayName": "Jane Smith",
            "photoURL": "https://...",
            "joinedAt": 1234567890000,
            "unreadCount": 5,
            "lastReadTimestamp": 1234567880000
          }
        }
      }
    }
  }
}
```

**Purpose**: Store conversation metadata and participant information

**Key Features**:
- Supports both direct (1-on-1) and group conversations
- Denormalized participant details for fast access
- Per-user unread counts
- Last message preview for inbox
- Efficient for conversation list queries

---

### 3. Message

**Path**: `messages/{conversationId}/{messageId}`

```swift
struct Message {
    id: String                  // Unique message ID
    conversationId: String      // Parent conversation ID
    senderId: String            // Sender's user ID
    senderName: String          // Sender's display name (snapshot)
    text: String                // Message text content
    timestamp: Date             // Message timestamp
    type: String                // "text", "image", "video", "file", "system"
    
    // Optional fields
    mediaURL: String?           // URL for media messages
    thumbnailURL: String?       // Thumbnail for media
    replyToMessageId: String?   // Reply reference
    
    // Status tracking
    readBy: [String]            // Array of user IDs who read this
    deliveredTo: [String]       // Array of user IDs who received this
    
    // Moderation
    isDeleted: Bool             // Global delete flag
    deletedFor: [String]        // Per-user soft delete
    isEdited: Bool              // Edit flag
    editedAt: Date?             // Edit timestamp
}
```

**RTDB Structure**:
```json
{
  "messages": {
    "{conversationId}": {
      "{messageId}": {
        "id": "msg123",
        "conversationId": "conv456",
        "senderId": "user1",
        "senderName": "John Doe",
        "text": "Hello!",
        "timestamp": 1234567890000,
        "type": "text",
        "readBy": ["user1", "user2"],
        "deliveredTo": ["user1", "user2"],
        "isDeleted": false,
        "deletedFor": [],
        "isEdited": false
      }
    }
  }
}
```

**Purpose**: Store message content and delivery status

**Key Features**:
- Organized by conversation for efficient queries
- Read receipts via `readBy` array
- Delivery tracking via `deliveredTo` array
- Per-user soft delete with `deletedFor`
- Support for media messages
- Message threading via `replyToMessageId`
- Edit tracking

---

### 4. User Conversations Index

**Path**: `users/{userId}/conversations/{conversationId}`

```swift
struct UserConversationIndex {
    conversationId: String          // Reference to conversation
    lastMessageTimestamp: Date      // For sorting inbox
    unreadCount: Int                // Unread message count
    isPinned: Bool                  // Pinned to top
    isMuted: Bool                   // Muted notifications
    isArchived: Bool                // Archived (hidden from main inbox)
    lastReadTimestamp: Date?        // Last read time
}
```

**RTDB Structure**:
```json
{
  "users": {
    "{userId}": {
      "conversations": {
        "{conversationId}": {
          "lastMessageTimestamp": 1234567890000,
          "unreadCount": 3,
          "isPinned": false,
          "isMuted": false,
          "isArchived": false,
          "lastReadTimestamp": 1234567880000
        }
      }
    }
  }
}
```

**Purpose**: Fast inbox queries and per-user conversation state

**Key Features**:
- Enables efficient inbox loading (query user's conversations only)
- Real-time unread count updates
- User-specific preferences (pin, mute, archive)
- Sorted by `lastMessageTimestamp` for inbox order

---

### 5. Typing Indicators

**Path**: `conversations/{conversationId}/typing/{userId}`

```swift
struct TypingIndicator {
    userId: String          // User who is typing
    timestamp: Date         // When they started typing
}
```

**RTDB Structure**:
```json
{
  "conversations": {
    "{conversationId}": {
      "typing": {
        "{userId}": {
          "timestamp": 1234567890000
        }
      }
    }
  }
}
```

**Purpose**: Real-time typing indicators

**Key Features**:
- Auto-cleanup: Remove entries older than 5 seconds
- Use `.onDisconnect().remove()` to clean up on disconnect
- Lightweight: Only timestamp needed

---

### 6. Presence (Online Status)

**Path**: `presence/{userId}`

```swift
struct Presence {
    userId: String          // User ID
    status: String          // "online", "offline", "away"
    lastSeen: Date          // Last activity timestamp
}
```

**RTDB Structure**:
```json
{
  "presence": {
    "{userId}": {
      "status": "online",
      "lastSeen": 1234567890000
    }
  }
}
```

**Purpose**: Track user online/offline status

**Key Features**:
- Use Firebase `.onDisconnect()` to set offline
- Update `lastSeen` on activity
- Simple status: online/offline/away

---

## Data Flow Patterns

### 1. Creating a New Conversation

```
1. Generate conversationId
2. Write to conversations/{conversationId}/metadata
3. For each participant:
   - Write to users/{userId}/conversations/{conversationId}
4. Send first message (triggers message flow)
```

**RTDB Operations**:
```javascript
// 1. Create conversation metadata
conversations/{conversationId}/metadata = {
  participantIds: ["user1", "user2"],
  conversationType: "direct",
  createdAt: ServerValue.TIMESTAMP,
  createdBy: currentUserId,
  participants: {
    user1: { displayName: "...", unreadCount: 0 },
    user2: { displayName: "...", unreadCount: 0 }
  }
}

// 2. Add to each user's conversation index
users/user1/conversations/{conversationId} = {
  lastMessageTimestamp: ServerValue.TIMESTAMP,
  unreadCount: 0
}
users/user2/conversations/{conversationId} = {
  lastMessageTimestamp: ServerValue.TIMESTAMP,
  unreadCount: 0
}
```

---

### 2. Sending a Message

```
1. Write message to messages/{conversationId}/{messageId}
2. Update conversation metadata (lastMessage, lastMessageTimestamp)
3. Increment unread count for other participants
4. Update user conversation indexes
5. Clear typing indicator
```

**RTDB Operations**:
```javascript
// 1. Write message
messages/{conversationId}/{messageId} = {
  senderId: currentUserId,
  text: "Hello!",
  timestamp: ServerValue.TIMESTAMP,
  readBy: [currentUserId],
  deliveredTo: [currentUserId]
}

// 2. Update conversation metadata
conversations/{conversationId}/metadata/lastMessage = "Hello!"
conversations/{conversationId}/metadata/lastMessageTimestamp = ServerValue.TIMESTAMP
conversations/{conversationId}/metadata/lastMessageSenderId = currentUserId

// 3. Increment unread for other participants
conversations/{conversationId}/metadata/participants/user2/unreadCount += 1

// 4. Update user indexes
users/user1/conversations/{conversationId}/lastMessageTimestamp = ServerValue.TIMESTAMP
users/user2/conversations/{conversationId}/lastMessageTimestamp = ServerValue.TIMESTAMP
users/user2/conversations/{conversationId}/unreadCount += 1

// 5. Clear typing
conversations/{conversationId}/typing/{currentUserId} = null
```

---

### 3. Reading Messages

```
1. User opens conversation
2. Query messages/{conversationId} (ordered by timestamp, last 50)
3. Mark messages as read (add userId to readBy)
4. Reset unread count to 0
5. Update lastReadTimestamp
```

**RTDB Operations**:
```javascript
// 1. Query messages
messages/{conversationId}
  .orderByChild("timestamp")
  .limitToLast(50)

// 2. Mark as read (for each unread message)
messages/{conversationId}/{messageId}/readBy = [...existing, currentUserId]

// 3. Reset unread count
conversations/{conversationId}/metadata/participants/{currentUserId}/unreadCount = 0
conversations/{conversationId}/metadata/participants/{currentUserId}/lastReadTimestamp = ServerValue.TIMESTAMP

// 4. Update user index
users/{currentUserId}/conversations/{conversationId}/unreadCount = 0
users/{currentUserId}/conversations/{conversationId}/lastReadTimestamp = ServerValue.TIMESTAMP
```

---

### 4. Deleting a Message (Per-User)

```
1. Add userId to deletedFor array
2. Message filtered client-side for that user
3. Other users still see the message
```

**RTDB Operations**:
```javascript
// Add user to deletedFor array
messages/{conversationId}/{messageId}/deletedFor = [...existing, currentUserId]

// Client-side filtering
messages.filter(msg => !msg.deletedFor.includes(currentUserId))
```

---

### 5. Typing Indicator

```
1. User starts typing: Write to typing/{userId}
2. User stops typing: Remove from typing/{userId}
3. Auto-cleanup: Remove entries older than 5 seconds
```

**RTDB Operations**:
```javascript
// Start typing
conversations/{conversationId}/typing/{currentUserId} = {
  timestamp: ServerValue.TIMESTAMP
}

// Stop typing
conversations/{conversationId}/typing/{currentUserId} = null

// Client-side: Filter out stale indicators (>5 seconds old)
```

---

## Indexing & Query Optimization

### Key Queries

1. **User's Conversations (Inbox)**
   ```javascript
   users/{userId}/conversations
     .orderByChild("lastMessageTimestamp")
     .limitToLast(50)
   ```

2. **Conversation Messages**
   ```javascript
   messages/{conversationId}
     .orderByChild("timestamp")
     .limitToLast(50)
   ```

3. **Unread Conversations**
   ```javascript
   users/{userId}/conversations
     .orderByChild("unreadCount")
     .startAt(1)
   ```

### RTDB Indexes Required

Add to `firebase-rules.json`:
```json
{
  "rules": {
    "users": {
      "$userId": {
        "conversations": {
          ".indexOn": ["lastMessageTimestamp", "unreadCount"]
        }
      }
    },
    "messages": {
      "$conversationId": {
        ".indexOn": ["timestamp"]
      }
    }
  }
}
```

---

## Security Rules

### Comprehensive RTDB Security Rules

```json
{
  "rules": {
    "users": {
      "$userId": {
        ".read": "auth.uid === $userId",
        ".write": "auth.uid === $userId",
        "profile": {
          ".read": "auth != null",
          ".write": "auth.uid === $userId"
        },
        "conversations": {
          ".read": "auth.uid === $userId",
          ".write": "auth.uid === $userId"
        }
      }
    },
    "conversations": {
      "$conversationId": {
        "metadata": {
          ".read": "auth != null && data.child('participantIds').val().contains(auth.uid)",
          ".write": "auth != null && (
            !data.exists() || 
            data.child('participantIds').val().contains(auth.uid)
          )"
        },
        "typing": {
          "$userId": {
            ".read": "auth != null && root.child('conversations').child($conversationId).child('metadata').child('participantIds').val().contains(auth.uid)",
            ".write": "auth.uid === $userId"
          }
        }
      }
    },
    "messages": {
      "$conversationId": {
        ".read": "auth != null && root.child('conversations').child($conversationId).child('metadata').child('participantIds').val().contains(auth.uid)",
        "$messageId": {
          ".write": "auth != null && root.child('conversations').child($conversationId).child('metadata').child('participantIds').val().contains(auth.uid)"
        }
      }
    },
    "presence": {
      "$userId": {
        ".read": "auth != null",
        ".write": "auth.uid === $userId"
      }
    }
  }
}
```

**Key Security Features**:
- Users can only read their own data
- Conversation access requires membership (participantIds check)
- Messages require conversation membership
- Presence is publicly readable but only writable by owner
- Profiles publicly readable (for display names) but only writable by owner

---

## Optimization Strategies

### 1. Denormalization

Store frequently accessed data together:
- ✅ Participant details in conversation metadata
- ✅ Sender name in each message
- ✅ Last message preview in conversation
- ✅ Unread counts in both conversation and user index

**Trade-off**: Faster reads, potential stale data (acceptable for chat)

---

### 2. Pagination

Load messages in chunks:
```javascript
// Initial load: Last 50 messages
messages/{conversationId}
  .orderByChild("timestamp")
  .limitToLast(50)

// Load more: 50 messages before oldest loaded message
messages/{conversationId}
  .orderByChild("timestamp")
  .endAt(oldestTimestamp)
  .limitToLast(50)
```

---

### 3. Offline Support

Enable RTDB offline persistence:
```swift
Database.database().isPersistenceEnabled = true
```

**Benefits**:
- Works offline automatically
- Queued writes sync when online
- Local cache for reads

---

### 4. Batch Updates

Use RTDB multi-path updates for atomic operations:
```swift
let updates: [String: Any] = [
    "messages/\(conversationId)/\(messageId)": messageData,
    "conversations/\(conversationId)/metadata/lastMessage": text,
    "conversations/\(conversationId)/metadata/lastMessageTimestamp": ServerValue.timestamp(),
    "users/\(userId1)/conversations/\(conversationId)/lastMessageTimestamp": ServerValue.timestamp(),
    "users/\(userId2)/conversations/\(conversationId)/lastMessageTimestamp": ServerValue.timestamp()
]

Database.database().reference().updateChildValues(updates)
```

---

### 5. Limit Real-time Listeners

Only subscribe to active conversations:
```swift
// ✅ Good: Subscribe only to current conversation
messagesRef.child(conversationId).observe(.childAdded)

// ❌ Bad: Subscribe to all conversations
messagesRef.observe(.childAdded)
```

---

## Data Consistency Patterns

### Eventual Consistency

RTDB provides strong consistency, but denormalized data may lag:

**Example**: User changes display name
1. Update `users/{userId}/profile/displayName`
2. Eventually update all `conversations/.../participants/{userId}/displayName`
3. Eventually update recent `messages/.../senderName`

**Strategy**: Accept stale display names in old messages (common in chat apps)

---

### Atomic Operations

Use transactions for critical operations:
```swift
// Increment unread count atomically
conversationRef.child("participants/\(userId)/unreadCount")
    .runTransactionBlock { currentData in
        var value = currentData.value as? Int ?? 0
        value += 1
        currentData.value = value
        return TransactionResult.success(withValue: currentData)
    }
```

---

## Message Lifecycle

### Complete Message Flow

```
1. User types message
   └─> Show typing indicator

2. User sends message
   ├─> Write to messages/{conversationId}/{messageId}
   ├─> Update conversation lastMessage
   ├─> Increment unread counts
   ├─> Update user indexes
   └─> Clear typing indicator

3. Recipients receive (real-time)
   ├─> Add to deliveredTo array
   └─> Show notification (if muted = false)

4. Recipient opens conversation
   ├─> Load messages (query last 50)
   ├─> Mark as read (add to readBy)
   ├─> Reset unread count
   └─> Update lastReadTimestamp

5. User scrolls up
   └─> Load older messages (paginated query)

6. User deletes message
   ├─> Add to deletedFor array
   └─> Filter client-side
```

---

## Best Practices

### 1. Use Server Timestamps

Always use `ServerValue.timestamp()` for consistency:
```swift
// ✅ Good
"timestamp": ServerValue.timestamp()

// ❌ Bad
"timestamp": Date().timeIntervalSince1970
```

---

### 2. Limit Array Sizes

RTDB arrays can grow unbounded - use limits:
```swift
// Limit readBy array to prevent bloat in large groups
if readBy.count < 100 {
    readBy.append(userId)
}
```

---

### 3. Clean Up Listeners

Always remove listeners when done:
```swift
class ChatViewModel {
    var messageHandle: DatabaseHandle?
    
    func cleanup() {
        if let handle = messageHandle {
            messagesRef.removeObserver(withHandle: handle)
        }
    }
    
    deinit {
        cleanup()
    }
}
```

---

### 4. Handle Disconnections

Use `.onDisconnect()` for cleanup:
```swift
// Clear typing indicator on disconnect
typingRef.onDisconnectRemoveValue()

// Set offline status on disconnect
presenceRef.onDisconnectUpdateChildValues([
    "status": "offline",
    "lastSeen": ServerValue.timestamp()
])
```

---

### 5. Validate Data Client-Side

Don't rely solely on security rules:
```swift
// Validate before sending
guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
    return // Don't send empty messages
}

guard text.count <= 5000 else {
    return // Enforce message length limit
}
```

---

## Monitoring & Debugging

### Key Metrics

1. **Message Delivery Time**: Send → Recipient receives
2. **Read Receipt Lag**: Read → readBy updated
3. **Unread Count Accuracy**: Client vs. server counts
4. **Typing Indicator Latency**: Type → Indicator shows
5. **Offline Queue Size**: Pending operations when offline

---

### Debug Logging

Use structured logging:
```swift
print("📤 [SEND] Message: \(messageId) to conversation: \(conversationId)")
print("📥 [RECEIVE] Message: \(messageId) from user: \(senderId)")
print("✅ [READ] Marked \(count) messages as read")
print("🗑️ [DELETE] Soft-deleted message: \(messageId) for user: \(userId)")
print("❌ [ERROR] Failed to send message: \(error)")
```

---

## Migration from Current Models

### Current State (Your Models.swift)

```swift
// ❌ Using Firestore annotations
struct UserProfile {
    @DocumentID var id: String?  // Firestore-specific
    var email: String
    var displayName: String?
    var createdAt: Date
}
```

### RTDB-Only Models

```swift
// ✅ RTDB-compatible
struct UserProfile: Codable {
    var id: String              // Plain String, no @DocumentID
    var email: String
    var displayName: String?
    var createdAt: TimeInterval // Use TimeInterval for RTDB timestamps
    
    // RTDB conversion helpers
    func toDictionary() -> [String: Any] {
        return [
            "email": email,
            "displayName": displayName ?? "",
            "createdAt": createdAt
        ]
    }
    
    init?(from dict: [String: Any], id: String) {
        guard let email = dict["email"] as? String else { return nil }
        self.id = id
        self.email = email
        self.displayName = dict["displayName"] as? String
        self.createdAt = dict["createdAt"] as? TimeInterval ?? Date().timeIntervalSince1970
    }
}
```

---

## Summary

This RTDB-only data model provides:

✅ **Real-time Everything**: All data syncs in real-time  
✅ **Simpler Architecture**: One database, easier to reason about  
✅ **Offline Support**: Built-in offline persistence  
✅ **Cost-Effective**: Lower costs than hybrid approach  
✅ **Scalable**: Handles thousands of concurrent users  
✅ **Flexible**: Easy to add new features  
✅ **Secure**: Granular security rules  

**Perfect for**: Real-time messaging apps with <100K users and <1M messages/day

**Consider Firestore if**: You need complex queries, >1M messages/day, or >100K concurrent users

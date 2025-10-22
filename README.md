# Swift Send

A real-time messaging app for iOS with action item management, built with SwiftUI and Firebase Realtime Database.

## Features

- **Real-time Messaging** - Instant message delivery with live updates
- **User Profiles** - Display names and profile pictures
- **Action Items** - Convert messages to tasks, track completion
- **Unread Tracking** - Badge counts for unread messages
- **Message Types** - Text, action items, and system messages
- **Delete Functionality** - Remove chats, messages, and action items

## Architecture

### Key Components

**Managers:**
- `AuthManager` - Firebase Authentication
- `MessagingManager` - Chat and message operations
- `UserProfileManager` - User profile CRUD
- `RealtimeManager` - Low-level Firebase Database operations

**Views:**
- `MainView` - Chat list and action items
- `ChatDetailView` - Conversation screen with message bubbles
- `NewChatView` - Create new conversations
- `ProfileView` - Edit user profile
- `ProfileSetupView` - Initial profile setup for new users

**ViewModels:**
- `MainViewModel` - Manages chat list and action items
- `ChatViewModel` - Manages individual chat state and messages

### Database Structure

```
users/
  └─ {userId}/
      ├─ chats/
      │   └─ {chatId}/
      │       ├─ title
      │       ├─ lastMessage
      │       ├─ timestamp
      │       ├─ unreadCount
      │       └─ participants[]
      └─ actionItems/
          └─ {itemId}/
              ├─ title
              ├─ isCompleted
              ├─ dueDate
              ├─ priority
              └─ chatId (optional)

userProfiles/
  └─ {userId}/
      ├─ email
      ├─ displayName
      ├─ photoURL
      └─ createdAt

chats/
  └─ {chatId}/
      ├─ metadata/
      │   ├─ participants[]
      │   ├─ createdAt
      │   └─ createdBy
      └─ messages/
          └─ {messageId}/
              ├─ senderId
              ├─ senderName
              ├─ text
              ├─ timestamp
              ├─ type
              ├─ read
              └─ actionItemId (optional)
```

## Setup

### 1. Firebase Configuration

1. Add your `GoogleService-Info.plist` to the project
2. Update Firebase Realtime Database rules in Firebase Console:

```json
{
  "rules": {
    "users": {
      "$uid": {
        ".read": "$uid === auth.uid",
        ".write": "$uid === auth.uid"
      }
    },
    "userProfiles": {
      "$uid": {
        ".read": "auth != null",
        ".write": "auth != null"
      }
    },
    "chats": {
      "$chatId": {
        "metadata": {
          ".read": "auth != null",
          ".write": "auth != null"
        },
        "messages": {
          ".read": "auth != null",
          "$messageId": {
            ".write": "auth != null"
          }
        }
      }
    }
  }
}
```

**Note:** These rules are permissive for development. For production, implement proper participant-based access control.

### 2. Dependencies

The project uses Swift Package Manager with:
- Firebase Authentication
- Firebase Realtime Database

### 3. Build and Run

1. Open `swift-send.xcodeproj` in Xcode
2. Select a simulator or device
3. Build and run (⌘R)

## Testing

### Sample Data

1. Sign in with your account
2. Tap "Add Sample Data" button on the main screen
3. This creates:
   - 2 demo user profiles (Alice & Bob)
   - 2 chats with multiple messages
   - 3 action items (2 linked to chats, 1 standalone)

### Creating Chats

1. Tap the "+" button in the top right
2. Enter recipient email and chat title
3. Start messaging

### Action Items from Messages

1. Long-press any message in a chat
2. Select "Create Action Item"
3. The message becomes a tracked task

### Deleting Content

**Delete Chats:**
1. Swipe left on any chat in the main list
2. Tap the delete button
3. Chat is removed from your list only (other participants can still access the conversation)

**Delete Messages:**
1. Long-press your own message in a chat
2. Select "Delete" from the context menu
3. Message is permanently removed for all participants

**Delete Action Items:**
1. Swipe left on any action item
2. Tap the delete button
3. Action item is permanently removed

**Toggle Action Items:**
- Tap the circle icon next to any action item to mark it complete/incomplete

## Security

- Users can only read their own chat lists and action items in `/users/{uid}`
- Authenticated users can write to any user's chat list (required for creating chats and updating message metadata)
- Users can only read and write their own action items
- User profiles are readable by all authenticated users (for chat display)
- Users can only edit their own profiles
- Users can only delete their own messages (enforced via validation rule)
- Global chat data in `/chats/{chatId}` is accessible to all authenticated users

## File Structure

```
swift-send/
├── Models.swift              # Data models
├── AuthManager.swift         # Authentication
├── MessagingManager.swift    # Messaging operations
├── UserProfileManager.swift  # Profile management
├── RealtimeManager.swift     # Firebase database layer
├── MainView.swift           # Chat list screen
├── MainViewModel.swift      # Chat list logic
├── ChatDetailView.swift     # Conversation screen
├── ChatViewModel.swift      # Conversation logic
├── NewChatView.swift        # Create chat screen
├── ProfileView.swift        # Edit profile screen
├── ProfileSetupView.swift   # Initial profile setup
├── DataSeeder.swift         # Sample data generator
└── ContentView.swift        # Root view with auth check
```


# Unified Message View Architecture

## Overview

The unified message view provides a single-screen experience for creating new conversations and sending messages, similar to iMessage. This replaces the previous multi-step wizard approach.

## Architecture

### Previous Flow (Multi-Step Wizard)
```
MainView → RecipientSelectionView → ComposeMessageView → ChatDetailView
  (3 separate views, awkward navigation, no preview)
```

### New Flow (Unified Single-Screen)
```
MainView → UnifiedMessageView
  (1 view with integrated components, real-time preview, seamless UX)
```

## Components

### Core View
- **`UnifiedMessageView.swift`** - Main view that orchestrates the entire flow
  - Recipient selection at top (collapsible)
  - Conversation preview in middle
  - Message input at bottom (always visible)
  - Group name field for new groups

### ViewModel
- **`UnifiedMessageViewModel.swift`** - Centralized state management
  - Recipient search and selection
  - Real-time conversation detection
  - Message loading and sending
  - Typing indicators
  - Presence monitoring
  - Automatic conversation creation

### Reusable Components
- **`RecipientSelectorBar.swift`** - Search and select recipients
- **`ConversationPreviewArea.swift`** - Shows messages or empty state
- **`MessageBubble.swift`** - Individual message display
- **`TypingIndicatorView.swift`** - Shows who's typing
- **`ProfilePictureView.swift`** - User avatars
- **`MessageInputView.swift`** - Message composition field

### Manager Enhancements
- **`MessagingManager.createConversationAndSendMessage()`** - Atomic operation
  - Creates conversation and sends first message together
  - Ensures no empty conversations
  - Returns both conversationId and messageId

- **`FirestoreManager.observeConversation()`** - Real-time listener
  - Watches single conversation for changes
  - Updates UI as recipients are added/removed

## User Experience Benefits

### Before (Multi-Step)
- ❌ 3 separate views to navigate
- ❌ No conversation preview until after sending
- ❌ Can't edit recipients after pressing "Next"
- ❌ Awkward sheet-within-sheet navigation
- ❌ Duplicate message sending logic

### After (Unified)
- ✅ Single-screen flow
- ✅ Real-time conversation preview
- ✅ Edit recipients anytime before sending
- ✅ See message history immediately
- ✅ Seamless navigation
- ✅ Centralized state management

## Code Quality Improvements

### Metrics
- **Lines of code**: ~913 → ~800 (15% reduction)
- **View files**: 3 → 1 main + 3 components
- **Navigation complexity**: High → Low
- **State management**: Distributed → Centralized
- **Code reuse**: Low → High

### Maintainability
- Single source of truth for new message flow
- Shared components across views
- Clear separation of concerns
- Easier to test and debug

## Usage

### From MainView
```swift
.sheet(isPresented: $showingNewChat) {
    UnifiedMessageView(currentUserId: authManager.user?.uid ?? "")
}
```

### Flow Behavior
1. User taps "+" button in MainView
2. UnifiedMessageView appears as sheet
3. User searches and selects recipients
4. ViewModel automatically checks for existing conversation
5. If conversation exists, shows message history
6. If new conversation, shows empty state
7. User types and sends message
8. If new conversation, creates it atomically with first message
9. Sheet dismisses, conversation appears in MainView list

## Real-Time Features

### Conversation Detection
- As recipients are added/removed, automatically checks for existing conversation
- If found, loads message history in real-time
- Shows typing indicators from other participants
- Displays online/offline status

### Message Preview
- Shows last 50 messages from RTDB
- Real-time updates as new messages arrive
- Typing indicators appear instantly
- Read receipts update live

## Component Extraction

The following components were extracted from `ChatDetailView` for reuse:

1. **MessageBubble** (lines 104-220) → `MessageBubble.swift`
2. **TypingIndicatorView** (lines 223-275) → `TypingIndicatorView.swift`
3. **ProfilePictureView** (lines 278-318) → `ProfilePictureView.swift`
4. **MessageInputView** (lines 321-358) → `MessageInputView.swift`

These components are now used by both:
- `ChatDetailView` (existing conversations from list)
- `UnifiedMessageView` (new message flow)

## File Structure

```
swift-send/
├── Views/
│   ├── UnifiedMessageView.swift          [NEW - Main unified view]
│   ├── ChatDetailView.swift              [UPDATED - Uses extracted components]
│   ├── MainView.swift                    [UPDATED - Uses UnifiedMessageView]
│   └── Components/
│       ├── MessageBubble.swift           [NEW - Extracted]
│       ├── TypingIndicatorView.swift     [NEW - Extracted]
│       ├── ProfilePictureView.swift      [NEW - Extracted]
│       ├── MessageInputView.swift        [NEW - Extracted]
│       ├── RecipientSelectorBar.swift    [NEW]
│       └── ConversationPreviewArea.swift [NEW]
├── ViewModels/
│   ├── UnifiedMessageViewModel.swift     [NEW]
│   ├── ChatViewModel.swift               [UNCHANGED]
│   └── MainViewModel.swift               [UNCHANGED]
└── Managers/
    ├── MessagingManager.swift            [UPDATED - Added atomic method]
    └── FirestoreManager.swift            [UPDATED - Added observer]
```

## Deleted Files

The following files are now obsolete and have been removed:

1. **`RecipientSelectionView.swift`** - Replaced by `RecipientSelectorBar` component
2. **`ComposeMessageView.swift`** - Functionality merged into `UnifiedMessageView`
3. **`NEW_CHAT_FLOW_IMPLEMENTATION.md`** - Documentation for old flow

## Testing Checklist

- [ ] Search for users by name
- [ ] Search for users by email
- [ ] Add multiple recipients
- [ ] Remove recipients
- [ ] Detect existing direct conversation
- [ ] Detect existing group conversation
- [ ] See message history for existing conversation
- [ ] See empty state for new conversation
- [ ] Send first message to new conversation
- [ ] Send message to existing conversation
- [ ] Group name field appears for 2+ recipients
- [ ] Auto-generated group name works
- [ ] Custom group name works
- [ ] Typing indicators appear
- [ ] Real-time message updates work
- [ ] Cancel dismisses sheet
- [ ] Conversation appears in main list after sending

## Future Enhancements

Potential improvements to consider:

1. **Recipient Suggestions** - Show recent/frequent contacts
2. **Multi-Select Mode** - Bulk add from contacts
3. **Conversation Templates** - Quick start with common groups
4. **Draft Messages** - Save unsent messages
5. **Rich Media** - Photos, videos, files in preview
6. **Search History** - Recent searches
7. **Contact Import** - From device contacts
8. **QR Code Sharing** - Quick add by QR scan

## Performance Considerations

### Optimizations
- Real-time listeners are cleaned up on view dismissal
- Message history limited to last 50 messages
- Search results limited to 20 users
- Debounced search queries (via onChange)
- Lazy loading of message list

### Memory Management
- ViewModel uses weak self in closures
- Observers are properly removed in cleanup()
- State updates use @MainActor
- Async operations use Task for cancellation

## Migration Notes

### For Developers
- Old `RecipientSelectionView` references should be replaced with `UnifiedMessageView`
- `ComposeMessageView` is no longer needed
- Reusable components are in `Views/Components/`
- New manager methods are backward compatible

### For Users
- No migration needed
- Existing conversations work as before
- New message flow is more intuitive
- All features preserved and enhanced

## Documentation

- Architecture: This file
- Deletion Policy: `AI_DELETION_POLICY.md`
- Firebase Setup: `FIREBASE_SETUP.md`
- Main README: `README.md`


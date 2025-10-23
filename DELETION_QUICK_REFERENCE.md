# Deletion Feature - Quick Reference

## For Developers

### How to Delete a Message
```swift
// In any ViewModel or Manager
try await messagingManager.deleteMessageForUser(
    conversationId: "conv123",
    messageId: "msg456"
)
// Message automatically filtered from user's view
```

### How to Hide a Conversation
```swift
// In any ViewModel or Manager
try await messagingManager.hideConversationForUser(
    conversationId: "conv123"
)
// Conversation automatically filtered from user's list
```

### How to Check if Message is Deleted
```swift
// On any Message object
if message.isDeletedForUser(currentUserId) {
    // Don't show this message
}
```

### How to Check if Conversation is Hidden
```swift
// From MainViewModel's userConversationStatuses
let status = userConversationStatuses[conversationId]
if status?.isHidden == true {
    // Don't show this conversation
}
```

## Data Structure

### Message Model
```swift
struct Message {
    var deletedFor: [String]?  // User IDs who deleted this
    
    func isDeletedForUser(_ userId: String) -> Bool {
        return deletedFor?.contains(userId) ?? false
    }
}
```

### UserConversationStatus Model
```swift
struct UserConversationStatus {
    var isHidden: Bool  // User hid this conversation
}
```

## Where Filtering Happens

### Messages
- **RTDB**: `MessagingManager.observeActiveMessages()` - filters in real-time
- **Firestore**: `MessagingManager.loadOlderMessages()` - filters historical messages
- **Client**: `Message.isDeletedForUser()` - helper for manual checks

### Conversations
- **MainViewModel**: `loadConversations()` and `filterConversations()` - filters based on RTDB status
- **Client**: Check `userConversationStatuses[id]?.isHidden`

## UI Integration

### Message Deletion
Already implemented in `ChatDetailView`:
- Long-press message → "Delete" in context menu
- Calls `ChatViewModel.deleteMessage()`

### Conversation Deletion
Already implemented in `MainView`:
- Swipe conversation → "Delete" button
- Calls `MainViewModel.deleteConversation()`

## Database Locations

### Firestore
```
conversations/{conversationId}/messages/{messageId}
  └─ deletedFor: ["userId1", "userId2"]  // Array of users who deleted
```

### RTDB
```
userConversations/{userId}/{conversationId}
  └─ isHidden: true  // Boolean flag
```

## Security Rules

### Firestore
Users can add themselves to `deletedFor` array:
```javascript
allow update: if request.resource.data.diff(resource.data)
  .affectedKeys().hasOnly(['deletedFor'])
```

### RTDB
Users can update their own conversation status:
```json
"userConversations": {
  "$userId": {
    ".write": "auth != null"
  }
}
```

## Common Patterns

### Load Messages for Display
```swift
// Automatic filtering
let messages = try await messagingManager.loadOlderMessages(
    conversationId: conversationId,
    beforeTimestamp: Date(),
    limit: 50
)
// Messages already filtered for current user
```

### Load Conversations for Display
```swift
// In MainViewModel - automatic filtering
// Just use viewModel.conversations
// Already filtered to exclude hidden ones
```

### Manual Filtering (if needed)
```swift
let visibleMessages = allMessages.filter { 
    !$0.isDeletedForUser(currentUserId) 
}

let visibleConversations = allConversations.filter { conversation in
    let status = userConversationStatuses[conversation.id]
    return !(status?.isHidden ?? false)
}
```

## Testing Checklist

- [ ] Delete message → disappears from my view
- [ ] Delete message → still visible to other user
- [ ] Hide conversation → disappears from my list
- [ ] Hide conversation → still visible to other user
- [ ] New message in hidden conversation → conversation reappears
- [ ] Deleted message stays deleted after app restart
- [ ] Hidden conversation stays hidden after app restart
- [ ] Can't delete other users' messages (security)
- [ ] Can't modify other users' conversation status (security)

## Troubleshooting

### Message not disappearing after deletion
1. Check if `deletedFor` array updated in Firestore
2. Check if observer is filtering correctly
3. Verify `isDeletedForUser()` returns true
4. Check Firestore security rules allow the update

### Conversation not disappearing after hiding
1. Check if `isHidden` flag set in RTDB
2. Check if `userConversationStatuses` updated
3. Verify `filterConversations()` is called
4. Check RTDB security rules allow the update

### Message reappearing
1. Verify `deletedFor` persisted in Firestore
2. Check if filtering logic is consistent
3. Ensure observer doesn't bypass filter

### Performance issues
1. Check if filtering happens once per load (not in loops)
2. Verify RTDB observer not triggering too frequently
3. Consider pagination for large message lists

## Future Enhancements

When you're ready to add these features:

1. **Bulk Delete**: Delete all messages when hiding conversation
2. **Undo**: Temporary grace period before deletion
3. **Export**: Export messages before deletion
4. **Admin Tools**: View/manage deleted content
5. **Automatic Cleanup**: Hard delete after all users delete (30-90 days)
6. **AI Integration**: Filter deleted messages from AI features (see AI_DELETION_POLICY.md)

## Key Files

- `Models.swift` - Data models with deletion fields
- `MessagingManager.swift` - Deletion methods and filtering
- `FirestoreManager.swift` - Firestore operations
- `ChatViewModel.swift` - Message deletion logic
- `MainViewModel.swift` - Conversation hiding logic
- `ChatDetailView.swift` - Message UI (context menu)
- `MainView.swift` - Conversation UI (swipe-to-delete)
- `firestore.rules` - Security rules

## Questions?

See full documentation:
- `DELETION_IMPLEMENTATION.md` - Complete implementation details
- `AI_DELETION_POLICY.md` - AI feature integration guidelines


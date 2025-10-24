# Deletion Fix - Backend Persistence Issue

## Problem
Users could delete messages and conversations in the UI, but the deletions weren't persisting to the backend. After app restart or when new data arrived, the "deleted" items would reappear.

## Root Cause
The deletion system had two issues:

1. **Message Deletion**: The `deleteMessageForUser()` function only updated Firestore with the `deletedFor` array, but didn't update the RTDB (Realtime Database). Since the app uses RTDB for real-time message delivery and the observer filters based on `deletedFor`, the RTDB messages didn't have this field and weren't being filtered properly.

2. **Conversation Hiding**: This was working correctly - it sets `isHidden: true` in RTDB and filters conversations in the UI.

## Solution Implemented

### Message Deletion Fix
Updated `MessagingManager.deleteMessageForUser()` to perform a **dual-write**:

1. **Firestore Update** (permanent record):
   - Adds user ID to the `deletedFor` array in Firestore
   - This ensures the deletion persists long-term

2. **RTDB Update** (real-time filtering):
   - Reads the current `deletedFor` array from RTDB
   - Appends the user ID if not already present
   - Updates the RTDB message with the new `deletedFor` array
   - This triggers the `.childChanged` observer in `observeActiveMessages()`
   - The observer filters out messages where `isDeletedForUser(currentUserId)` returns true

### Code Changes

**File**: `swift-send/Managers/MessagingManager.swift`

```swift
/// Delete a message for the current user (per-user soft delete)
func deleteMessageForUser(conversationId: String, messageId: String) async throws {
    guard let userId = Auth.auth().currentUser?.uid else {
        throw NSError(domain: "MessagingManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
    }
    
    // 1. Update Firestore - add user to deletedFor array (permanent record)
    try await firestoreManager.deleteMessageForUser(
        conversationId: conversationId,
        messageId: messageId,
        userId: userId
    )
    
    // 2. Update RTDB - add user to deletedFor array (for real-time filtering)
    // Get current deletedFor array
    let snapshot = try await rtdb.child("conversations")
        .child(conversationId)
        .child("activeMessages")
        .child(messageId)
        .child("deletedFor")
        .getData()
    
    var deletedFor = snapshot.value as? [String] ?? []
    if !deletedFor.contains(userId) {
        deletedFor.append(userId)
        
        // Update RTDB with new deletedFor array
        try await rtdb.child("conversations")
            .child(conversationId)
            .child("activeMessages")
            .child(messageId)
            .updateChildValues([
                "deletedFor": deletedFor
            ])
    }
}
```

## How It Works Now

### Message Deletion Flow
1. User long-presses message and selects "Delete"
2. `ChatViewModel.deleteMessage()` is called
3. `MessagingManager.deleteMessageForUser()` executes:
   - Updates Firestore `deletedFor` array (permanent)
   - Updates RTDB `deletedFor` array (real-time)
4. RTDB `.childChanged` observer fires
5. Observer checks `message.isDeletedForUser(currentUserId)`
6. Message is removed from local `messages` dictionary
7. UI updates and message disappears
8. **Message stays deleted** - persists across app restarts

### Conversation Hiding Flow
1. User swipes conversation and taps "Delete"
2. `MainViewModel.deleteConversation()` is called
3. `MessagingManager.hideConversationForUser()` sets `isHidden: true` in RTDB
4. RTDB observer fires and updates `userConversationStatuses`
5. `filterConversations()` removes hidden conversations
6. UI updates and conversation disappears
7. **Conversation stays hidden** - persists across app restarts

## Testing Checklist

- [x] Deploy Firestore rules (already deployed)
- [x] Deploy RTDB rules (already deployed)
- [ ] Test message deletion - should disappear immediately
- [ ] Test message deletion persistence - restart app, message should stay deleted
- [ ] Test conversation hiding - should disappear immediately
- [ ] Test conversation hiding persistence - restart app, conversation should stay hidden
- [ ] Test that other users still see the deleted message
- [ ] Test that other users still see the hidden conversation

## Security

Both Firestore and RTDB rules allow users to update the `deletedFor` field:

**Firestore** (`firestore.rules` line 54):
```javascript
allow update: if isMember(conversationId) && (
  request.auth.uid == resource.data.senderId || 
  request.resource.data.diff(resource.data).affectedKeys().hasOnly(['finalDeliveryStatus', 'isEdited', 'editedAt']) ||
  request.resource.data.diff(resource.data).affectedKeys().hasOnly(['deletedFor'])
);
```

**RTDB** (`firebase-rules.json`):
```json
{
  "rules": {
    ".read": "auth != null",
    ".write": "auth != null"
  }
}
```

Note: RTDB rules are currently very permissive. Consider tightening them in the future for better security.

## Next Steps

1. **Test the fix**: Build and run the app to verify deletions persist
2. **Monitor logs**: Check for any errors during deletion operations
3. **Consider RTDB rule improvements**: Add more granular security rules for RTDB
4. **Update documentation**: Ensure all deletion docs reflect the dual-write approach


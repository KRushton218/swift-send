# Deletion Logging Guide

## Overview
Comprehensive logging has been added throughout the deletion flow to help debug and monitor deletion operations in real-time.

## Log Prefixes & Emojis

### Message Deletion
- `🗑️ [DELETE]` - Message deletion operations
- `📝 [DELETE]` - Database write operations
- `✅ [DELETE]` - Successful operations
- `❌ [DELETE]` - Failed operations
- `ℹ️ [DELETE]` - Informational messages

### Conversation Hiding
- `👻 [HIDE]` - Conversation hide operations
- `✅ [HIDE]` - Successful operations
- `❌ [HIDE]` - Failed operations

### Message Observation (Real-time)
- `📨 [OBSERVE]` - New messages added
- `🗑️ [OBSERVE]` - Messages deleted (removed from cache)
- `✏️ [OBSERVE]` - Message content changed
- `🔥 [OBSERVE]` - Message removed from RTDB
- `🚫 [OBSERVE]` - Message filtered (deleted for user)
- `📤 [OBSERVE]` - Emitting updated message list
- `📥 [OBSERVE]` - Initial message load complete

### Message Loading (Historical)
- `📚 [LOAD]` - Loading older messages from Firestore
- `🚫 [LOAD]` - Filtered out deleted messages
- `✅ [LOAD]` - Successfully loaded messages

### ViewModels
- `🗑️ [ChatViewModel]` - Message deletion requested
- `👻 [MainViewModel]` - Conversation hide requested
- `🔍 [MainViewModel]` - Filtering conversations
- `📊 [MainViewModel]` - Conversation count changes

### Firestore Operations
- `📝 [FirestoreManager]` - Firestore operations
- `✅ [FirestoreManager]` - Successful Firestore operations
- `❌ [FirestoreManager]` - Failed Firestore operations

### Message Model
- `🚫 [Message]` - Message deletion check

## Complete Deletion Flow with Logs

### Message Deletion Flow

```
1. User Action (UI)
   └─ Long-press message → Select "Delete"

2. ChatViewModel.deleteMessage()
   🗑️ [ChatViewModel] User requested message deletion
      Message ID: abc123
      Message text: Hello world...

3. MessagingManager.deleteMessageForUser()
   🗑️ [DELETE] Starting message deletion
      User: user123
      Conversation: conv456
      Message: abc123

4. Firestore Update
   📝 [DELETE] Updating Firestore...
   📝 [FirestoreManager] Updating message deletedFor array
      Conversation: conv456
      Message: abc123
      User: user123
   ✅ [FirestoreManager] Firestore message updated successfully
   ✅ [DELETE] Firestore updated successfully

5. RTDB Update
   📝 [DELETE] Updating RTDB...
      Current deletedFor: []
      New deletedFor: ["user123"]
   ✅ [DELETE] RTDB updated successfully
   🎉 [DELETE] Message deletion complete!

6. RTDB Observer Triggered
   🗑️ [OBSERVE] Message deleted, removing from local cache: abc123
      deletedFor: ["user123"]
   📤 [OBSERVE] Emitting updated message list (5 messages)

7. ViewModel Receives Update
   ✅ [ChatViewModel] Message deletion completed

8. UI Updates
   └─ Message disappears from chat
```

### Conversation Hiding Flow

```
1. User Action (UI)
   └─ Swipe conversation → Tap "Delete"

2. MainViewModel.deleteConversation()
   👻 [MainViewModel] User requested conversation hide
      Conversation ID: conv456
      Conversation name: Team Chat

3. MessagingManager.hideConversationForUser()
   👻 [HIDE] Starting conversation hide
      User: user123
      Conversation: conv456
   ✅ [HIDE] Conversation hidden successfully
   🎉 [HIDE] Conversation hide complete!

4. ViewModel Receives Update
   ✅ [MainViewModel] Conversation hide completed

5. Filter Conversations
   🔍 Filtering conversations (current count: 10)
   👻 [MainViewModel] Filtering out hidden conversation: conv456
      ✅ Filtered out 1 hidden conversations
   📊 [MainViewModel] Conversation count: 10 → 9

6. UI Updates
   └─ Conversation disappears from list
```

### Loading Older Messages (with deleted messages)

```
1. User scrolls to top of chat

2. MessagingManager.loadOlderMessages()
   📚 [LOAD] Loading older messages from Firestore
      Conversation: conv456
      Before: 2025-10-24 12:00:00
      Limit: 50
      Retrieved: 50 messages

3. Filtering
   🚫 [LOAD] Filtered out 3 deleted messages
   ✅ [LOAD] Returning 47 messages

4. Messages appear in chat
```

## How to Use These Logs

### Debugging Message Deletion Issues

1. **Check if deletion is initiated:**
   ```
   Look for: 🗑️ [ChatViewModel] User requested message deletion
   ```

2. **Check if Firestore update succeeds:**
   ```
   Look for: ✅ [DELETE] Firestore updated successfully
   If missing: ❌ [DELETE] Firestore update failed: [error]
   ```

3. **Check if RTDB update succeeds:**
   ```
   Look for: ✅ [DELETE] RTDB updated successfully
   If missing: ❌ [DELETE] RTDB update failed: [error]
   ```

4. **Check if observer detects the change:**
   ```
   Look for: 🗑️ [OBSERVE] Message deleted, removing from local cache
   Should show: deletedFor: ["user123"]
   ```

5. **Check if UI updates:**
   ```
   Look for: 📤 [OBSERVE] Emitting updated message list
   Message count should decrease
   ```

### Debugging Conversation Hiding Issues

1. **Check if hide is initiated:**
   ```
   Look for: 👻 [MainViewModel] User requested conversation hide
   ```

2. **Check if RTDB update succeeds:**
   ```
   Look for: ✅ [HIDE] Conversation hidden successfully
   If missing: ❌ [HIDE] Failed to hide conversation: [error]
   ```

3. **Check if filtering happens:**
   ```
   Look for: 🔍 Filtering conversations
   Should show: 👻 [MainViewModel] Filtering out hidden conversation
   ```

4. **Check conversation count:**
   ```
   Look for: 📊 [MainViewModel] Conversation count: X → Y
   Y should be X - 1
   ```

### Common Issues and Their Log Signatures

#### Issue: Message deleted but comes back
**What to look for:**
```
✅ [DELETE] Firestore updated successfully
❌ [DELETE] RTDB update failed: [error]
```
**Problem:** RTDB update failed, so observer doesn't know message is deleted

#### Issue: Message doesn't disappear immediately
**What to look for:**
```
✅ [DELETE] RTDB updated successfully
(Missing) 🗑️ [OBSERVE] Message deleted, removing from local cache
```
**Problem:** Observer not detecting the change or filtering not working

#### Issue: Conversation hidden but still visible
**What to look for:**
```
✅ [HIDE] Conversation hidden successfully
(Missing) 🔍 Filtering conversations
```
**Problem:** Filter not being called after status update

#### Issue: Deleted messages reappear on scroll
**What to look for:**
```
📚 [LOAD] Loading older messages from Firestore
   Retrieved: 50 messages
(Missing) 🚫 [LOAD] Filtered out X deleted messages
```
**Problem:** Firestore messages don't have deletedFor field or filtering not working

## Viewing Logs in Xcode

1. **Open Xcode Console:**
   - View → Debug Area → Show Debug Area
   - Or press: `Cmd + Shift + Y`

2. **Filter logs by operation:**
   - Type `[DELETE]` to see only deletion logs
   - Type `[HIDE]` to see only hide logs
   - Type `[OBSERVE]` to see only observer logs
   - Type `❌` to see only errors

3. **Follow a complete flow:**
   - Clear console before testing
   - Perform deletion action
   - Watch logs appear in sequence
   - Verify each step completes successfully

## Performance Considerations

These logs are verbose and intended for debugging. In production, you may want to:

1. **Reduce log verbosity:**
   - Remove detailed logs from hot paths (observer callbacks)
   - Keep only error logs and critical checkpoints

2. **Use conditional logging:**
   ```swift
   #if DEBUG
   print("🗑️ [DELETE] Starting message deletion")
   #endif
   ```

3. **Use OSLog for production:**
   - Replace `print()` with `Logger` for better performance
   - Already using `Logger` in ViewModels

## Next Steps

1. **Test the deletion flow:**
   - Open Xcode console
   - Delete a message
   - Verify all logs appear in correct order
   - Check for any error messages

2. **Monitor for issues:**
   - Look for missing log entries
   - Check for error messages
   - Verify message counts decrease

3. **Optimize if needed:**
   - Remove verbose logs from frequently called functions
   - Keep error logs and critical checkpoints


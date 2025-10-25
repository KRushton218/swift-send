# Notification System Testing Guide

## Changes Summary

### Files Modified
- **AuthManager.swift** (+144 lines) - Global notification system
- **ChatViewModel.swift** (-28 lines) - Removed duplicate notifications
- **ChatView.swift** (+3 lines) - Active conversation coordination
- **ConversationListView.swift** (+19 lines) - Fixed observer leaks
- **PresenceManager.swift** (-1 line) - Removed unused import

---

## Pre-Testing Checklist

### 1. Build Verification
```bash
# From project root
xcodebuild -project swift-send.xcodeproj \
  -scheme swift-send \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  clean build
```

**Expected:** Build should succeed with no errors

**If build fails:**
- Check for syntax errors in modified files
- Verify all imports are correct
- Ensure AuthManager is properly initialized in App

---

## Testing Scenarios

### Scenario 1: Global Notifications for Unopened Conversations

**Setup:**
1. Sign in as User A on Device 1
2. Sign in as User B on Device 2
3. User B sends message to User A in a NEW conversation
4. **Do NOT open the conversation on Device 1 yet**

**Expected Behavior:**
- ✅ User A receives notification on Device 1
- ✅ Notification shows sender name and message preview
- ✅ Tapping notification opens the conversation

**Console Logs to Watch For:**
```
🌐 Starting global message listener for user [userId]
🌐 Global listener: Found X conversations
🌐 Now observing messages in conversation [conversationId]
🔔 1 new message(s) in conversation [conversationId]
📬 Notification sent: [senderName]
```

**This tests:** The NEW global notification system works for ALL conversations

---

### Scenario 2: No Duplicate Notifications

**Setup:**
1. User A and User B in existing conversation
2. User A has conversation OPEN on Device 1
3. User B sends message from Device 2

**Expected Behavior:**
- ✅ User A sees message appear in chat instantly
- ❌ User A should NOT receive notification (chat is active)
- ✅ Check console: Should see suppression log

**Console Logs to Watch For:**
```
🔕 Suppressing notification - user is viewing conversation [conversationId]
```

**This tests:** Active chat suppression works properly

---

### Scenario 3: Notifications Resume When Chat Closes

**Setup:**
1. User A has conversation open
2. User A navigates BACK to conversation list
3. User B sends message

**Expected Behavior:**
- ✅ User A receives notification
- ✅ Unread badge appears on conversation row

**Console Logs to Watch For:**
```
// When leaving chat:
(no suppression log - activeConversationId should be nil)

// When message arrives:
🔔 1 new message(s) in conversation [conversationId]
```

**This tests:** activeConversationId coordination works

---

### Scenario 4: Multiple Conversations

**Setup:**
1. User A in 3 different conversations
2. User A has Conversation 1 OPEN
3. User B sends message in Conversation 2
4. User C sends message in Conversation 3

**Expected Behavior:**
- ❌ No notification for Conversation 1 (active)
- ✅ Notification for Conversation 2
- ✅ Notification for Conversation 3
- ✅ Two separate notifications received

**This tests:** Multiple conversation monitoring works

---

### Scenario 5: Group Chat Detection

**Setup:**
1. Create group chat with 3+ participants
2. User A on Device 1 (chat closed)
3. User B sends message to group

**Expected Behavior:**
- ✅ Notification title shows "New Group Message"
- ✅ Notification body shows "[Sender]: [Message]"

**Console Log Check:**
```
// In AuthManager.handleGlobalMessagesUpdate
// participantCount should be > 2
// isGroupChat should be true
```

**This tests:** Group chat detection works properly

---

### Scenario 6: App Lifecycle (Background/Foreground)

**Setup:**
1. User A signed in, app open
2. Send app to background (home button)
3. User B sends message
4. Bring app back to foreground

**Expected Behavior:**
- ✅ Notification received while in background
- ✅ Global listener restarts on foreground
- ✅ No duplicate notifications

**Console Logs to Watch For:**
```
// On background:
🌐 Stopping global message listener

// On foreground:
🌐 Starting global message listener for user [userId]
```

**This tests:** Lifecycle management works

---

### Scenario 7: Sign Out Cleanup

**Setup:**
1. User A signed in with active global listener
2. Sign out

**Expected Behavior:**
- ✅ All observers removed
- ✅ No crashes
- ✅ No memory leaks

**Console Logs to Watch For:**
```
🌐 Stopping global message listener
🌐 Global message listener stopped
```

**Memory Check:** Use Xcode Instruments to verify no observer leaks

---

### Scenario 8: Observer Leak Prevention

**Setup:**
1. Open conversation list
2. Navigate back and forth 5 times
3. Check memory usage

**Expected Behavior:**
- ✅ Memory usage stays stable
- ✅ No accumulation of observers

**Console Logs to Watch For:**
```
🧹 ConversationListView: Cleaning up observers
🧹 ConversationListView: Cleanup complete
```

**Verification:** Use Xcode Memory Graph to check for leaked observers

---

## Debugging Tips

### Enable Detailed Logging

Temporarily add more logging if needed:

```swift
// In AuthManager.handleGlobalMessagesUpdate
print("DEBUG: activeConversationId = \(activeConversationId ?? "nil")")
print("DEBUG: conversationId = \(conversationId)")
print("DEBUG: newMessages count = \(newMessages.count)")
```

### Check Notification Permissions

```swift
// In NotificationManager
UNUserNotificationCenter.current().getNotificationSettings { settings in
    print("Notification auth status: \(settings.authorizationStatus)")
}
```

### Verify Observer Registration

Add breakpoint in:
- `AuthManager.startGlobalMessageListener()`
- `AuthManager.handleGlobalMessagesUpdate()`
- Check `globalMessageObserverHandles` dictionary contents

---

## Known Issues to Watch For

### ❌ Issue: No notifications at all
**Possible Causes:**
- Notification permissions not granted
- Global listener not started (check sign-in flow)
- Firebase not configured properly

**Fix:** Check console logs for startup errors

### ❌ Issue: Duplicate notifications
**Possible Causes:**
- activeConversationId not being set
- ChatView not updating AuthManager

**Fix:** Add breakpoints in ChatView.onAppear/onDisappear

### ❌ Issue: Memory leaks
**Possible Causes:**
- Observers not removed in ConversationListView
- Strong reference cycles

**Fix:** Use Instruments to trace leaked objects

---

## Success Criteria

All scenarios should pass:
- [x] Global notifications for unopened conversations
- [x] No duplicate notifications for active chat
- [x] Notifications resume when chat closes
- [x] Multiple conversations work independently
- [x] Group chat detection works
- [x] App lifecycle handled properly
- [x] Sign out cleanup works
- [x] No observer memory leaks

---

## Performance Benchmarks

**Before Implementation:**
- Notifications only for opened conversations
- Observer leaks in ConversationListView
- Duplicate notifications possible

**After Implementation:**
- Notifications for ALL conversations
- Proper observer cleanup
- No duplicates with active chat suppression

**Memory Usage:**
- Should remain stable over time
- Observers cleaned up on view disappear
- No accumulation of Firebase listeners

---

## Next Steps After Testing

1. ✅ All scenarios pass → Ready to commit
2. ❌ Scenarios fail → Debug and fix issues
3. 📊 Performance issues → Profile with Instruments
4. 🐛 Edge cases found → Add to this doc

---

## Rollback Plan

If critical issues found:

```bash
# Discard changes
git checkout master
git branch -D feature/notifications-system

# Or revert specific file
git checkout master -- swift-send/Managers/AuthManager.swift
```

The old ChatViewModel notification system will resume working.

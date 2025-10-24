# Debug Logging Guide

## Overview

Comprehensive debug logging has been added to the unified message view and chat detail view to help troubleshoot issues. All logs use Apple's unified logging system (OSLog) with emoji prefixes for easy scanning.

## Viewing Logs

### Method 1: Xcode Console (Recommended)
1. Run the app from Xcode
2. Open the Console pane (bottom of Xcode window)
3. Filter logs by typing `swift-send` or specific emojis in the search box

### Method 2: Console.app
1. Open Console.app (Applications > Utilities > Console)
2. Select your device/simulator from the left sidebar
3. Filter by process name: `swift-send`
4. Or filter by subsystem: `com.swiftsend.app`

### Method 3: Terminal
```bash
# For simulator
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.swiftsend.app"' --level debug

# For device (requires device name)
idevicesyslog | grep "com.swiftsend.app"
```

## Log Categories

### UnifiedMessageView
- **Category**: `UnifiedMessageView`
- **Tracks**: View lifecycle, user interactions, dismiss events

### UnifiedMessageViewModel
- **Category**: `UnifiedMessageViewModel`
- **Tracks**: Recipient management, conversation detection, message sending, real-time updates

### ChatDetailView
- **Category**: `ChatDetailView`
- **Tracks**: View lifecycle for existing conversations

### ChatViewModel
- **Category**: `ChatViewModel`
- **Tracks**: Message loading, sending, typing indicators, presence

### MainView
- **Category**: `MainView`
- **Tracks**: Sheet presentation state changes

## Log Emoji Guide

| Emoji | Meaning | Example |
|-------|---------|---------|
| 🚀 | Initialization | ViewModel or view initialized |
| 🎬 | View created | View init called |
| 👁️ | View appeared | onAppear triggered |
| 👋 | View disappeared | onDisappear triggered |
| 🔍 | Searching | User search or conversation lookup |
| ➕ | Adding | Adding recipient |
| ➖ | Removing | Removing recipient |
| 👥 | Recipients | Recipient count changed |
| 📥 | Loading | Loading messages or data |
| 📨 | Received | Data received from server |
| 📤 | Sending | Sending message |
| ✅ | Success | Operation completed successfully |
| ❌ | Error/Cancel | Operation failed or cancelled |
| ⚠️ | Warning | Non-critical issue |
| 🔄 | State change | UI state changed |
| 🧹 | Cleanup | Removing observers/listeners |
| 🔇 | Unsubscribe | Removing specific observer |
| 👀 | Observing | Setting up observer |
| 🆕 | Creating | Creating new conversation |
| 📝 | Metadata | Group name or other metadata |
| ℹ️ | Info | General information |

## Common Debugging Scenarios

### Issue: View closes unexpectedly

**What to look for:**
```
🎬 UnifiedMessageView init
👁️ UnifiedMessageView appeared
👋 UnifiedMessageView disappeared - calling cleanup
```

If you see "disappeared" shortly after "appeared" without user action, check:
1. Look for `🔄 showingNewChat changed: true → false` in MainView logs
2. Check if there's an error message just before dismissal
3. Look for any `❌` error logs

### Issue: Messages not loading

**What to look for:**
```
🚀 ChatViewModel initialized for conversation: [ID]
⚙️ Setting up ChatViewModel
📥 Loading messages for conversation: [ID]
📨 Received X messages for conversation
```

If you don't see "Received X messages", check:
1. Firebase connection
2. Conversation ID validity
3. Any error logs between "Loading" and expected "Received"

### Issue: Conversation not detected

**What to look for:**
```
➕ Adding recipient: [Name] ([ID])
👥 Total recipients: X
🔍 Checking for existing conversation with X recipients
🔍 Looking for conversation with members: [IDs]
✅ Found existing conversation: [ID]
```

Or:
```
ℹ️ No existing conversation found - will create new one on first message
```

### Issue: Message not sending

**What to look for:**
```
📤 Sending message to X recipients
📨 Sending to existing conversation: [ID]
✅ Message sent successfully
```

Or for new conversations:
```
🆕 Creating new [type] conversation with X members
✅ Created conversation: [ID]
👀 Starting to observe new conversation
```

## Filtering Tips

### In Xcode Console
- Type `🚀` to see all initializations
- Type `❌` to see all errors
- Type `UnifiedMessage` to see unified message view logs only
- Type `ChatViewModel` to see chat-specific logs

### In Console.app
Create custom filters:
1. Click "+" to add filter
2. Choose "Message" contains "🚀" for init logs
3. Choose "Category" is "UnifiedMessageViewModel" for specific component

## Log Levels

- **Debug** (🔍): Detailed information for troubleshooting
- **Info** (ℹ️): General informational messages
- **Warning** (⚠️): Potential issues that don't stop execution
- **Error** (❌): Errors that need attention

## Performance Considerations

Logging is lightweight and uses OSLog, which:
- Has minimal performance impact
- Automatically compresses logs
- Respects privacy (no sensitive data logged)
- Can be filtered by log level in release builds

## Troubleshooting the "View Closes Itself" Issue

Based on your specific issue where the conversation view closes after a second:

1. **Start the app and open Console.app**
2. **Filter by subsystem**: `com.swiftsend.app`
3. **Tap on the conversation** in the main list
4. **Watch for this sequence**:
   ```
   🎬 ChatDetailView init for conversation: [ID]
   👁️ ChatDetailView appeared for conversation: [ID]
   🚀 ChatViewModel initialized
   ⚙️ Setting up ChatViewModel
   📥 Loading messages
   ```
5. **If the view closes, look for**:
   ```
   👋 ChatDetailView disappeared
   ```
6. **Check what happens between "appeared" and "disappeared"**
   - Is there an error?
   - Is there a state change in MainView?
   - Are messages being loaded?

The logs will show you exactly where the flow breaks down.

## Additional Debug Information

If you need even more detail, you can temporarily change log levels in the code:

```swift
// Change from .info to .debug for more verbose logging
logger.debug("Your message here")

// Change from .debug to .info to see in default view
logger.info("Your message here")
```

## Common Issue: Multiple View Initializations

If you see logs like:
```
👁️ ChatDetailView appeared
🎬 ChatDetailView init
🎬 ChatDetailView init
🎬 ChatDetailView init
👋 ChatDetailView disappeared
```

This means SwiftUI is recreating the view multiple times, which causes navigation to break.

**Root Cause**: The parent view's state (like the conversations array) is changing, causing SwiftUI to think the destination view needs to be recreated.

**Fix Applied**: 
1. Made `Conversation` conform to `Equatable` (comparing by ID only)
2. Added stable `.id()` modifier to NavigationLinks
3. This prevents unnecessary re-initialization when the array is re-sorted or filtered

## Next Steps

After identifying the issue with logs:
1. Note the exact sequence of log messages
2. Look for any `❌` error messages
3. Check the timing between events
4. Look for multiple `🎬 init` calls after `👁️ appeared`
5. Share the relevant log sequence for further analysis

The logs will tell us exactly what's happening when the view closes unexpectedly!


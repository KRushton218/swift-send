# Firebase Setup & Development Guide

## Current Permission Issues

You're encountering two types of errors:

### 1. Firestore Permission Error
```
Error fetching conversations: Missing or insufficient permissions.
12.4.0 - [FirebaseFirestore][I-FST000001] Listen for query at conversations failed: Missing or insufficient permissions.
```

**Cause:** This error is often misleading. It's usually caused by:
- Missing Firestore indexes (most common)
- Or actual permission issues in your Firestore rules

**Solution:** 
- The code has been updated to sort conversations in-memory instead of requiring a server-side index
- If issues persist, deploy Firestore indexes using: `firebase deploy --only firestore:indexes`

### 2. Realtime Database Permission Error
```
❌ Error seeding data: Permission denied
12.4.0 - [FirebaseDatabase][I-RDB038012] setValue: at /conversationMembers/... failed: permission_denied
```

**Cause:** The `MessagingManager` was trying to write all member IDs at once, which doesn't align with your security rules.

**Solution:** Code has been updated to write each member individually, which complies with your security rules.

### Security Rules are Working Correctly!

Your current security rules prevent:
- ✓ Creating user profiles for other users
- ✓ Accessing conversations you're not a member of
- ✓ Writing to paths you don't own

This is **expected behavior** in production - your security is solid!

## Solutions

### Option 1: Modified Data Seeder (Current Implementation)

The DataSeeder has been updated to only create data for the currently authenticated user. This works with production Firebase rules but is limited to single-user testing.

**Pros:**
- Works immediately with production Firebase
- No additional setup required
- Safe for production deployment

**Cons:**
- Can't test multi-user conversations
- Limited testing scenarios

### Option 2: Firebase Local Emulator Suite (Recommended for Development)

The Firebase Emulator Suite lets you test your app locally without affecting production data and bypasses security rules for easier testing.

#### Setup Instructions

1. **Install Firebase CLI:**
   ```bash
   npm install -g firebase-tools
   ```

2. **Login to Firebase:**
   ```bash
   firebase login
   ```

3. **Initialize Emulators:**
   ```bash
   cd /Users/kiranrushton/Desktop/swift-send
   firebase init emulators
   ```
   
   Select:
   - ✓ Authentication Emulator
   - ✓ Firestore Emulator
   - ✓ Realtime Database Emulator
   
   Use default ports or customize as needed.

4. **Start Emulators:**
   ```bash
   firebase emulators:start
   ```

5. **Configure Your App for Emulators:**
   
   In `swift_sendApp.swift`, add this code after `FirebaseApp.configure()`:
   
   ```swift
   #if DEBUG
   // Use emulators for local development
   Auth.auth().useEmulator(withHost: "localhost", port: 9099)
   
   let db = Firestore.firestore()
   let settings = db.settings
   settings.host = "localhost:8080"
   settings.cacheSettings = MemoryCacheSettings()
   settings.isSSLEnabled = false
   db.settings = settings
   
   Database.database().useEmulator(withHost: "localhost", port: 9000)
   #endif
   ```

6. **Benefits:**
   - Test with multiple users without creating real accounts
   - Seed any data you want without permission issues
   - Fast reset between tests
   - No cost for reads/writes
   - Emulator UI at http://localhost:4000

### Option 3: Test with Multiple Real Users

For integration testing with production Firebase:

1. **Create Test Accounts:**
   - Create 2-3 Firebase Auth accounts with real email/password
   - Or use anonymous authentication for quick testing

2. **Test on Multiple Devices/Simulators:**
   - Run the app on different simulators
   - Log in with different accounts
   - Test real multi-user conversations

3. **Clean Up:**
   - Delete test data from Firebase Console when done
   - Or create a cleanup script

## Current Security Rules

Your current rules are secure and production-ready:

### Firestore Rules (`firestore.rules`)
- ✓ Users can only read/write their own profiles
- ✓ Only conversation members can access messages
- ✓ Message senders can edit/delete their own messages

### Realtime Database Rules (`firebase-rules.json`)
- ✓ Presence data is protected per user
- ✓ Conversation access requires membership
- ✓ Typing indicators only writable by the user

## Deploy Firestore Indexes (Important!)

Your app needs certain Firestore indexes to query conversations efficiently. I've created a `firestore.indexes.json` file with the required indexes.

### Deploy Indexes to Firebase:

```bash
firebase deploy --only firestore:indexes
```

This creates indexes for:
- Querying conversations by member IDs
- Sorting messages by timestamp
- Efficient pagination

**Note:** Index creation can take a few minutes. You'll see the progress in Firebase Console.

## Recommended Development Workflow

1. **For Development:**
   - Use Firebase Emulator Suite (Option 2)
   - Seed any data you want for testing
   - Fast iteration without affecting production
   - No need to worry about indexes in emulator mode

2. **For Testing:**
   - Use real Firebase with test accounts (Option 3)
   - Test actual network conditions
   - Verify security rules work correctly
   - **Deploy indexes first** using the command above

3. **For Production:**
   - Use production Firebase with real users
   - Security rules automatically protect data
   - **Ensure indexes are deployed**
   - Current rules are already production-ready

## Next Steps

I recommend setting up the Firebase Emulator Suite (Option 2) for the best development experience. It gives you:
- Freedom to test with mock users
- No permission issues during development
- Local testing without network latency
- Easy data reset between test runs

Let me know if you'd like me to add the emulator configuration to your app!


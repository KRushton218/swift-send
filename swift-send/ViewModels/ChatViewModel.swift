//
//  ChatViewModel.swift
//  swift-send
//
//  MVVM ARCHITECTURE - VIEWMODEL LAYER (Per-conversation)
//  =========================================================
//  ViewModel for a single chat screen. Created per conversation (not a singleton).
//  Bound to ChatView via @StateObject.
//
//  Key Responsibilities:
//  1. Message loading via Firebase observers (real-time updates)
//  2. Optimistic UI for sending messages (show immediately, reconcile with Firebase)
//  3. Offline message queue with auto-retry on reconnection
//  4. Participant presence tracking (online/offline status)
//  5. Typing indicators (debounced to 1 update/sec, auto-clear after 5s)
//  6. Connection monitoring (show offline banner, retry failed messages)
//  7. Read receipts (mark messages as read when viewed)
//
//  Data Flow - Sending:
//  User types → optimistic Message(status: .sending) → pendingMessages queue
//  → Firebase write → observer fires → reconcile (remove from pending) → status: .delivered
//
//  Data Flow - Receiving:
//  Firebase observer fires → messages updated → ChatView re-renders → mark as read
//

import Foundation
import Combine
import FirebaseDatabase

@MainActor
class ChatViewModel: ObservableObject {
    // MARK: - Published State (SwiftUI bindings)

    @Published var messages: [Message] = []  // All messages (Firebase + pending optimistic)
    @Published var messageText: String = ""  // Two-way binding with TextField
    @Published var isLoading = false
    @Published var participantInfo: [ParticipantInfo] = []  // Online status of other users
    @Published var isActive = false  // Set by ChatView.onAppear to suppress notifications
    @Published var typingUsers: [TypingIndicator] = []  // Who's currently typing
    @Published var isConnected: Bool = true  // Firebase connection state (drives offline banner)
    @Published var userPreferences: UserPreferences?  // User preferences for auto-translate

    // MARK: - Immutable State

    let conversationId: String
    let currentUserId: String
    let participants: [String]

    // MARK: - Private State

    private var messagesObserverHandle: DatabaseHandle?
    private var presenceObserverHandles: [String: DatabaseHandle] = [:]
    private var typingObserverHandle: DatabaseHandle?
    private var connectionObserverHandle: DatabaseHandle?
    private let realtimeManager = RealtimeManager.shared
    private let presenceManager = PresenceManager.shared
    private let translationManager = TranslationManager.shared
    private var timerCancellable: AnyCancellable?  // For presence timestamp updates
    private var typingTimer: Timer?  // Auto-clear typing after 5s inactivity
    private var lastTypingUpdate: Date?  // For debouncing
    private let typingDebounceInterval: TimeInterval = 1.0  // Max 1 update/sec
    private let typingTimeoutInterval: TimeInterval = 5.0  // Auto-clear after 5s

    // Offline support: optimistic messages not yet confirmed by Firebase
    private var pendingMessages: [String: Message] = [:]  // messageId: message

    // Track which messages we've already attempted to auto-translate
    private var autoTranslatedMessageIds: Set<String> = []

    // Track when the view was opened to avoid translating old messages
    private let viewOpenedAt: TimeInterval

    /// Initialize ViewModel and start all observers
    /// Note: Each ChatView creates its own ChatViewModel instance
    init(conversationId: String, currentUserId: String, participants: [String]) {
        self.conversationId = conversationId
        self.currentUserId = currentUserId
        self.participants = participants
        self.viewOpenedAt = Date().timeIntervalSince1970 * 1000  // Current timestamp in ms
        loadMessages()  // Firebase observer for real-time message updates
        markMessagesAsRead()  // Mark visible messages as read
        observeParticipantPresence()  // Track online/offline status
        observeTypingIndicators()  // Who's typing
        observeConnectionState()  // Online/offline banner + auto-retry
        startPresenceTimer()  // Update "last seen" timestamps every 1s
        loadUserPreferences()  // Load auto-translate preferences
    }

    // MARK: - Lifecycle & Observer Cleanup
    // CRITICAL: Firebase observers MUST be removed in deinit to prevent memory leaks
    // Pattern: Store DatabaseHandle on registration → Remove in deinit with same path
    // Each observer maintains an active connection to Firebase until explicitly removed

    deinit {
        // Messages observer - most critical, fires on every message update
        if let handle = messagesObserverHandle {
            realtimeManager.removeObserver(handle: handle, path: "conversations/\(conversationId)/messages")
        }

        // Presence observers - one per participant (could be multiple in group chats)
        for (userId, handle) in presenceObserverHandles {
            realtimeManager.removeObserver(handle: handle, path: "presence/\(userId)")
        }

        // Typing observer - monitors conversation-wide typing state
        if let handle = typingObserverHandle {
            realtimeManager.removeObserver(handle: handle, path: "typing/\(conversationId)")
        }

        // Connection observer - Firebase system path for network state
        if let handle = connectionObserverHandle {
            realtimeManager.removeObserver(handle: handle, path: ".info/connected")
        }

        // Combine subscription - presence timer for "last seen" updates
        timerCancellable?.cancel()

        // Local timer - auto-clear typing state after 5s
        typingTimer?.invalidate()

        // Note: Typing state cleared automatically by Firebase onDisconnect handler
        // (set in RealtimeManager.setTyping). We don't call clearTypingState() here to avoid
        // retain cycles from creating Tasks in deinit.
    }

    // MARK: - Firebase Observers (Real-time Updates)
    // Observer Pattern: Register → Store handle → Callback fires on data change → Remove in deinit
    // [weak self] prevents retain cycles (observer callback holds reference to ViewModel)

    /// OPTIMISTIC UI PATTERN - Reconciliation Logic
    /// Observer Lifetime: Created in init → Fires on every message change → Removed in deinit
    /// Firebase observer provides "source of truth" messages.
    /// We merge them with pending optimistic messages that haven't been confirmed yet.
    /// Once Firebase confirms a message (matched by text+sender), remove from pending queue.
    private func loadMessages() {
        // Register observer - returns DatabaseHandle for cleanup
        messagesObserverHandle = realtimeManager.observeMessages(for: conversationId) { [weak self] firebaseMessages in
            guard let self = self else { return }  // Prevent retain cycle
            Task { @MainActor in
                print("📨 Firebase observer fired with \(firebaseMessages.count) messages")
                print("📨 Current pending messages: \(self.pendingMessages.count)")

                var allMessages = firebaseMessages
                var idsToRemoveFromPending: Set<String> = []

                // Reconcile pending messages with Firebase
                for (pendingId, pendingMessage) in self.pendingMessages {
                    // Match by text + sender (timestamps differ: local vs server)
                    let firebaseHasIt = firebaseMessages.contains { fb in
                        fb.text == pendingMessage.text &&
                        fb.senderId == pendingMessage.senderId
                    }

                    if firebaseHasIt {
                        // Confirmed - remove from pending
                        idsToRemoveFromPending.insert(pendingId)
                        print("✅ Pending message '\(pendingMessage.text)' found in Firebase, removing from pending")
                    } else {
                        // Not yet confirmed - keep showing optimistic version
                        allMessages.append(pendingMessage)
                        print("⏳ Pending message '\(pendingMessage.text)' not in Firebase yet, keeping optimistic version")
                    }
                }

                // Clean up confirmed messages
                for id in idsToRemoveFromPending {
                    self.pendingMessages.removeValue(forKey: id)
                }

                // Update UI
                self.messages = allMessages.sorted { $0.timestamp < $1.timestamp }
                print("📨 Final message count: \(self.messages.count), Pending: \(self.pendingMessages.count)")

                await self.markNewMessagesAsRead()
                await self.autoTranslateNewMessages()
            }
        }
    }

    // NOTE: Notification handling is now done globally by AuthManager
    // This eliminates duplicate notifications and ensures notifications
    // work for all conversations, even those not currently open

    private func markNewMessagesAsRead() async {
        for message in messages where !message.isReadBy(userId: currentUserId) && message.senderId != currentUserId {
            do {
                try await realtimeManager.markMessageAsRead(
                    conversationId: conversationId,
                    messageId: message.id,
                    userId: currentUserId
                )
            } catch {
                // Silently fail - non-critical operation
            }
        }
    }
    func markMessagesAsRead() {
        Task {
            do {
                // Find the senderId - it's whoever is NOT the current user
                let otherParticipants = participants.filter { $0 != currentUserId }
                let senderId = otherParticipants.first ?? ""

                try await realtimeManager.markConversationMessagesAsRead(
                    conversationId: conversationId,
                    userId: currentUserId,
                    senderId: senderId
                )
            } catch {
                // Silently fail - non-critical operation
            }
        }
    }

    /// OPTIMISTIC UI PATTERN - Send Flow
    /// 1. Show message immediately with status: .sending
    /// 2. Add to pendingMessages queue
    /// 3. Fire async Firebase write
    /// 4. On success: wait for observer to confirm (reconciliation in loadMessages)
    /// 5. On failure: mark as .failed, user can retry
    func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let text = messageText
        messageText = ""

        Task {
            try? await clearTypingState()
        }

        // Step 1: Create optimistic message (shown immediately)
        let messageId = UUID().uuidString
        let optimisticMessage = Message(
            id: messageId,
            conversationId: conversationId,
            senderId: currentUserId,
            text: text,
            timestamp: Date().timeIntervalSince1970 * 1000,
            status: .sending,
            readBy: [currentUserId: Date().timeIntervalSince1970 * 1000]
        )

        // Step 2: Add to UI and pending queue
        messages.append(optimisticMessage)
        pendingMessages[messageId] = optimisticMessage

        // Step 3: Send to Firebase asynchronously
        Task {
            do {
                _ = try await realtimeManager.sendMessage(
                    conversationId: conversationId,
                    senderId: currentUserId,
                    text: text
                )

                // Success - write queued to Firebase
                // DON'T remove from pending yet - observer will confirm and remove it
                print("✅ Message write queued to Firebase")

            } catch {
                // Failed - mark as .failed, allow retry
                var failedMessage = optimisticMessage
                failedMessage.status = .failed
                pendingMessages[messageId] = failedMessage

                if let index = messages.firstIndex(where: { $0.id == messageId }) {
                    messages[index] = failedMessage
                }

                print("❌ Message failed to send: \(error.localizedDescription)")
            }
        }
    }

    func getReadByNames() async -> [String: String] {
        var names: [String: String] = [:]

        for userId in participants where userId != currentUserId {
            do {
                if let user = try await realtimeManager.getUser(userId: userId) {
                    names[userId] = user.displayName ?? user.email
                }
            } catch {
                // Silently fail - user name will show as Unknown
            }
        }

        return names
    }

    /// Multiple observers pattern: One observer per participant
    /// Store handles in dictionary [userId: DatabaseHandle] for cleanup
    private func observeParticipantPresence() {
        let otherParticipants = participants.filter { $0 != currentUserId }

        for userId in otherParticipants {
            // Each participant gets their own observer watching /presence/{userId}
            let handle = realtimeManager.observePresence(userId: userId) { [weak self] presence in
                guard let self = self else { return }
                Task { @MainActor in
                    await self.updateParticipantInfo(userId: userId, presence: presence)
                }
            }
            // Store handle for cleanup (deinit removes all handles from this dict)
            presenceObserverHandles[userId] = handle
        }
    }

    private func updateParticipantInfo(userId: String, presence: Presence?) async {
        // Get user info
        guard let user = try? await realtimeManager.getUser(userId: userId) else {
            return
        }

        let name = user.displayName ?? user.email
        let isOnline = presence?.isOnline ?? false
        let lastOnline = presence?.lastOnline

        // Create participant info with explicit status
        let info = ParticipantInfo(
            id: userId,
            name: name,
            isOnline: isOnline,
            lastOnline: lastOnline
        )

        // Update or add participant info
        if let index = participantInfo.firstIndex(where: { $0.id == userId }) {
            participantInfo[index] = info
        } else {
            participantInfo.append(info)
        }
    }

    private func startPresenceTimer() {
        // Subscribe to the centralized presence timer
        // Every second, trigger a UI refresh to update "Last seen" text (e.g., "1m ago" → "2m ago")
        timerCancellable = presenceManager.timer
            .sink { [weak self] _ in
                guard let self = self else { return }
                // Force UI update to refresh relative timestamps
                self.objectWillChange.send()
            }
    }

    // MARK: - Lifecycle

    func onViewDisappear() {
        Task {
            try? await clearTypingState()
        }
    }

    // MARK: - Typing Indicators
    // Pattern: Debounced to max 1 update/sec, auto-clear after 5s of inactivity
    // Firebase disconnect handlers auto-clear on app close

    /// Observer watches /typing/{conversationId} for all users typing in this conversation
    /// Lifetime: Created in init → Fires when anyone types → Removed in deinit
    private func observeTypingIndicators() {
        typingObserverHandle = realtimeManager.observeTypingIndicators(conversationId: conversationId) { [weak self] typingIndicators in
            guard let self = self else { return }
            Task { @MainActor in
                // Filter out self (don't show your own typing)
                self.typingUsers = typingIndicators.filter { $0.id != self.currentUserId }
                print("⌨️ Typing indicators updated: \(self.typingUsers.count) users typing")
                for user in self.typingUsers {
                    print("   - \(user.name) is typing")
                }
            }
        }
    }

    /// Called on every keystroke by ChatView.onChange
    /// Debounced to prevent Firebase spam (max 1 update/sec)
    func onMessageTextChanged() {
        resetTypingTimer()  // Reset 5s auto-clear timer

        // Debounce: skip if updated less than 1s ago
        let now = Date()
        if let lastUpdate = lastTypingUpdate,
           now.timeIntervalSince(lastUpdate) < typingDebounceInterval {
            print("⌨️ Typing update debounced (too soon)")
            return
        }

        lastTypingUpdate = now

        Task {
            guard let userName = await getUserDisplayName() else {
                print("⌨️ Could not get user display name for typing indicator")
                return
            }
            let isTyping = !messageText.isEmpty
            print("⌨️ Sending typing indicator: \(userName) isTyping=\(isTyping)")
            try? await realtimeManager.setTyping(
                conversationId: conversationId,
                userId: currentUserId,
                name: userName,
                isTyping: isTyping
            )
        }
    }

    private func clearTypingState() async {
        guard let userName = await getUserDisplayName() else { return }
        try? await realtimeManager.setTyping(
            conversationId: conversationId,
            userId: currentUserId,
            name: userName,
            isTyping: false
        )
        typingTimer?.invalidate()
        typingTimer = nil
        lastTypingUpdate = nil
    }

    /// Auto-clear typing state after 5s of inactivity
    private func resetTypingTimer() {
        typingTimer?.invalidate()
        typingTimer = Timer.scheduledTimer(withTimeInterval: typingTimeoutInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.clearTypingState()
            }
        }
    }

    private func getUserDisplayName() async -> String? {
        guard let user = try? await realtimeManager.getUser(userId: currentUserId) else {
            return nil
        }
        return user.displayName ?? user.email
    }

    // MARK: - Connection Monitoring & Message Retry
    // Pattern: Monitor Firebase connection state → show offline banner → auto-retry on reconnect

    /// Special Firebase system observer watching /.info/connected
    /// Lifetime: Created in init → Fires on connection state change → Removed in deinit
    /// Triggers auto-retry of failed messages when connection restored
    private func observeConnectionState() {
        connectionObserverHandle = realtimeManager.observeConnectionState { [weak self] connected in
            guard let self = self else { return }
            Task { @MainActor in
                self.isConnected = connected  // Drives offline banner in ChatView
                print("🌐 Connection state: \(connected ? "✅ Online" : "❌ Offline")")

                // Auto-retry all pending messages when reconnected
                if connected {
                    await self.retryPendingMessages()
                }
            }
        }
    }

    private func retryPendingMessages() async {
        guard !pendingMessages.isEmpty else { return }

        print("🔄 Retrying \(pendingMessages.count) pending messages")

        for (messageId, var message) in pendingMessages {
            do {
                // Try to send the message
                _ = try await realtimeManager.sendMessage(
                    conversationId: conversationId,
                    senderId: currentUserId,
                    text: message.text
                )

                // Success - remove from pending queue
                pendingMessages.removeValue(forKey: messageId)
                print("✅ Message \(messageId) sent successfully")

            } catch {
                // Still failed - mark as failed
                message.status = .failed
                pendingMessages[messageId] = message

                // Update UI
                if let index = messages.firstIndex(where: { $0.id == messageId }) {
                    messages[index] = message
                }

                print("❌ Message \(messageId) failed to send: \(error.localizedDescription)")
            }
        }
    }

    func retryMessage(_ message: Message) {
        Task {
            var updatedMessage = message
            updatedMessage.status = .sending

            // Update UI immediately
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index] = updatedMessage
            }

            do {
                // Try to send
                _ = try await realtimeManager.sendMessage(
                    conversationId: conversationId,
                    senderId: currentUserId,
                    text: message.text
                )

                // Success - remove from pending queue
                pendingMessages.removeValue(forKey: message.id)
                print("✅ Retry successful for message \(message.id)")

            } catch {
                // Failed again
                updatedMessage.status = .failed
                pendingMessages[message.id] = updatedMessage

                if let index = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[index] = updatedMessage
                }

                print("❌ Retry failed for message \(message.id): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Auto-Translation
    // Load user preferences for auto-translate feature

    private func loadUserPreferences() {
        Task {
            do {
                let prefs = try await realtimeManager.getUserPreferences(userId: currentUserId)
                await MainActor.run {
                    self.userPreferences = prefs
                    print("✅ User preferences loaded: autoTranslate=\(prefs?.autoTranslate ?? false), preferredLanguage=\(prefs?.preferredLanguage ?? "unknown")")
                }
            } catch {
                print("⚠️ Failed to load user preferences: \(error.localizedDescription)")
            }
        }
    }

    /// Auto-translate new messages from other users if enabled
    /// Called after messages are updated in the observer
    private func autoTranslateNewMessages() async {
        // Check if auto-translate is enabled
        guard let preferences = userPreferences, preferences.autoTranslate else {
            return
        }

        let preferredLang = preferences.preferredLanguage

        // Find messages that need auto-translation:
        // 1. From other users (not current user)
        // 2. Arrived AFTER the view opened (to avoid rate limiting on old messages)
        // 3. Not already translated
        // 4. Not already attempted to translate
        let messagesToTranslate = messages.filter { message in
            message.senderId != currentUserId &&
            message.timestamp >= viewOpenedAt &&
            !message.hasTranslation &&
            translationManager.translations[message.id] == nil &&
            !autoTranslatedMessageIds.contains(message.id)
        }

        guard !messagesToTranslate.isEmpty else {
            return
        }

        print("🌍 Auto-translating \(messagesToTranslate.count) new messages to \(preferredLang)")

        // Translate each message
        for message in messagesToTranslate {
            // Mark as attempted to avoid re-trying
            autoTranslatedMessageIds.insert(message.id)

            do {
                try await translationManager.translateMessage(message, to: preferredLang, userId: currentUserId)
                print("✅ Auto-translated message \(message.id)")
            } catch {
                print("⚠️ Failed to auto-translate message \(message.id): \(error.localizedDescription)")
            }
        }
    }
}

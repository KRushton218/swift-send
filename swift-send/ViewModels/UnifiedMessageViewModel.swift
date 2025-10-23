//
//  UnifiedMessageViewModel.swift
//  swift-send
//
//  Created on 10/23/25.
//  ViewModel for unified message view - handles recipient selection,
//  conversation preview, and message sending in a single flow.
//

import Foundation
import FirebaseAuth
import FirebaseDatabase
import FirebaseFirestore

@MainActor
class UnifiedMessageViewModel: ObservableObject {
    // MARK: - Published Properties
    
    // Recipient management
    @Published var selectedRecipients: [UserProfile] = []
    @Published var searchText = ""
    @Published var searchResults: [UserProfile] = []
    @Published var isSearching = false
    
    // Conversation state
    @Published var existingConversation: Conversation?
    @Published var messages: [Message] = []
    @Published var isLoadingMessages = false
    @Published var isCheckingConversation = false
    
    // Message composition
    @Published var messageText = ""
    @Published var groupName = ""
    @Published var isSending = false
    
    // Typing and presence
    @Published var typingUsers: [String] = []
    @Published var onlineMembers: Set<String> = []
    
    // Error handling
    @Published var errorMessage = ""
    
    // MARK: - Private Properties
    
    private let currentUserId: String
    private let userProfileManager = UserProfileManager()
    private let messagingManager = MessagingManager()
    private let firestoreManager = FirestoreManager()
    private let presenceManager = PresenceManager()
    
    private var messageObserverHandle: DatabaseHandle?
    private var typingObserverHandle: DatabaseHandle?
    private var conversationListener: ListenerRegistration?
    private var presenceObservers: [String: DatabaseHandle] = [:]
    
    // MARK: - Initialization
    
    init(currentUserId: String) {
        self.currentUserId = currentUserId
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Recipient Management
    
    /// Search for users by name or email
    func searchUsers(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        errorMessage = ""
        
        Task {
            do {
                let results = try await userProfileManager.searchUsers(query: query, limit: 20)
                // Filter out current user and already selected recipients
                let filtered = results.filter { user in
                    user.id != currentUserId && !selectedRecipients.contains(where: { $0.id == user.id })
                }
                
                searchResults = filtered
                isSearching = false
            } catch {
                errorMessage = "Search failed: \(error.localizedDescription)"
                isSearching = false
            }
        }
    }
    
    /// Add a recipient to the selection
    func addRecipient(_ user: UserProfile) {
        guard !selectedRecipients.contains(where: { $0.id == user.id }) else { return }
        guard user.id != currentUserId else { return }
        
        selectedRecipients.append(user)
        searchText = ""
        searchResults = []
        
        // Check for existing conversation with new recipient set
        checkForExistingConversation()
    }
    
    /// Add recipient by email address
    func addRecipientByEmail(_ email: String) {
        errorMessage = ""
        
        Task {
            do {
                guard let user = try await userProfileManager.findUserByEmail(email: email) else {
                    errorMessage = "No user found with email: \(email)"
                    return
                }
                
                addRecipient(user)
            } catch {
                errorMessage = "Error looking up user: \(error.localizedDescription)"
            }
        }
    }
    
    /// Remove a recipient from the selection
    func removeRecipient(_ user: UserProfile) {
        selectedRecipients.removeAll { $0.id == user.id }
        
        // Re-check for existing conversation with updated recipient set
        checkForExistingConversation()
    }
    
    /// Check if email format is valid
    func isValidEmail(_ string: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: string)
    }
    
    // MARK: - Conversation Management
    
    /// Check if conversation already exists with selected recipients
    private func checkForExistingConversation() {
        guard !selectedRecipients.isEmpty else {
            existingConversation = nil
            messages = []
            cleanup()
            return
        }
        
        isCheckingConversation = true
        errorMessage = ""
        
        Task {
            do {
                // Build member IDs list
                var memberIds = [currentUserId]
                memberIds.append(contentsOf: selectedRecipients.map { $0.id })
                
                // Check if conversation exists
                let existing = try await messagingManager.findConversationByParticipants(memberIds: memberIds)
                
                existingConversation = existing
                isCheckingConversation = false
                
                // If conversation exists, load messages
                if let conversation = existing {
                    loadConversationPreview(conversationId: conversation.id ?? "")
                } else {
                    messages = []
                    cleanup()
                }
            } catch {
                errorMessage = "Error checking conversations: \(error.localizedDescription)"
                isCheckingConversation = false
            }
        }
    }
    
    /// Load conversation preview (messages + real-time updates)
    private func loadConversationPreview(conversationId: String) {
        isLoadingMessages = true
        
        // Clean up any existing observers
        cleanup()
        
        // Observe messages in real-time
        messageObserverHandle = messagingManager.observeActiveMessages(
            conversationId: conversationId,
            limit: 50
        ) { [weak self] messages in
            guard let self = self else { return }
            Task { @MainActor in
                self.messages = messages
                self.isLoadingMessages = false
            }
        }
        
        // Setup typing indicators
        setupTypingIndicators(conversationId: conversationId)
        
        // Setup presence monitoring
        setupPresenceMonitoring(conversationId: conversationId)
    }
    
    // MARK: - Message Sending
    
    /// Send message (creates conversation if needed)
    func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !selectedRecipients.isEmpty else {
            errorMessage = "Please select at least one recipient"
            return
        }
        
        isSending = true
        errorMessage = ""
        
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Task {
            do {
                if let conversation = existingConversation, let conversationId = conversation.id {
                    // Send to existing conversation
                    _ = try await messagingManager.sendMessage(
                        conversationId: conversationId,
                        text: trimmedMessage,
                        type: .text
                    )
                } else {
                    // Create new conversation and send first message
                    var memberIds = [currentUserId]
                    memberIds.append(contentsOf: selectedRecipients.map { $0.id })
                    
                    let type: ConversationType = selectedRecipients.count > 1 ? .group : .direct
                    let finalGroupName: String? = selectedRecipients.count > 1 
                        ? (groupName.isEmpty ? autoGeneratedGroupName : groupName) 
                        : nil
                    
                    let (conversationId, _) = try await messagingManager.createConversationAndSendMessage(
                        type: type,
                        name: finalGroupName,
                        memberIds: memberIds,
                        createdBy: currentUserId,
                        messageText: trimmedMessage
                    )
                    
                    // Fetch the created conversation
                    let conversation = try await firestoreManager.getConversation(id: conversationId)
                    existingConversation = conversation
                    
                    // Start observing the new conversation
                    if let conversation = conversation {
                        loadConversationPreview(conversationId: conversation.id ?? "")
                    }
                }
                
                // Clear message text
                messageText = ""
                isSending = false
            } catch {
                errorMessage = "Failed to send message: \(error.localizedDescription)"
                isSending = false
            }
        }
    }
    
    /// Handle text changes for typing indicator
    func onTextChanged(_ newValue: String) {
        guard let conversationId = existingConversation?.id else { return }
        
        Task {
            if !newValue.isEmpty {
                try? await presenceManager.setTypingIndicator(
                    conversationId: conversationId,
                    isTyping: true
                )
            } else {
                try? await presenceManager.clearTypingIndicator(conversationId: conversationId)
            }
        }
    }
    
    // MARK: - Typing Indicators
    
    private func setupTypingIndicators(conversationId: String) {
        typingObserverHandle = presenceManager.observeTypingIndicators(
            conversationId: conversationId
        ) { [weak self] typingUserIds in
            guard let self = self else { return }
            Task { @MainActor in
                // Filter out current user
                self.typingUsers = typingUserIds.filter { $0 != self.currentUserId }
            }
        }
    }
    
    // MARK: - Presence Monitoring
    
    private func setupPresenceMonitoring(conversationId: String) {
        guard let conversation = existingConversation else { return }
        
        // Observe presence for each member
        for memberId in conversation.memberIds where memberId != currentUserId {
            let handle = presenceManager.observePresence(userId: memberId) { [weak self] isOnline in
                guard let self = self else { return }
                Task { @MainActor in
                    if isOnline {
                        self.onlineMembers.insert(memberId)
                    } else {
                        self.onlineMembers.remove(memberId)
                    }
                }
            }
            presenceObservers[memberId] = handle
        }
    }
    
    // MARK: - Computed Properties
    
    var isGroupChat: Bool {
        selectedRecipients.count > 1
    }
    
    var autoGeneratedGroupName: String {
        let names = selectedRecipients.map { $0.displayName }
        let joined = names.joined(separator: ", ")
        if joined.count > 40 {
            return String(joined.prefix(37)) + "..."
        }
        return joined
    }
    
    var conversationTitle: String {
        if let conversation = existingConversation {
            if conversation.type == .group {
                return conversation.name ?? autoGeneratedGroupName
            } else {
                // Direct chat - show other person's name
                let otherMemberId = conversation.memberIds.first { $0 != currentUserId }
                if let otherMemberId = otherMemberId,
                   let memberDetail = conversation.memberDetails[otherMemberId] {
                    return memberDetail.displayName
                }
            }
        }
        
        // New conversation
        if selectedRecipients.count == 1 {
            return selectedRecipients[0].displayName
        } else if selectedRecipients.count > 1 {
            return groupName.isEmpty ? autoGeneratedGroupName : groupName
        }
        
        return "New Message"
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        // Remove message observer
        if let handle = messageObserverHandle,
           let conversationId = existingConversation?.id {
            messagingManager.removeMessageObserver(conversationId: conversationId, handle: handle)
            messageObserverHandle = nil
        }
        
        // Remove typing observer
        if let handle = typingObserverHandle,
           let conversationId = existingConversation?.id {
            presenceManager.removeTypingObserver(conversationId: conversationId, handle: handle)
            typingObserverHandle = nil
        }
        
        // Remove presence observers
        for (userId, handle) in presenceObservers {
            presenceManager.removePresenceObserver(userId: userId, handle: handle)
        }
        presenceObservers.removeAll()
        
        // Remove conversation listener
        conversationListener?.remove()
        conversationListener = nil
    }
}


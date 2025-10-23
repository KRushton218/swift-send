//
//  UnifiedMessageView.swift
//  swift-send
//
//  Created on 10/23/25.
//  Unified single-screen message composition view.
//  Combines recipient selection, conversation preview, and message sending.
//

import SwiftUI
import OSLog

/// Unified message view - single screen for entire new message flow
/// Replaces the multi-step wizard (RecipientSelection → Compose → ChatDetail)
struct UnifiedMessageView: View {
    let currentUserId: String
    @StateObject private var viewModel: UnifiedMessageViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isRecipientFieldFocused: Bool
    @FocusState private var isMessageFieldFocused: Bool
    
    private let logger = Logger(subsystem: "com.swiftsend.app", category: "UnifiedMessageView")
    
    init(currentUserId: String) {
        self.currentUserId = currentUserId
        _viewModel = StateObject(wrappedValue: UnifiedMessageViewModel(currentUserId: currentUserId))
        Logger(subsystem: "com.swiftsend.app", category: "UnifiedMessageView").info("🎬 UnifiedMessageView init for user: \(currentUserId)")
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                recipientSection
                conversationPreviewSection
                errorSection
                groupNameSection
                messageInputSection
            }
            .navigationTitle(viewModel.conversationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        logger.info("❌ Cancel button tapped - dismissing view")
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isSending {
                        ProgressView()
                    }
                }
            }
            .onChange(of: viewModel.searchText) { newValue in
                viewModel.searchUsers(query: newValue)
            }
            .onChange(of: hasSelectedRecipients) { hasRecipients in
                if !hasRecipients {
                    isRecipientFieldFocused = true
                    isMessageFieldFocused = false
                }
            }
            .onChange(of: viewModel.existingConversation != nil) { hasConversation in
                if hasConversation {
                    isRecipientFieldFocused = false
                    isMessageFieldFocused = true
                }
            }
            .onAppear {
                logger.info("👁️ UnifiedMessageView appeared")
                isRecipientFieldFocused = true
            }
            .onDisappear {
                logger.info("👋 UnifiedMessageView disappeared - calling cleanup")
                viewModel.cleanup()
            }
        }
    }
    
    // MARK: - Sections
    
    @ViewBuilder
    private var recipientSection: some View {
        if shouldShowRecipientSelector {
            RecipientSelectorBar(
                searchText: $viewModel.searchText,
                selectedRecipients: $viewModel.selectedRecipients,
                searchResults: viewModel.searchResults,
                isSearching: viewModel.isSearching,
                onAddRecipient: { user in
                    viewModel.addRecipient(user)
                },
                onRemoveRecipient: { user in
                    viewModel.removeRecipient(user)
                },
                onAddByEmail: { email in
                    viewModel.addRecipientByEmail(email)
                },
                isValidEmail: { email in
                    viewModel.isValidEmail(email)
                },
                focus: $isRecipientFieldFocused
            )
            .frame(maxHeight: 300)
        } else {
            collapsedRecipientBar
        }
    }
    
    @ViewBuilder
    private var conversationPreviewSection: some View {
        if hasSelectedRecipients {
            ConversationPreviewArea(
                messages: viewModel.messages,
                conversation: viewModel.existingConversation,
                typingUsers: viewModel.typingUsers,
                isLoadingMessages: viewModel.isLoadingMessages,
                selectedRecipients: viewModel.selectedRecipients,
                onStarMessage: { message in
                    starMessage(message)
                },
                onDeleteMessage: { message in
                    deleteMessage(message)
                }
            )
        }
    }
    
    @ViewBuilder
    private var errorSection: some View {
        if !viewModel.errorMessage.isEmpty {
            Text(viewModel.errorMessage)
                .font(.caption)
                .foregroundColor(.red)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.1))
        }
    }
    
    @ViewBuilder
    private var groupNameSection: some View {
        if viewModel.isGroupChat && viewModel.existingConversation == nil {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Group Name (Optional)", text: $viewModel.groupName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                
                Text("Leave blank to use: \(viewModel.autoGeneratedGroupName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
    }
    
    private var messageInputSection: some View {
        MessageInputView(
            messageText: $viewModel.messageText,
            isSendEnabled: hasSelectedRecipients,
            onSend: {
                viewModel.sendMessage()
            },
            onTextChanged: { newValue in
                viewModel.onTextChanged(newValue)
            },
            focus: $isMessageFieldFocused
        )
    }
    
    private var shouldShowRecipientSelector: Bool {
        viewModel.existingConversation == nil || viewModel.selectedRecipients.isEmpty
    }
    
    private var hasSelectedRecipients: Bool {
        !viewModel.selectedRecipients.isEmpty
    }
    
    // MARK: - Collapsed Recipient Bar
    
    /// Shows a collapsed view of recipients when conversation is active
    private var collapsedRecipientBar: some View {
        HStack {
            Text("To:")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.selectedRecipients) { recipient in
                        HStack(spacing: 6) {
                            ProfilePictureView(photoURL: recipient.photoURL, size: 24)
                            Text(recipient.displayName)
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(16)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.gray.opacity(0.3)),
            alignment: .bottom
        )
    }
    
    // MARK: - Message Actions
    
    private func starMessage(_ message: Message) {
        guard let conversationId = viewModel.existingConversation?.id else { return }
        
        Task {
            do {
                try await MessagingManager().starMessage(
                    userId: currentUserId,
                    messageId: message.id,
                    conversationId: conversationId,
                    conversationTitle: viewModel.conversationTitle,
                    messageText: message.text,
                    senderId: message.senderId,
                    senderName: message.senderName
                )
            } catch {
                print("Error starring message: \(error)")
            }
        }
    }
    
    private func deleteMessage(_ message: Message) {
        guard let conversationId = viewModel.existingConversation?.id else { return }
        
        Task {
            do {
                try await MessagingManager().deleteMessageForUser(
                    conversationId: conversationId,
                    messageId: message.id
                )
            } catch {
                print("Error deleting message: \(error)")
            }
        }
    }
}

#Preview {
    UnifiedMessageView(currentUserId: "test-user")
}

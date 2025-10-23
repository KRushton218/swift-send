//
//  ConversationPreviewArea.swift
//  swift-send
//
//  Created on 10/23/25.
//  Shows message preview or empty state for new conversations.
//

import SwiftUI
import FirebaseAuth

/// Conversation preview area
/// Shows messages if conversation exists, or empty state for new conversations
struct ConversationPreviewArea: View {
    let messages: [Message]
    let conversation: Conversation?
    let typingUsers: [String]
    let isLoadingMessages: Bool
    let selectedRecipients: [UserProfile]
    let onStarMessage: (Message) -> Void
    let onDeleteMessage: (Message) -> Void
    
    var body: some View {
        ScrollView {
            if isLoadingMessages {
                // Loading state
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if messages.isEmpty {
                // Empty state for new conversation
                emptyStateView
            } else {
                // Message list
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        MessageBubble(
                            message: message,
                            isFromCurrentUser: message.isFromCurrentUser(userId: Auth.auth().currentUser?.uid ?? ""),
                            conversation: conversation,
                            onStarMessage: {
                                onStarMessage(message)
                            },
                            onDeleteMessage: {
                                onDeleteMessage(message)
                            }
                        )
                    }
                    
                    // Typing indicator
                    if !typingUsers.isEmpty {
                        TypingIndicatorView(typingUserIds: typingUsers, conversation: conversation)
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - Empty State
    
    /// Empty state for new conversations
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // Show recipient avatars
            if !selectedRecipients.isEmpty {
                HStack(spacing: -10) {
                    ForEach(selectedRecipients.prefix(3)) { recipient in
                        ProfilePictureView(photoURL: recipient.photoURL, size: 60)
                            .overlay(
                                Circle()
                                    .stroke(Color(.systemBackground), lineWidth: 2)
                            )
                    }
                    
                    if selectedRecipients.count > 3 {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.2))
                                .frame(width: 60, height: 60)
                            
                            Text("+\(selectedRecipients.count - 3)")
                                .font(.headline)
                                .foregroundColor(.blue)
                        }
                        .overlay(
                            Circle()
                                .stroke(Color(.systemBackground), lineWidth: 2)
                        )
                    }
                }
                .padding(.bottom, 8)
            }
            
            // Empty state message
            VStack(spacing: 8) {
                Text("Start a conversation")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if selectedRecipients.count == 1 {
                    Text("Say hi to \(selectedRecipients[0].displayName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else if selectedRecipients.count > 1 {
                    Text("Send your first message to the group")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("Add recipients to get started")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


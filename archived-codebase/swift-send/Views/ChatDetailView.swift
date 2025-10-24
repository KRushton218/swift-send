//
//  ChatDetailView.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//  Updated on 10/23/25 to use extracted reusable components.
//

import SwiftUI
import FirebaseAuth
import OSLog

struct ChatDetailView: View {
    let conversation: Conversation
    let currentUserId: String
    @StateObject private var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var showInfoSheet = false
    
    private let logger = Logger(subsystem: "com.swiftsend.app", category: "ChatDetailView")
    
    init(conversation: Conversation, userId: String) {
        self.conversation = conversation
        self.currentUserId = userId
        _viewModel = StateObject(wrappedValue: ChatViewModel(conversationId: conversation.id ?? "", userId: userId))
        Logger(subsystem: "com.swiftsend.app", category: "ChatDetailView").info("🎬 ChatDetailView init for conversation: \(conversation.id ?? "unknown")")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Load more button at top
                        if !viewModel.messages.isEmpty {
                            if viewModel.hasMoreMessages {
                                Button("Load Earlier Messages") {
                                    viewModel.loadOlderMessages()
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                            } else {
                                Text("No Earlier Messages Available")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 8)
                            }
                        }
                        
                        ForEach(viewModel.messages) { message in
                            MessageBubble(
                                message: message,
                                isFromCurrentUser: message.isFromCurrentUser(userId: Auth.auth().currentUser?.uid ?? ""),
                                conversation: viewModel.conversation,
                                onStarMessage: {
                                    viewModel.starMessage(message)
                                },
                                onDeleteMessage: {
                                    viewModel.deleteMessage(message)
                                }
                            )
                            .id(message.id)
                        }
                        
                        // Typing indicator
                        if !viewModel.typingUsers.isEmpty {
                            TypingIndicatorView(typingUserIds: viewModel.typingUsers, conversation: viewModel.conversation)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) {
                    // Scroll to bottom when new message arrives
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Message Input
            MessageInputView(
                messageText: $viewModel.messageText,
                onSend: viewModel.sendMessage,
                onTextChanged: viewModel.onTextChanged
            )
        }
        .navigationTitle(getConversationDisplayName())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if conversation.type == .group {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showInfoSheet = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showInfoSheet) {
            if let activeConversation = viewModel.conversation ?? Optional(conversation) {
                GroupChatInfoView(
                    conversation: activeConversation,
                    currentUserId: currentUserId
                ) {
                    Task {
                        viewModel.loadConversation()
                    }
                }
            }
        }
        .onAppear {
            logger.info("👁️ ChatDetailView appeared for conversation: \(self.conversation.id ?? "unknown")")
            viewModel.setup()
        }
        .onDisappear {
            logger.info("👋 ChatDetailView disappeared for conversation: \(self.conversation.id ?? "unknown")")
            viewModel.cleanup()
        }
    }
    
    private func getConversationDisplayName() -> String {
        // Use the safe display name from the ViewModel's conversation (which can be updated)
        // Fall back to the original conversation if viewModel.conversation is nil
        let activeConversation = viewModel.conversation ?? conversation
        return activeConversation.safeDisplayName(currentUserId: currentUserId)
    }
}

#Preview {
    NavigationView {
        ChatDetailView(
            conversation: Conversation(
                id: "1",
                type: .direct,
                name: nil,
                createdBy: "user1",
                memberIds: ["user1", "user2"],
                memberDetails: [
                    "user2": Conversation.MemberDetail(displayName: "John Doe")
                ]
            ),
            userId: "user1"
        )
    }
}


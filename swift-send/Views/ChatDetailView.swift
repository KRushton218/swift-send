//
//  ChatDetailView.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//  Updated on 10/23/25 to use extracted reusable components.
//

import SwiftUI
import FirebaseAuth

struct ChatDetailView: View {
    let conversation: Conversation
    let currentUserId: String
    @StateObject private var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(conversation: Conversation, userId: String) {
        self.conversation = conversation
        self.currentUserId = userId
        _viewModel = StateObject(wrappedValue: ChatViewModel(conversationId: conversation.id ?? "", userId: userId))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Load more button at top
                        if !viewModel.messages.isEmpty {
                            Button("Load Earlier Messages") {
                                viewModel.loadOlderMessages()
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
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
        .onAppear {
            viewModel.setup()
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }
    
    private func getConversationDisplayName() -> String {
        if conversation.type == .group {
            return conversation.name ?? "Group Chat"
        } else {
            // For direct chats, show the other person's name
            let otherMemberId = conversation.memberIds.first { $0 != currentUserId }
            if let otherMemberId = otherMemberId,
               let memberDetail = conversation.memberDetails[otherMemberId] {
                return memberDetail.displayName
            }
            return "Chat"
        }
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


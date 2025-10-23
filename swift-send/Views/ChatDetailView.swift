//
//  ChatDetailView.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
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

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: Message
    let isFromCurrentUser: Bool
    let conversation: Conversation?
    let onStarMessage: () -> Void
    let onDeleteMessage: () -> Void
    
    var senderPhotoURL: String? {
        if !isFromCurrentUser {
            return conversation?.memberDetails[message.senderId]?.photoURL
        }
        return nil
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isFromCurrentUser { Spacer() }
            
            // Profile picture for other users
            if !isFromCurrentUser {
                ProfilePictureView(photoURL: senderPhotoURL, size: 32)
            }
            
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // Show sender name in group chats
                if !isFromCurrentUser && conversation?.type == .group {
                    Text(message.senderName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
                
                if message.type == .actionItem {
                    // Action Item Message
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text(message.text)
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(16)
                } else if message.type == .system {
                    // System Message
                    Text(message.text)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                } else {
                    // Regular Text Message
                    VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                        Text(message.text)
                            .padding(12)
                            .background(isFromCurrentUser ? Color.blue : Color.gray.opacity(0.2))
                            .foregroundColor(isFromCurrentUser ? .white : .primary)
                            .cornerRadius(16)
                            .contextMenu {
                                Button {
                                    onStarMessage()
                                } label: {
                                    Label("Star Message", systemImage: "star.fill")
                                }
                                
                                Button {
                                    UIPasteboard.general.string = message.text
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                
                                if isFromCurrentUser {
                                    Button(role: .destructive) {
                                        onDeleteMessage()
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        
                        // Delivery/read status for current user's messages
                        if isFromCurrentUser, let readBy = message.readBy {
                            HStack(spacing: 4) {
                                if readBy.count > 1 {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                } else {
                                    Image(systemName: "checkmark")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                                Text(message.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text(message.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Spacer for current user's messages
            if isFromCurrentUser {
                if let currentUserProfile = conversation?.memberDetails[message.senderId] {
                    ProfilePictureView(photoURL: currentUserProfile.photoURL, size: 32)
                } else {
                    ProfilePictureView(size: 32)
                }
            }
            
            if !isFromCurrentUser { Spacer() }
        }
    }
}

// MARK: - Typing Indicator View
struct TypingIndicatorView: View {
    let typingUserIds: [String]
    let conversation: Conversation?
    
    var typingText: String {
        guard let conversation = conversation else { return "Someone is typing..." }
        
        let typingNames = typingUserIds.compactMap { userId in
            conversation.memberDetails[userId]?.displayName
        }
        
        if typingNames.isEmpty {
            return "Someone is typing..."
        } else if typingNames.count == 1 {
            return "\(typingNames[0]) is typing..."
        } else if typingNames.count == 2 {
            return "\(typingNames[0]) and \(typingNames[1]) are typing..."
        } else {
            return "\(typingNames.count) people are typing..."
        }
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ProfilePictureView(size: 32)
            
            HStack(spacing: 4) {
                Text(typingText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Animated dots
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 6, height: 6)
                        .opacity(0.5)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: typingUserIds.count
                        )
                }
            }
            .padding(12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(16)
            
            Spacer()
        }
    }
}

// MARK: - Profile Picture View
struct ProfilePictureView: View {
    let photoURL: String?
    let size: CGFloat
    
    init(photoURL: String? = nil, size: CGFloat = 40) {
        self.photoURL = photoURL
        self.size = size
    }
    
    var body: some View {
        Group {
            if let urlString = photoURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        defaultProfileImage
                    @unknown default:
                        defaultProfileImage
                    }
                }
            } else {
                defaultProfileImage
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1))
    }
    
    private var defaultProfileImage: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .foregroundColor(.gray)
    }
}

// MARK: - Message Input View
struct MessageInputView: View {
    @Binding var messageText: String
    let onSend: () -> Void
    let onTextChanged: ((String) -> Void)?
    
    init(messageText: Binding<String>, onSend: @escaping () -> Void, onTextChanged: ((String) -> Void)? = nil) {
        self._messageText = messageText
        self.onSend = onSend
        self.onTextChanged = onTextChanged
    }
    
    var body: some View {
        HStack(spacing: 12) {
            TextField("Message", text: $messageText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .onChange(of: messageText) { oldValue, newValue in
                    onTextChanged?(newValue)
                }
            
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.gray.opacity(0.3)),
            alignment: .top
        )
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


//
//  ChatDetailView.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//

import SwiftUI
import FirebaseAuth

struct ChatDetailView: View {
    let chat: Chat
    @StateObject private var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(chat: Chat, userId: String) {
        self.chat = chat
        _viewModel = StateObject(wrappedValue: ChatViewModel(chatId: chat.id, userId: userId))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(
                                message: message,
                                isFromCurrentUser: message.isFromCurrentUser(userId: Auth.auth().currentUser?.uid ?? ""),
                                onCreateActionItem: {
                                    viewModel.createActionItem(from: message)
                                }
                            )
                            .id(message.id)
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
                onSend: viewModel.sendMessage
            )
        }
        .navigationTitle(chat.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: Message
    let isFromCurrentUser: Bool
    let onCreateActionItem: () -> Void
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isFromCurrentUser { Spacer() }
            
            // Profile picture for other users
            if !isFromCurrentUser {
                ProfilePictureView(size: 32)
            }
            
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                if !isFromCurrentUser {
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
                    Text(message.text)
                        .padding(12)
                        .background(isFromCurrentUser ? Color.blue : Color.gray.opacity(0.2))
                        .foregroundColor(isFromCurrentUser ? .white : .primary)
                        .cornerRadius(16)
                        .contextMenu {
                            Button {
                                onCreateActionItem()
                            } label: {
                                Label("Create Action Item", systemImage: "checkmark.circle")
                            }
                            
                            Button {
                                UIPasteboard.general.string = message.text
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                }
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Spacer for current user's messages
            if isFromCurrentUser {
                ProfilePictureView(size: 32)
            }
            
            if !isFromCurrentUser { Spacer() }
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
    
    var body: some View {
        HStack(spacing: 12) {
            TextField("Message", text: $messageText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
            
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
            chat: Chat(
                id: "1",
                title: "John Doe",
                lastMessage: "Hey there!",
                timestamp: Date(),
                participants: ["user1", "user2"]
            ),
            userId: "user1"
        )
    }
}


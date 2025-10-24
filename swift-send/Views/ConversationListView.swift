//
//  ConversationListView.swift
//  swift-send
//

import SwiftUI
import FirebaseDatabase
import FirebaseAuth

struct ConversationListView: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var conversations: [Conversation] = []
    @State private var conversationId: String?
    @State private var participants: [String] = []
    @State private var showChat = false
    @State private var userNames: [String: String] = [:] // userId -> displayName
    @State private var unreadCounts: [String: Int] = [:] // conversationId -> unread count

    private let realtimeManager = RealtimeManager.shared
    private var conversationObserverHandle: DatabaseHandle?

    var body: some View {
        Group {
            if conversations.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "message")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("No conversations yet")
                        .foregroundColor(.gray)
                    Text("Start a new chat or group")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } else {
                List(conversations) { conversation in
                    Button {
                        openConversation(conversation)
                    } label: {
                        ConversationRow(
                            conversation: conversation,
                            currentUserId: authManager.user?.uid ?? "",
                            userNames: userNames,
                            unreadCount: unreadCounts[conversation.id] ?? 0
                        )
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showChat) {
            if let conversationId = conversationId,
               let currentUserId = authManager.user?.uid {
                ChatView(viewModel: ChatViewModel(
                    conversationId: conversationId,
                    currentUserId: currentUserId,
                    participants: participants
                ))
            }
        }
        .onAppear {
            loadConversations()
        }
        .onDisappear {
            removeObserver()
        }
    }

    private func loadConversations() {
        guard let userId = authManager.user?.uid else { return }

        _ = realtimeManager.observeConversations(for: userId) { [self] conversations in
            Task { @MainActor in
                let previousConversations = self.conversations
                self.conversations = conversations
                await self.loadUserNames()

                // Only load unread counts for new conversations
                let newConversationIds = Set(conversations.map { $0.id })
                let oldConversationIds = Set(previousConversations.map { $0.id })
                let addedConversationIds = newConversationIds.subtracting(oldConversationIds)

                if !addedConversationIds.isEmpty || previousConversations.isEmpty {
                    await self.loadUnreadCounts()
                }

                // Set up observers for each conversation's messages
                await self.observeConversationMessages()
            }
        }
    }

    private func loadUserNames() async {
        var names: [String: String] = [:]

        // Get all unique user IDs from all conversations
        let allUserIds = Set(conversations.flatMap { $0.participants })

        for userId in allUserIds where userId != authManager.user?.uid {
            do {
                if let user = try await realtimeManager.getUser(userId: userId) {
                    names[userId] = user.displayName ?? user.email
                }
            } catch {
                print("Error loading user: \(error)")
            }
        }

        userNames = names
    }

    private func loadUnreadCounts() async {
        guard let currentUserId = authManager.user?.uid else { return }

        var counts: [String: Int] = [:]

        for conversation in conversations {
            do {
                let count = try await realtimeManager.getUnreadMessageCount(
                    conversationId: conversation.id,
                    userId: currentUserId
                )
                counts[conversation.id] = count
            } catch {
                print("Error loading unread count for \(conversation.id): \(error)")
                counts[conversation.id] = 0
            }
        }

        unreadCounts = counts
    }

    private func observeConversationMessages() async {
        guard let currentUserId = authManager.user?.uid else { return }

        for conversation in conversations {
            // Observe messages in this conversation
            _ = realtimeManager.observeMessages(for: conversation.id) { messages in

                Task { @MainActor in
                    // Count unread messages: from others, not read by current user
                    let unreadCount = messages.filter { message in
                        message.senderId != currentUserId && !message.isReadBy(userId: currentUserId)
                    }.count

                    // Update the count, ensuring minimum of 0
                    self.unreadCounts[conversation.id] = max(0, unreadCount)
                }
            }
        }
    }

    private func openConversation(_ conversation: Conversation) {
        conversationId = conversation.conversationId
        participants = conversation.participants
        showChat = true

        // Optimistically clear unread count (will be updated by observer)
        unreadCounts[conversation.id] = 0
    }

    private func removeObserver() {
        // Observer cleanup handled by RealtimeManager
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    let currentUserId: String
    let userNames: [String: String]
    let unreadCount: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(conversationTitle)
                    .font(.headline)
                    .fontWeight(unreadCount > 0 ? .bold : .regular)

                if let lastMessage = conversation.lastMessage {
                    Text(lastMessage)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let timestamp = conversation.lastMessageTimestamp {
                    Text(Date(timeIntervalSince1970: timestamp / 1000), style: .relative)
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var conversationTitle: String {
        let otherParticipants = conversation.participants.filter { $0 != currentUserId }

        if otherParticipants.isEmpty {
            return "You"
        } else if otherParticipants.count == 1 {
            // 1-on-1 chat
            return userNames[otherParticipants[0]] ?? "Unknown"
        } else {
            // Group chat
            let names = otherParticipants.compactMap { userNames[$0] }
            return names.joined(separator: ", ")
        }
    }
}

#Preview {
    NavigationStack {
        ConversationListView()
            .environmentObject(AuthManager())
    }
}

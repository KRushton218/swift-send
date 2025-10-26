//
//  ChatView.swift
//  swift-send
//

import SwiftUI

struct ChatView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject var viewModel: ChatViewModel
    @State private var scrollProxy: ScrollViewProxy?
    @State private var userNames: [String: String] = [:]
    @State private var preferredLanguage: String = "en" // Default to English

    var body: some View {
        VStack(spacing: 0) {
            // Offline connection banner
            if !viewModel.isConnected {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.caption)
                        .foregroundColor(.orange)

                    Text("No connection - Messages will be sent when you're back online")
                        .font(.caption)
                        .foregroundColor(.primary)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.15))
            }

            // Participant presence header
            if !viewModel.participantInfo.isEmpty {
                ParticipantHeader(participants: viewModel.participantInfo)
                Divider()
            }

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(
                                message: message,
                                isFromCurrentUser: message.senderId == viewModel.currentUserId,
                                userNames: userNames,
                                preferredLanguage: preferredLanguage,
                                isGroupChat: viewModel.participants.count > 2,
                                onRetry: { message in
                                    viewModel.retryMessage(message)
                                }
                            )
                            .id(message.id)
                        }

                        // Typing indicator
                        TypingIndicatorView(typingUsers: viewModel.typingUsers)
                            .id("typing-indicator")
                    }
                    .padding(.vertical)
                }
                .onAppear {
                    scrollProxy = proxy
                    scrollToBottom()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    scrollToBottom()
                }
                .onChange(of: viewModel.typingUsers.count) { oldCount, newCount in
                    // Auto-scroll when someone starts typing
                    if newCount > 0 {
                        withAnimation {
                            scrollProxy?.scrollTo("typing-indicator", anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input area
            HStack(spacing: 12) {
                TextField("Message", text: $viewModel.messageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .onChange(of: viewModel.messageText) { _, _ in
                        viewModel.onMessageTextChanged()
                    }

                Button {
                    viewModel.sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(viewModel.messageText.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .blue)
                }
                .disabled(viewModel.messageText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isLoading)
            }
            .padding()
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            userNames = await viewModel.getReadByNames()

            // Load user's preferred language
            if let prefs = try? await RealtimeManager.shared.getUserPreferences(userId: viewModel.currentUserId) {
                preferredLanguage = prefs.preferredLanguage
            }
        }
        .onAppear {
            viewModel.isActive = true
            authManager.activeConversationId = viewModel.conversationId
        }
        .onDisappear {
            viewModel.isActive = false
            authManager.activeConversationId = nil
            viewModel.onViewDisappear()
        }
    }

    private func scrollToBottom() {
        if let lastMessage = viewModel.messages.last {
            withAnimation {
                scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

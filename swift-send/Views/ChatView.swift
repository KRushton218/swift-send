//
//  ChatView.swift
//  swift-send
//
//  MVVM ARCHITECTURE - VIEW LAYER (Chat Screen)
//  =============================================
//  Main chat interface bound to ChatViewModel.
//  Demonstrates multiple SwiftUI binding patterns.
//
//  Binding Patterns:
//  1. @EnvironmentObject - App-wide state (authManager)
//  2. @StateObject - Per-view ViewModel ownership (viewModel)
//  3. @State - View-only state (scrollProxy, userNames)
//  4. @Published → View - Read viewModel.messages, viewModel.isConnected, etc.
//  5. $viewModel.messageText - Two-way binding with TextField
//  6. View → ViewModel - Call viewModel.sendMessage(), viewModel.retryMessage()
//
//  Data Flow:
//  User types → $viewModel.messageText updates → onChange fires → viewModel.onMessageTextChanged()
//  User sends → viewModel.sendMessage() → optimistic UI → Firebase → observer updates messages
//  Messages update → ForEach(viewModel.messages) re-renders → auto-scroll to bottom
//

import SwiftUI

struct ChatView: View {
    @EnvironmentObject var authManager: AuthManager  // App-wide auth state
    @StateObject var viewModel: ChatViewModel  // Per-conversation ViewModel
    @State private var scrollProxy: ScrollViewProxy?  // View-only state for scrolling
    @State private var userNames: [String: String] = [:]  // View-only cache
    @State private var preferredLanguage: String = "en"  // View-only preference
    @State private var showTranslationExtras: Bool = true  // Show sparkles for translation details

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
                                currentUserId: viewModel.currentUserId,
                                userNames: userNames,
                                preferredLanguage: preferredLanguage,
                                showTranslationExtras: showTranslationExtras,
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

            // Load user preferences
            if let prefs = try? await RealtimeManager.shared.getUserPreferences(userId: viewModel.currentUserId) {
                preferredLanguage = prefs.preferredLanguage
                showTranslationExtras = prefs.showTranslationExtras
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

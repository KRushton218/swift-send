//
//  ChatView.swift
//  swift-send
//

import SwiftUI

struct ChatView: View {
    @StateObject var viewModel: ChatViewModel
    @State private var scrollProxy: ScrollViewProxy?
    @State private var userNames: [String: String] = [:]
    @State private var userPreferences = UserPreferences.defaultPreferences
    @State private var showInsights = false

    var body: some View {
        VStack(spacing: 0) {
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
                                preferredLanguage: userPreferences.preferredLanguage
                            )
                            .id(message.id)
                        }
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
            }

            Divider()

            // Input area
            HStack(spacing: 12) {
                TextField("Message", text: $viewModel.messageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)

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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showInsights = true }) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.orange)
                }
            }
        }
        .sheet(isPresented: $showInsights) {
            InsightsView(conversationId: viewModel.conversationId)
        }
        .task {
            userNames = await viewModel.getReadByNames()
            await loadUserPreferences()
        }
        .onAppear {
            viewModel.isActive = true
            let participantNames = userNames.values.joined(separator: ", ")
            print("✅ ChatView appeared - notifications disabled for \(participantNames)")
        }
        .onDisappear {
            viewModel.isActive = false
            let participantNames = userNames.values.joined(separator: ", ")
            print("❌ ChatView disappeared - notifications enabled for \(participantNames)")
        }
    }

    private func scrollToBottom() {
        if let lastMessage = viewModel.messages.last {
            withAnimation {
                scrollProxy?.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }

    private func loadUserPreferences() async {
        let userId = viewModel.currentUserId

        do {
            let realtimeManager = RealtimeManager.shared
            if let prefs = try await realtimeManager.getUserPreferences(userId: userId) {
                userPreferences = prefs
            }
        } catch {
            print("Failed to load user preferences: \(error)")
        }
    }
}

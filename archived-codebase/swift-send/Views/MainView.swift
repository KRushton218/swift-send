//
//  MainView.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//

import SwiftUI
import FirebaseAuth
import OSLog

struct MainView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var viewModel: MainViewModel
    @State private var showingNewChat = false {
        didSet {
            Logger(subsystem: "com.swiftsend.app", category: "MainView").info("🔄 showingNewChat changed: \(oldValue) → \(self.showingNewChat)")
        }
    }
    @State private var showingProfile = false
    @State private var searchText = ""
    
    private var currentUserId: String {
        authManager.user?.uid ?? ""
    }
    
    private var filteredConversations: [Conversation] {
        let baseConversations = viewModel.validConversations
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedQuery.isEmpty else {
            return baseConversations
        }
        
        let query = trimmedQuery.lowercased()
        
        return baseConversations.filter { conversation in
            let displayName = viewModel
                .getConversationDisplayName(conversation, currentUserId: currentUserId)
                .lowercased()
            
            if displayName.contains(query) {
                return true
            }
            
            let lastMessagePreview = viewModel
                .getLastMessagePreview(conversation)
                .lowercased()
            
            if lastMessagePreview.contains(query) {
                return true
            }
            
            let memberMatch = conversation.memberDetails
                .values
                .contains { detail in
                    detail.displayName.lowercased().contains(query)
                }
            
            return memberMatch
        }
    }
    
    private var hasSearchQuery: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading conversations...")
                } else if filteredConversations.isEmpty {
                    if viewModel.validConversations.isEmpty && !hasSearchQuery {
                        // Empty state
                        VStack(spacing: 20) {
                            Image(systemName: "message.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            
                            Text("No Conversations")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("Start a new conversation to get chatting")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Button {
                                showingNewChat = true
                            } label: {
                                Label("New Chat", systemImage: "plus.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top)
                        }
                        .padding()
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass.circle")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            
                            Text("No Results")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            if hasSearchQuery {
                                Text("We couldn't find any conversations matching \"\(searchText)\".")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }
                        .padding()
                    }
                } else {
                    // Conversation list
                    List {
                        ForEach(filteredConversations) { conversation in
                            NavigationLink(
                                destination: ChatDetailView(
                                    conversation: conversation,
                                    userId: currentUserId
                                )
                            ) {
                                ConversationRowView(
                                    conversation: conversation,
                                    viewModel: viewModel,
                                    currentUserId: currentUserId
                                )
                            }
                            .id(conversation.id) // Stable ID - prevents navigation breaking
                        }
                        .onDelete { indexSet in
                            let conversationsToDelete = indexSet.map { filteredConversations[$0] }
                            for conversation in conversationsToDelete {
                                viewModel.deleteConversation(conversation)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search conversations"
            )
            .disableAutocorrection(true)
            .textInputAutocapitalization(.never)
            .navigationTitle("Swift Send")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingProfile = true
                    } label: {
                        Image(systemName: "person.circle")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingNewChat = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingNewChat) {
                UnifiedMessageView(currentUserId: currentUserId)
            }
            .sheet(isPresented: $showingProfile) {
                ProfileView()
            }
        }
    }
}

// MARK: - Conversation Row View

struct ConversationRowView: View {
    let conversation: Conversation
    let viewModel: MainViewModel
    let currentUserId: String
    
    var body: some View {
        HStack(spacing: 12) {
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.getConversationDisplayNameWithType(conversation, currentUserId: currentUserId))
                    .font(.headline)
                    .lineLimit(1)
                
                HStack {
                    Text(viewModel.getLastMessagePreview(conversation))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    Spacer()
                    
                    // Unread badge
                    if let conversationId = conversation.id {
                        let unreadCount = viewModel.getUnreadCount(conversationId: conversationId)
                        if unreadCount > 0 {
                            Text("\(unreadCount)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    MainView()
        .environmentObject(AuthManager())
}

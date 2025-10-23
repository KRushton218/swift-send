//
//  MainView.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//

import SwiftUI
import FirebaseAuth

struct MainView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var viewModel = MainViewModel()
    @State private var showingNewChat = false
    @State private var showingProfile = false
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading conversations...")
                } else if viewModel.validConversations.isEmpty {
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
                        
                        // Add sample data button for testing
                        Button("Add Sample Data") {
                            if let userId = authManager.user?.uid {
                                Task {
                                    await DataSeeder().seedSampleData(for: userId)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 8)
                    }
                    .padding()
                } else {
                    // Conversation list
                    List {
                        ForEach(viewModel.validConversations) { conversation in
                            NavigationLink(destination: ChatDetailView(conversation: conversation, userId: authManager.user?.uid ?? "")) {
                                ConversationRowView(
                                    conversation: conversation,
                                    viewModel: viewModel,
                                    currentUserId: authManager.user?.uid ?? ""
                                )
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let conversation = viewModel.validConversations[index]
                                viewModel.deleteConversation(conversation)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
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
            .onAppear {
                if let userId = authManager.user?.uid {
                    viewModel.loadData(for: userId)
                }
            }
            .onDisappear {
                viewModel.cleanup()
            }
            .sheet(isPresented: $showingNewChat) {
                UnifiedMessageView(currentUserId: authManager.user?.uid ?? "")
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
            // Avatar
            if let photoURL = viewModel.getConversationPhotoURL(conversation, currentUserId: currentUserId),
               let url = URL(string: photoURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 50, height: 50)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 50)
                            .clipShape(Circle())
                    case .failure:
                        avatarFallback
                    @unknown default:
                        avatarFallback
                    }
                }
            } else {
                avatarFallback
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(viewModel.getConversationDisplayName(conversation, currentUserId: currentUserId))
                        .font(.headline)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(viewModel.formatTimestamp(viewModel.getLastMessageTimestamp(conversation)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
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
    
    private var avatarFallback: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 50, height: 50)
            
            Image(systemName: conversation.type == .group ? "person.3.fill" : "person.fill")
                .foregroundColor(.gray)
                .font(.system(size: 24))
        }
    }
}

#Preview {
    MainView()
        .environmentObject(AuthManager())
}


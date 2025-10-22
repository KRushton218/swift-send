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
            VStack {
                // Chats Section
                if !viewModel.chats.isEmpty {
                    List {
                        Section("Chats") {
                            ForEach(viewModel.chats) { chat in
                                NavigationLink(destination: ChatDetailView(chat: chat, userId: authManager.user?.uid ?? "")) {
                                    ChatRow(chat: chat)
                                }
                            }
                            .onDelete { indexSet in
                                indexSet.forEach { index in
                                    viewModel.deleteChat(viewModel.chats[index])
                                }
                            }
                        }
                        
                        Section("Action Items") {
                            ForEach(viewModel.actionItems) { item in
                                ActionItemRow(item: item, onToggle: {
                                    viewModel.toggleActionItem(item)
                                })
                            }
                            .onDelete { indexSet in
                                indexSet.forEach { index in
                                    viewModel.deleteActionItem(viewModel.actionItems[index])
                                }
                            }
                        }
                    }
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "message.circle")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No chats yet")
                            .font(.title2)
                            .foregroundColor(.gray)
                        Text("Start a conversation to get started")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        // Add sample data button for testing
                        Button("Add Sample Data") {
                            if let userId = authManager.user?.uid {
                                Task {
                                    await DataSeeder().seedSampleData(for: userId)
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top)
                    }
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
            .sheet(isPresented: $showingNewChat) {
                NewChatView(userId: authManager.user?.uid ?? "")
            }
            .sheet(isPresented: $showingProfile) {
                ProfileView()
            }
        }
    }
}

// MARK: - Chat Row
struct ChatRow: View {
    let chat: Chat
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(chat.title)
                    .font(.headline)
                Text(chat.lastMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Text(chat.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if chat.unreadCount > 0 {
                Text("\(chat.unreadCount)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.blue)
                    .clipShape(Circle())
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Action Item Row
struct ActionItemRow: View {
    let item: ActionItem
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.isCompleted ? .green : .gray)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body)
                    .strikethrough(item.isCompleted)
                
                if let dueDate = item.dueDate {
                    Text(dueDate, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if item.priority == .high {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    MainView()
        .environmentObject(AuthManager())
}


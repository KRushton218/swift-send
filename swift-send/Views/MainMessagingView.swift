//
//  MainMessagingView.swift
//  swift-send
//

import SwiftUI
import FirebaseAuth

struct MainMessagingView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var selectedTab = 0
    @State private var isGroupMode = false
    @State private var hasUsers = false
    @State private var showProfile = false

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                ConversationListView()
                    .tabItem {
                        Label("Chats", systemImage: "message")
                    }
                    .tag(0)

                NewMessageView(isGroupMode: $isGroupMode, hasUsers: $hasUsers)
                    .tabItem {
                        Label("New", systemImage: "square.and.pencil")
                    }
                    .tag(1)
            }
            .navigationTitle(selectedTab == 0 ? "Chats" : "New Message")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if selectedTab == 1 && !isGroupMode && hasUsers {
                        Button {
                            isGroupMode = true
                        } label: {
                            Image(systemName: "person.2.fill")
                        }
                    } else if selectedTab == 0 {
                        Button {
                            showProfile = true
                        } label: {
                            Image(systemName: "person.circle")
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showProfile = true
                    } label: {
                        Image(systemName: "person.circle")
                    }
                }
            }
            .sheet(isPresented: $showProfile) {
                ProfileView()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenConversation"))) { notification in
                // Switch to Chats tab when notification is tapped
                if let userInfo = notification.userInfo,
                   let _ = userInfo["conversationId"] as? String {
                    selectedTab = 0
                    // Clear badge
                    NotificationManager.shared.clearBadge()
                }
            }
        }
    }
}

struct NewMessageView: View {
    @EnvironmentObject var authManager: AuthManager
    @Binding var isGroupMode: Bool
    @Binding var hasUsers: Bool

    @State private var users: [UserProfile] = []
    @State private var isLoading = true
    @State private var conversationId: String?
    @State private var participants: [String] = []
    @State private var showChat = false
    @State private var selectedUserIds: Set<String> = []

    private let realtimeManager = RealtimeManager.shared

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if users.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("No other users yet")
                        .foregroundColor(.gray)
                }
            } else {
                VStack(spacing: 0) {
                    // User List
                    List(users) { user in
                        HStack {
                            if isGroupMode {
                                Image(systemName: selectedUserIds.contains(user.userId) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedUserIds.contains(user.userId) ? .blue : .gray)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.displayName ?? "Unknown")
                                    .font(.headline)
                                Text(user.email)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            .padding(.vertical, 4)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isGroupMode {
                                toggleUserSelection(user.userId)
                            } else {
                                selectUser(user)
                            }
                        }
                    }

                    // Group chat action bar
                    if isGroupMode {
                        VStack(spacing: 0) {
                            Divider()

                            HStack {
                                Button {
                                    cancelGroupMode()
                                } label: {
                                    Text("Cancel")
                                        .foregroundColor(.red)
                                }

                                Spacer()

                                Text("\(selectedUserIds.count) selected")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)

                                Spacer()

                                Button {
                                    createGroupChat()
                                } label: {
                                    Text("Create")
                                        .fontWeight(.semibold)
                                }
                                .disabled(selectedUserIds.count < 1)
                            }
                            .padding()
                            .background(Color(.systemBackground))
                        }
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
        .task {
            await loadUsers()
        }
    }

    private func loadUsers() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let allUsers = try await realtimeManager.getAllUsers()
            // Filter out current user
            users = allUsers.filter { $0.userId != authManager.user?.uid }
            hasUsers = !users.isEmpty
        } catch {
            print("Error loading users: \(error)")
            hasUsers = false
        }
    }

    private func selectUser(_ user: UserProfile) {
        Task {
            do {
                guard let currentUserId = authManager.user?.uid else { return }

                participants = [currentUserId, user.userId]
                conversationId = try await realtimeManager.getOrCreateConversation(participants: participants)
                showChat = true
            } catch {
                print("Error creating conversation: \(error)")
            }
        }
    }

    private func toggleUserSelection(_ userId: String) {
        if selectedUserIds.contains(userId) {
            selectedUserIds.remove(userId)
        } else {
            selectedUserIds.insert(userId)
        }
    }

    private func cancelGroupMode() {
        isGroupMode = false
        selectedUserIds.removeAll()
    }

    private func createGroupChat() {
        Task {
            do {
                guard let currentUserId = authManager.user?.uid else { return }

                // Add current user to participants
                var allParticipants = Array(selectedUserIds)
                allParticipants.append(currentUserId)

                participants = allParticipants
                conversationId = try await realtimeManager.getOrCreateConversation(participants: allParticipants)

                // Reset group mode
                isGroupMode = false
                selectedUserIds.removeAll()

                // Show chat
                showChat = true
            } catch {
                print("Error creating group conversation: \(error)")
            }
        }
    }
}

#Preview {
    MainMessagingView()
        .environmentObject(AuthManager())
}

//
//  RecipientSelectionView.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/23/25.
//

import SwiftUI

struct RecipientSelectionView: View {
    let currentUserId: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedRecipients: [UserProfile] = []
    @State private var searchResults: [UserProfile] = []
    @State private var isSearching = false
    @State private var errorMessage = ""
    @State private var showingCompose = false
    @State private var existingConversation: Conversation?
    @State private var isCheckingConversation = false
    
    private let profileManager = UserProfileManager()
    private let messagingManager = MessagingManager()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search by name or email", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocapitalization(.none)
                        .onChange(of: searchText) { oldValue, newValue in
                            performSearch(query: newValue)
                        }
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                
                // Selected recipients chips
                if !selectedRecipients.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(selectedRecipients) { recipient in
                                RecipientChip(
                                    recipient: recipient,
                                    onRemove: {
                                        removeRecipient(recipient)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .background(Color(.systemBackground))
                }
                
                Divider()
                
                // Search results or instructions
                if isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !searchText.isEmpty {
                    if searchResults.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.system(size: 50))
                                .foregroundColor(.secondary)
                            
                            Text("No users found")
                                .font(.headline)
                            
                            Text("Try searching by name or email")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            // Option to add by email if it looks like an email
                            if isValidEmail(searchText) {
                                Button {
                                    addRecipientByEmail(searchText)
                                } label: {
                                    Label("Add \(searchText)", systemImage: "plus.circle.fill")
                                }
                                .buttonStyle(.bordered)
                                .padding(.top, 8)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(searchResults) { user in
                                Button {
                                    addRecipient(user)
                                } label: {
                                    HStack(spacing: 12) {
                                        ProfilePictureView(photoURL: user.photoURL, size: 40)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(user.displayName)
                                                .font(.headline)
                                            Text(user.email)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        if selectedRecipients.contains(where: { $0.id == user.id }) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                                .disabled(selectedRecipients.contains(where: { $0.id == user.id }))
                            }
                        }
                        .listStyle(.plain)
                    }
                } else {
                    VStack(spacing: 20) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("Add Recipients")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Search for people by name or email to start a conversation")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                // Error message
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                }
            }
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        proceedToCompose()
                    } label: {
                        if isCheckingConversation {
                            ProgressView()
                        } else {
                            Text("Next")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(selectedRecipients.isEmpty || isCheckingConversation)
                }
            }
            .navigationDestination(isPresented: $showingCompose) {
                if let existingConversation = existingConversation {
                    // Navigate to existing conversation
                    ChatDetailView(conversation: existingConversation, userId: currentUserId)
                } else {
                    // Show compose view for new conversation
                    ComposeMessageView(
                        currentUserId: currentUserId,
                        recipients: selectedRecipients,
                        onDismiss: {
                            dismiss()
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func performSearch(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        errorMessage = ""
        
        Task {
            do {
                let results = try await profileManager.searchUsers(query: query, limit: 20)
                // Filter out current user and already selected recipients
                let filtered = results.filter { user in
                    user.id != currentUserId && !selectedRecipients.contains(where: { $0.id == user.id })
                }
                
                await MainActor.run {
                    searchResults = filtered
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Search failed: \(error.localizedDescription)"
                    isSearching = false
                }
            }
        }
    }
    
    private func addRecipient(_ user: UserProfile) {
        guard !selectedRecipients.contains(where: { $0.id == user.id }) else { return }
        guard user.id != currentUserId else { return }
        
        selectedRecipients.append(user)
        searchText = ""
        searchResults = []
    }
    
    private func addRecipientByEmail(_ email: String) {
        errorMessage = ""
        
        Task {
            do {
                guard let user = try await profileManager.findUserByEmail(email: email) else {
                    await MainActor.run {
                        errorMessage = "No user found with email: \(email)"
                    }
                    return
                }
                
                await MainActor.run {
                    addRecipient(user)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Error looking up user: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func removeRecipient(_ user: UserProfile) {
        selectedRecipients.removeAll { $0.id == user.id }
    }
    
    private func isValidEmail(_ string: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: string)
    }
    
    private func proceedToCompose() {
        isCheckingConversation = true
        errorMessage = ""
        
        Task {
            do {
                // Build member IDs list (current user + selected recipients)
                var memberIds = [currentUserId]
                memberIds.append(contentsOf: selectedRecipients.map { $0.id })
                
                // Check if conversation already exists
                let existing = try await messagingManager.findConversationByParticipants(memberIds: memberIds)
                
                await MainActor.run {
                    existingConversation = existing
                    isCheckingConversation = false
                    showingCompose = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Error checking conversations: \(error.localizedDescription)"
                    isCheckingConversation = false
                }
            }
        }
    }
}

// MARK: - Recipient Chip View

struct RecipientChip: View {
    let recipient: UserProfile
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            ProfilePictureView(photoURL: recipient.photoURL, size: 24)
            
            Text(recipient.displayName)
                .font(.subheadline)
                .lineLimit(1)
            
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.1))
        .foregroundColor(.blue)
        .cornerRadius(16)
    }
}

#Preview {
    RecipientSelectionView(currentUserId: "test-user")
}


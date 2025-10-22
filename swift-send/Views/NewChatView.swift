//
//  NewChatView.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//

import SwiftUI

struct NewChatView: View {
    let userId: String
    @Environment(\.dismiss) private var dismiss
    @State private var recipientEmail = ""
    @State private var chatTitle = ""
    @State private var isCreating = false
    @State private var errorMessage = ""
    
    private let messagingManager = MessagingManager()
    
    var body: some View {
        NavigationView {
            Form {
                Section("Chat Details") {
                    TextField("Recipient Email", text: $recipientEmail)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                    
                    TextField("Chat Title", text: $chatTitle)
                        .textContentType(.name)
                }
                
                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                Section {
                    Button(action: createChat) {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Create Chat")
                        }
                    }
                    .disabled(recipientEmail.isEmpty || chatTitle.isEmpty || isCreating)
                }
            }
            .navigationTitle("New Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func createChat() {
        isCreating = true
        errorMessage = ""
        
        Task {
            do {
                // For now, we'll use email as the recipient ID
                // In a real app, you'd look up the user by email first
                let participants = [userId, recipientEmail]
                
                let chatId = try await messagingManager.createChat(
                    participants: participants,
                    title: chatTitle,
                    createdBy: userId
                )
                
                // Send initial system message
                _ = try await messagingManager.sendMessage(
                    chatId: chatId,
                    senderId: userId,
                    senderName: "System",
                    text: "Chat created",
                    type: .system
                )
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to create chat: \(error.localizedDescription)"
                    isCreating = false
                }
            }
        }
    }
}

#Preview {
    NewChatView(userId: "test-user")
}


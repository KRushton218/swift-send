//
//  ChatViewModel.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//

import Foundation
import FirebaseDatabase
import Combine

class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var messageText: String = ""
    @Published var isLoading = false
    @Published var currentUserProfile: UserProfile?
    
    private var messagingManager = MessagingManager()
    private var profileManager = UserProfileManager()
    private var messageHandle: DatabaseHandle?
    private var chatId: String
    private var userId: String
    
    init(chatId: String, userId: String) {
        self.chatId = chatId
        self.userId = userId
        loadMessages()
        markAsRead()
        loadCurrentUserProfile()
    }
    
    func loadCurrentUserProfile() {
        Task {
            do {
                let profile = try await profileManager.getUserProfile(userId: userId)
                await MainActor.run {
                    self.currentUserProfile = profile
                }
            } catch {
                print("Error loading user profile: \(error.localizedDescription)")
            }
        }
    }
    
    func loadMessages() {
        isLoading = true
        messageHandle = messagingManager.observeMessages(chatId: chatId) { [weak self] messages in
            self?.messages = messages
            self?.isLoading = false
        }
    }
    
    func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let text = messageText
        messageText = "" // Clear input immediately
        
        Task {
            do {
                // Use current user profile display name
                let displayName = currentUserProfile?.displayName ?? "User"
                _ = try await messagingManager.sendMessage(
                    chatId: chatId,
                    senderId: userId,
                    senderName: displayName,
                    text: text
                )
            } catch {
                print("Error sending message: \(error.localizedDescription)")
                // Restore message text on error
                await MainActor.run {
                    messageText = text
                }
            }
        }
    }
    
    func createActionItem(from message: Message, priority: ActionItem.Priority = .medium, dueDate: Date? = nil) {
        Task {
            do {
                _ = try await messagingManager.createActionItemFromMessage(
                    userId: userId,
                    chatId: chatId,
                    messageText: message.text,
                    priority: priority,
                    dueDate: dueDate
                )
            } catch {
                print("Error creating action item: \(error.localizedDescription)")
            }
        }
    }
    
    private func markAsRead() {
        Task {
            do {
                try await messagingManager.markAsRead(chatId: chatId, userId: userId)
            } catch {
                print("Error marking as read: \(error.localizedDescription)")
            }
        }
    }
    
    deinit {
        if let handle = messageHandle {
            messagingManager.observeMessages(chatId: chatId) { _ in }
            // Note: We need to properly remove the observer
            // This is a simplified version
        }
    }
}


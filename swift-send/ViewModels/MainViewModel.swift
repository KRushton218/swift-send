//
//  MainViewModel.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//

import Foundation
import FirebaseDatabase
import Combine

class MainViewModel: ObservableObject {
    @Published var chats: [Chat] = []
    @Published var actionItems: [ActionItem] = []
    @Published var isLoading = false
    
    private var realtimeManager = RealtimeManager()
    private var messagingManager = MessagingManager()
    private var chatHandle: DatabaseHandle?
    private var actionItemHandle: DatabaseHandle?
    private var userId: String?
    
    func loadData(for userId: String) {
        self.userId = userId
        isLoading = true
        
        // Listen to chats
        chatHandle = realtimeManager.observe(at: "users/\(userId)/chats") { [weak self] data in
            self?.chats = data.compactMap { (key, value) -> Chat? in
                guard let chatData = value as? [String: Any] else { return nil }
                return Chat(
                    id: key,
                    title: chatData["title"] as? String ?? "Untitled",
                    lastMessage: chatData["lastMessage"] as? String ?? "",
                    timestamp: Date(timeIntervalSince1970: chatData["timestamp"] as? TimeInterval ?? 0),
                    participants: chatData["participants"] as? [String] ?? [],
                    unreadCount: chatData["unreadCount"] as? Int ?? 0
                )
            }.sorted { $0.timestamp > $1.timestamp }
            
            self?.isLoading = false
        }
        
        // Listen to action items
        actionItemHandle = realtimeManager.observe(at: "users/\(userId)/actionItems") { [weak self] data in
            self?.actionItems = data.compactMap { (key, value) -> ActionItem? in
                guard let itemData = value as? [String: Any] else { return nil }
                let priorityString = itemData["priority"] as? String ?? "medium"
                let priority = ActionItem.Priority(rawValue: priorityString) ?? .medium
                
                let dueDate: Date? = if let timestamp = itemData["dueDate"] as? TimeInterval {
                    Date(timeIntervalSince1970: timestamp)
                } else {
                    nil
                }
                
                return ActionItem(
                    id: key,
                    title: itemData["title"] as? String ?? "Untitled",
                    isCompleted: itemData["isCompleted"] as? Bool ?? false,
                    dueDate: dueDate,
                    priority: priority,
                    chatId: itemData["chatId"] as? String
                )
            }.sorted { !$0.isCompleted && $1.isCompleted }
        }
    }
    
    func deleteChat(_ chat: Chat) {
        guard let userId = userId else { return }
        
        Task {
            do {
                try await messagingManager.deleteChat(chatId: chat.id, userId: userId)
            } catch {
                print("Error deleting chat: \(error.localizedDescription)")
            }
        }
    }
    
    func deleteActionItem(_ item: ActionItem) {
        guard let userId = userId else { return }
        
        Task {
            do {
                try await messagingManager.deleteActionItem(userId: userId, actionItemId: item.id)
            } catch {
                print("Error deleting action item: \(error.localizedDescription)")
            }
        }
    }
    
    func toggleActionItem(_ item: ActionItem) {
        guard let userId = userId else { return }
        
        Task {
            do {
                try await messagingManager.toggleActionItemCompletion(userId: userId, actionItemId: item.id, isCompleted: !item.isCompleted)
            } catch {
                print("Error toggling action item: \(error.localizedDescription)")
            }
        }
    }
    
    deinit {
        if let userId = userId {
            if let handle = chatHandle {
                realtimeManager.removeObserver(at: "users/\(userId)/chats", handle: handle)
            }
            if let handle = actionItemHandle {
                realtimeManager.removeObserver(at: "users/\(userId)/actionItems", handle: handle)
            }
        }
    }
}


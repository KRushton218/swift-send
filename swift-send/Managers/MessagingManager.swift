//
//  MessagingManager.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//

import Foundation
import FirebaseDatabase

class MessagingManager {
    private let realtimeManager = RealtimeManager()
    
    // MARK: - Send Message
    func sendMessage(chatId: String, senderId: String, senderName: String, text: String, type: Message.MessageType = .text) async throws -> String {
        let messageData: [String: Any] = [
            "chatId": chatId,
            "senderId": senderId,
            "senderName": senderName,
            "text": text,
            "timestamp": Date().timeIntervalSince1970,
            "type": type.rawValue,
            "read": false
        ]
        
        // Add message to chat
        let messageId = try await realtimeManager.createItem(at: "chats/\(chatId)/messages", data: messageData)
        
        // Update chat metadata for all participants
        let chatData = try await realtimeManager.getData(at: "chats/\(chatId)/metadata")
        if let participants = chatData?["participants"] as? [String] {
            for participantId in participants {
                let userChatUpdate: [String: Any] = [
                    "lastMessage": text,
                    "timestamp": Date().timeIntervalSince1970
                ]
                try await realtimeManager.updateData(at: "users/\(participantId)/chats/\(chatId)", data: userChatUpdate)
                
                // Increment unread count for other participants
                if participantId != senderId {
                    let currentData = try await realtimeManager.getData(at: "users/\(participantId)/chats/\(chatId)")
                    let currentUnread = currentData?["unreadCount"] as? Int ?? 0
                    try await realtimeManager.updateData(at: "users/\(participantId)/chats/\(chatId)", data: ["unreadCount": currentUnread + 1])
                }
            }
        }
        
        return messageId
    }
    
    // MARK: - Create Chat
    func createChat(participants: [String], title: String, createdBy: String) async throws -> String {
        let chatId = UUID().uuidString
        
        // Create chat metadata
        let chatMetadata: [String: Any] = [
            "participants": participants,
            "createdAt": Date().timeIntervalSince1970,
            "createdBy": createdBy
        ]
        
        try await realtimeManager.setData(at: "chats/\(chatId)/metadata", data: chatMetadata)
        
        // Add chat to each participant's chat list
        for participantId in participants {
            let userChatData: [String: Any] = [
                "title": title,
                "lastMessage": "",
                "timestamp": Date().timeIntervalSince1970,
                "participants": participants,
                "unreadCount": 0
            ]
            try await realtimeManager.setData(at: "users/\(participantId)/chats/\(chatId)", data: userChatData)
        }
        
        return chatId
    }
    
    // MARK: - Mark Messages as Read
    func markAsRead(chatId: String, userId: String) async throws {
        // Reset unread count
        try await realtimeManager.updateData(at: "users/\(userId)/chats/\(chatId)", data: ["unreadCount": 0])
    }
    
    // MARK: - Observe Messages
    func observeMessages(chatId: String, completion: @escaping ([Message]) -> Void) -> DatabaseHandle {
        return realtimeManager.observe(at: "chats/\(chatId)/messages") { data in
            let messages = data.compactMap { (key, value) -> Message? in
                guard let messageData = value as? [String: Any] else { return nil }
                return Message(
                    id: key,
                    chatId: messageData["chatId"] as? String ?? chatId,
                    senderId: messageData["senderId"] as? String ?? "",
                    senderName: messageData["senderName"] as? String ?? "Unknown",
                    text: messageData["text"] as? String ?? "",
                    timestamp: Date(timeIntervalSince1970: messageData["timestamp"] as? TimeInterval ?? 0),
                    type: Message.MessageType(rawValue: messageData["type"] as? String ?? "text") ?? .text,
                    read: messageData["read"] as? Bool ?? false,
                    actionItemId: messageData["actionItemId"] as? String
                )
            }.sorted { $0.timestamp < $1.timestamp }
            
            completion(messages)
        }
    }
    
    // MARK: - Create Action Item from Message
    func createActionItemFromMessage(userId: String, chatId: String, messageText: String, priority: ActionItem.Priority = .medium, dueDate: Date? = nil) async throws -> String {
        let actionItemData: [String: Any] = [
            "title": messageText,
            "isCompleted": false,
            "priority": priority.rawValue,
            "chatId": chatId,
            "dueDate": dueDate?.timeIntervalSince1970 ?? 0
        ]
        
        let actionItemId = try await realtimeManager.createItem(at: "users/\(userId)/actionItems", data: actionItemData)
        
        // Send a system message about the action item
        _ = try await sendMessage(chatId: chatId, senderId: userId, senderName: "System", text: "Action item created: \(messageText)", type: .actionItem)
        
        return actionItemId
    }
    
    // MARK: - Delete Message
    func deleteMessage(chatId: String, messageId: String) async throws {
        try await realtimeManager.deleteData(at: "chats/\(chatId)/messages/\(messageId)")
    }
    
    // MARK: - Delete Chat
    func deleteChat(chatId: String, userId: String) async throws {
        // Delete chat from user's chat list only
        // The global chat data in /chats/{chatId} remains for other participants
        try await realtimeManager.deleteData(at: "users/\(userId)/chats/\(chatId)")
    }
    
    // MARK: - Delete Action Item
    func deleteActionItem(userId: String, actionItemId: String) async throws {
        try await realtimeManager.deleteData(at: "users/\(userId)/actionItems/\(actionItemId)")
    }
    
    // MARK: - Toggle Action Item Completion
    func toggleActionItemCompletion(userId: String, actionItemId: String, isCompleted: Bool) async throws {
        try await realtimeManager.updateData(at: "users/\(userId)/actionItems/\(actionItemId)", data: ["isCompleted": isCompleted])
    }
}


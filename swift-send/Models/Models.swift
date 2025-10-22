//
//  Models.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//

import Foundation

// MARK: - Chat Model
struct Chat: Identifiable, Codable {
    var id: String
    var title: String
    var lastMessage: String
    var timestamp: Date
    var participants: [String]
    var unreadCount: Int
    
    init(id: String = UUID().uuidString, title: String, lastMessage: String, timestamp: Date = Date(), participants: [String] = [], unreadCount: Int = 0) {
        self.id = id
        self.title = title
        self.lastMessage = lastMessage
        self.timestamp = timestamp
        self.participants = participants
        self.unreadCount = unreadCount
    }
}

// MARK: - Message Model
struct Message: Identifiable, Codable, Equatable {
    var id: String
    var chatId: String
    var senderId: String
    var senderName: String
    var text: String
    var timestamp: Date
    var type: MessageType
    var read: Bool
    var actionItemId: String?
    
    init(id: String = UUID().uuidString, chatId: String, senderId: String, senderName: String, text: String, timestamp: Date = Date(), type: MessageType = .text, read: Bool = false, actionItemId: String? = nil) {
        self.id = id
        self.chatId = chatId
        self.senderId = senderId
        self.senderName = senderName
        self.text = text
        self.timestamp = timestamp
        self.type = type
        self.read = read
        self.actionItemId = actionItemId
    }
    
    enum MessageType: String, Codable {
        case text
        case actionItem
        case system
    }
    
    func isFromCurrentUser(userId: String) -> Bool {
        return senderId == userId
    }
}

// MARK: - User Profile Model
struct UserProfile: Identifiable, Codable {
    var id: String
    var email: String
    var displayName: String
    var photoURL: String?
    var createdAt: Date
    
    init(id: String, email: String, displayName: String? = nil, photoURL: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.email = email
        self.displayName = displayName ?? email.components(separatedBy: "@").first ?? "User"
        self.photoURL = photoURL
        self.createdAt = createdAt
    }
}

// MARK: - Action Item Model
struct ActionItem: Identifiable, Codable {
    var id: String
    var title: String
    var isCompleted: Bool
    var dueDate: Date?
    var priority: Priority
    var chatId: String?
    
    init(id: String = UUID().uuidString, title: String, isCompleted: Bool = false, dueDate: Date? = nil, priority: Priority = .medium, chatId: String? = nil) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.priority = priority
        self.chatId = chatId
    }
    
    enum Priority: String, Codable {
        case low, medium, high
    }
}


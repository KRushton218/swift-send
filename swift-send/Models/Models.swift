//
//  Models.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//

import Foundation
import FirebaseFirestore

// MARK: - Conversation Type
enum ConversationType: String, Codable {
    case direct
    case group
}

// MARK: - Conversation Model (Firestore)
struct Conversation: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var type: ConversationType
    var name: String?
    var createdAt: Date
    var createdBy: String
    var memberIds: [String]
    var memberDetails: [String: MemberDetail]
    var lastMessage: LastMessage?
    var metadata: ConversationMetadata
    
    // Equatable implementation - compare by ID only for SwiftUI stability
    static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        return lhs.id == rhs.id
    }
    
    init(id: String? = nil, type: ConversationType, name: String? = nil, createdAt: Date = Date(), createdBy: String, memberIds: [String], memberDetails: [String: MemberDetail], lastMessage: LastMessage? = nil, metadata: ConversationMetadata = ConversationMetadata()) {
        self.id = id
        self.type = type
        self.name = name
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.memberIds = memberIds
        self.memberDetails = memberDetails
        self.lastMessage = lastMessage
        self.metadata = metadata
    }
    
    struct MemberDetail: Codable, Equatable {
        var displayName: String
        var photoURL: String?
        var joinedAt: Date
        
        init(displayName: String, photoURL: String? = nil, joinedAt: Date = Date()) {
            self.displayName = displayName
            self.photoURL = photoURL
            self.joinedAt = joinedAt
        }
    }
    
    struct LastMessage: Codable, Equatable {
        var text: String
        var senderId: String
        var senderName: String
        var timestamp: Date
        var type: String
        
        init(text: String, senderId: String, senderName: String, timestamp: Date = Date(), type: String = "text") {
            self.text = text
            self.senderId = senderId
            self.senderName = senderName
            self.timestamp = timestamp
            self.type = type
        }
    }
    
    struct ConversationMetadata: Codable, Equatable {
        var totalMessages: Int
        var imageUrl: String?
        
        init(totalMessages: Int = 0, imageUrl: String? = nil) {
            self.totalMessages = totalMessages
            self.imageUrl = imageUrl
        }
    }
}

// MARK: - Conversation Extensions (Safe Accessors)
extension Conversation {
    /// Safe ID accessor that handles nil cases
    var safeId: String {
        guard let id = id else {
            print("⚠️ Warning: Conversation has nil ID. Type: \(type), CreatedBy: \(createdBy)")
            return "unknown-\(UUID().uuidString)"
        }
        return id
    }
    
    /// Safe display name with comprehensive fallback chain
    func safeDisplayName(currentUserId: String) -> String {
        if type == .group {
            // Group chat: use name or generate from participants
            if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                return name
            }
            
            // Generate name from participants (excluding current user)
            let otherMembers = memberIds.filter { $0 != currentUserId }
            let otherMemberNames = otherMembers.compactMap { memberId -> String? in
                guard let memberDetail = memberDetails[memberId] else { return nil }
                let name = memberDetail.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? nil : name
            }
            
            if otherMemberNames.isEmpty {
                return "Group Chat"
            } else if otherMemberNames.count <= 3 {
                // List names for small groups (1-3 people)
                return otherMemberNames.joined(separator: ", ")
            } else {
                // "You and X people" for larger groups
                return "You and \(otherMemberNames.count) people"
            }
        } else {
            // Direct chat: find other member
            let otherMemberId = memberIds.first { $0 != currentUserId }
            
            if let otherMemberId = otherMemberId,
               let memberDetail = memberDetails[otherMemberId] {
                let displayName = memberDetail.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !displayName.isEmpty {
                    return displayName
                }
            }
            
            // Fallback for direct chats - should rarely happen
            return "Unknown User"
        }
    }
    
    /// Safe photo URL accessor with validation
    func safePhotoURL(currentUserId: String) -> String? {
        var urlString: String?
        
        if type == .group {
            // Group chat: use metadata image
            urlString = metadata.imageUrl
        } else {
            // Direct chat: use other member's photo
            let otherMemberId = memberIds.first { $0 != currentUserId }
            if let otherMemberId = otherMemberId,
               let memberDetail = memberDetails[otherMemberId] {
                urlString = memberDetail.photoURL
            }
        }
        
        // Validate URL string
        guard let urlString = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty,
              URL(string: urlString) != nil else {
            return nil
        }
        
        return urlString
    }
    
    /// Enhanced last message preview with type handling
    func enhancedLastMessagePreview() -> String {
        guard let lastMessage = lastMessage else {
            return "No messages yet"
        }
        
        // Handle deleted messages
        if lastMessage.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Check message type for better preview
            switch MessageType(rawValue: lastMessage.type) {
            case .image:
                return "📷 Photo"
            case .video:
                return "🎥 Video"
            case .file:
                return "📎 File"
            case .actionItem:
                return "✓ Action Item"
            case .system:
                return "System message"
            case .text, .none:
                return "No messages yet"
            }
        }
        
        // Return text preview based on type
        switch MessageType(rawValue: lastMessage.type) {
        case .image:
            return "📷 \(lastMessage.text)"
        case .video:
            return "🎥 \(lastMessage.text)"
        case .file:
            return "📎 \(lastMessage.text)"
        case .actionItem:
            return "✓ \(lastMessage.text)"
        case .system:
            return lastMessage.text
        case .text, .none:
            return lastMessage.text
        }
    }
}

// MARK: - User Conversation Status (RTDB)
struct UserConversationStatus: Codable {
    var conversationId: String
    var lastReadMessageId: String?
    var lastReadTimestamp: Double?
    var unreadCount: Int
    var isPinned: Bool
    var isMuted: Bool
    var isHidden: Bool
    var lastMessageTimestamp: Double
    
    init(conversationId: String, lastReadMessageId: String? = nil, lastReadTimestamp: Double? = nil, unreadCount: Int = 0, isPinned: Bool = false, isMuted: Bool = false, isHidden: Bool = false, lastMessageTimestamp: Double = Date().timeIntervalSince1970 * 1000) {
        self.conversationId = conversationId
        self.lastReadMessageId = lastReadMessageId
        self.lastReadTimestamp = lastReadTimestamp
        self.unreadCount = unreadCount
        self.isPinned = isPinned
        self.isMuted = isMuted
        self.isHidden = isHidden
        self.lastMessageTimestamp = lastMessageTimestamp
    }
    
    // RTDB Conversion
    init?(from dictionary: [String: Any]) {
        guard let conversationId = dictionary["conversationId"] as? String else { return nil }
        
        self.conversationId = conversationId
        self.lastReadMessageId = dictionary["lastReadMessageId"] as? String
        self.lastReadTimestamp = dictionary["lastReadTimestamp"] as? Double
        self.unreadCount = dictionary["unreadCount"] as? Int ?? 0
        self.isPinned = dictionary["isPinned"] as? Bool ?? false
        self.isMuted = dictionary["isMuted"] as? Bool ?? false
        self.isHidden = dictionary["isHidden"] as? Bool ?? false
        self.lastMessageTimestamp = dictionary["lastMessageTimestamp"] as? Double ?? Date().timeIntervalSince1970 * 1000
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "conversationId": conversationId,
            "unreadCount": unreadCount,
            "isPinned": isPinned,
            "isMuted": isMuted,
            "isHidden": isHidden,
            "lastMessageTimestamp": lastMessageTimestamp
        ]
        
        if let lastReadMessageId = lastReadMessageId {
            dict["lastReadMessageId"] = lastReadMessageId
        }
        if let lastReadTimestamp = lastReadTimestamp {
            dict["lastReadTimestamp"] = lastReadTimestamp
        }
        
        return dict
    }
}

// MARK: - Message Type
enum MessageType: String, Codable {
    case text
    case image
    case video
    case file
    case actionItem
    case system
}

// MARK: - Delivery Status
enum DeliveryState: String, Codable {
    case pending
    case sent
    case delivered
    case failed
}

struct DeliveryStatus: Codable, Equatable {
    var status: DeliveryState
    var timestamp: Double
    
    init(status: DeliveryState, timestamp: Double = Date().timeIntervalSince1970 * 1000) {
        self.status = status
        self.timestamp = timestamp
    }
    
    // RTDB Conversion
    init?(from dictionary: [String: Any]) {
        guard let statusString = dictionary["status"] as? String,
              let status = DeliveryState(rawValue: statusString) else {
            return nil
        }
        
        self.status = status
        self.timestamp = dictionary["timestamp"] as? Double ?? Date().timeIntervalSince1970 * 1000
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "status": status.rawValue,
            "timestamp": timestamp
        ]
    }
}

// MARK: - Message Model (Hybrid: RTDB + Firestore)
struct Message: Identifiable, Codable, Equatable {
    var id: String
    var conversationId: String  // Changed from chatId
    var senderId: String
    var senderName: String
    var text: String
    var timestamp: Date
    var type: MessageType
    var mediaUrl: String?
    var replyToMessageId: String?
    
    // RTDB-specific (real-time delivery tracking)
    var deliveryStatus: [String: DeliveryStatus]?
    var readBy: [String: Double]?
    
    // Firestore-specific (archived messages)
    var finalDeliveryStatus: FinalDeliveryStatus?
    var isDeleted: Bool
    var isEdited: Bool
    var editedAt: Date?
    var deletedFor: [String]?  // Track which users deleted this message
    
    // Legacy support
    var read: Bool
    var actionItemId: String?
    
    init(id: String = UUID().uuidString, conversationId: String, senderId: String, senderName: String, text: String, timestamp: Date = Date(), type: MessageType = .text, mediaUrl: String? = nil, replyToMessageId: String? = nil, deliveryStatus: [String: DeliveryStatus]? = nil, readBy: [String: Double]? = nil, isDeleted: Bool = false, isEdited: Bool = false, editedAt: Date? = nil, deletedFor: [String]? = nil, read: Bool = false, actionItemId: String? = nil) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.senderName = senderName
        self.text = text
        self.timestamp = timestamp
        self.type = type
        self.mediaUrl = mediaUrl
        self.replyToMessageId = replyToMessageId
        self.deliveryStatus = deliveryStatus
        self.readBy = readBy
        self.finalDeliveryStatus = nil
        self.isDeleted = isDeleted
        self.isEdited = isEdited
        self.editedAt = editedAt
        self.deletedFor = deletedFor
        self.read = read
        self.actionItemId = actionItemId
    }
    
    struct FinalDeliveryStatus: Codable, Equatable {
        var delivered: [String]
        var failed: [String]
        var read: [String]
        
        init(delivered: [String] = [], failed: [String] = [], read: [String] = []) {
            self.delivered = delivered
            self.failed = failed
            self.read = read
        }
    }
    
    func isFromCurrentUser(userId: String) -> Bool {
        return senderId == userId
    }
    
    // Check if message was read by a specific user
    func wasReadBy(userId: String) -> Bool {
        return readBy?[userId] != nil || read
    }
    
    // Check delivery status for a user
    func deliveryStateFor(userId: String) -> DeliveryState? {
        return deliveryStatus?[userId]?.status
    }
    
    // Check if message is deleted for a specific user
    func isDeletedForUser(_ userId: String) -> Bool {
        return deletedFor?.contains(userId) ?? false
    }
    
    // MARK: - RTDB Conversion (for real-time active messages)
    init?(rtdbData dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? String,
              let senderId = dictionary["senderId"] as? String,
              let senderName = dictionary["senderName"] as? String,
              let text = dictionary["text"] as? String else {
            return nil
        }
        
        self.id = id
        self.conversationId = ""  // Will be set from path
        self.senderId = senderId
        self.senderName = senderName
        self.text = text
        
        // Handle timestamp (can be Double or ServerValue)
        if let timestampValue = dictionary["timestamp"] as? Double {
            self.timestamp = Date(timeIntervalSince1970: timestampValue / 1000)
        } else {
            self.timestamp = Date()
        }
        
        self.type = MessageType(rawValue: dictionary["type"] as? String ?? "text") ?? .text
        self.mediaUrl = dictionary["mediaUrl"] as? String
        self.replyToMessageId = dictionary["replyToMessageId"] as? String
        
        // Parse delivery status
        if let deliveryDict = dictionary["deliveryStatus"] as? [String: [String: Any]] {
            var statuses: [String: DeliveryStatus] = [:]
            for (userId, statusData) in deliveryDict {
                if let status = DeliveryStatus(from: statusData) {
                    statuses[userId] = status
                }
            }
            self.deliveryStatus = statuses.isEmpty ? nil : statuses
        } else {
            self.deliveryStatus = nil
        }
        
        // Parse read receipts
        if let readByDict = dictionary["readBy"] as? [String: Double] {
            self.readBy = readByDict
        } else {
            self.readBy = nil
        }
        
        self.finalDeliveryStatus = nil
        self.isDeleted = false
        self.isEdited = dictionary["isEdited"] as? Bool ?? false
        self.editedAt = nil
        self.deletedFor = dictionary["deletedFor"] as? [String]
        self.read = false
        self.actionItemId = dictionary["actionItemId"] as? String
    }
    
    func toRTDBDictionary(memberIds: [String]) -> [String: Any] {
        var deliveryDict: [String: [String: Any]] = [:]
        for memberId in memberIds {
            let status: DeliveryState = memberId == senderId ? .sent : .pending
            deliveryDict[memberId] = [
                "status": status.rawValue,
                "timestamp": ["sv": "timestamp"]  // ServerValue.timestamp()
            ]
        }
        
        var dict: [String: Any] = [
            "id": id,
            "senderId": senderId,
            "senderName": senderName,
            "text": text,
            "type": type.rawValue,
            "timestamp": ["sv": "timestamp"],  // ServerValue.timestamp()
            "deliveryStatus": deliveryDict,
            "readBy": [senderId: ["sv": "timestamp"]]
        ]
        
        if let mediaUrl = mediaUrl {
            dict["mediaUrl"] = mediaUrl
        } else {
            dict["mediaUrl"] = NSNull()
        }
        
        if let replyToMessageId = replyToMessageId {
            dict["replyToMessageId"] = replyToMessageId
        } else {
            dict["replyToMessageId"] = NSNull()
        }
        
        return dict
    }
    
    // MARK: - Legacy Firebase Conversion (backward compatibility)
    init?(from dictionary: [String: Any], id: String) {
        guard let senderId = dictionary["senderId"] as? String,
              let senderName = dictionary["senderName"] as? String,
              let text = dictionary["text"] as? String else {
            return nil
        }
        
        self.id = id
        self.conversationId = dictionary["chatId"] as? String ?? dictionary["conversationId"] as? String ?? ""
        self.senderId = senderId
        self.senderName = senderName
        self.text = text
        self.timestamp = Date(timeIntervalSince1970: dictionary["timestamp"] as? TimeInterval ?? 0)
        self.type = MessageType(rawValue: dictionary["type"] as? String ?? "text") ?? .text
        self.mediaUrl = dictionary["mediaUrl"] as? String
        self.replyToMessageId = dictionary["replyToMessageId"] as? String
        self.deliveryStatus = nil
        self.readBy = nil
        self.finalDeliveryStatus = nil
        self.isDeleted = dictionary["isDeleted"] as? Bool ?? false
        self.isEdited = dictionary["isEdited"] as? Bool ?? false
        self.editedAt = nil
        self.deletedFor = dictionary["deletedFor"] as? [String]
        self.read = dictionary["read"] as? Bool ?? false
        self.actionItemId = dictionary["actionItemId"] as? String
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "conversationId": conversationId,
            "senderId": senderId,
            "senderName": senderName,
            "text": text,
            "timestamp": timestamp.timeIntervalSince1970,
            "type": type.rawValue,
            "isDeleted": isDeleted,
            "isEdited": isEdited,
            "read": read
        ]
        
        if let mediaUrl = mediaUrl {
            dict["mediaUrl"] = mediaUrl
        }
        if let replyToMessageId = replyToMessageId {
            dict["replyToMessageId"] = replyToMessageId
        }
        if let actionItemId = actionItemId {
            dict["actionItemId"] = actionItemId
        }
        if let editedAt = editedAt {
            dict["editedAt"] = editedAt.timeIntervalSince1970
        }
        if let deletedFor = deletedFor {
            dict["deletedFor"] = deletedFor
        }
        
        return dict
    }
}

// MARK: - User Profile Model
struct UserProfile: Identifiable, Codable {
    var id: String
    var email: String
    var displayName: String
    var photoURL: String?
    var createdAt: Date
    var hasCompletedProfileSetup: Bool
    
    init(id: String, email: String, displayName: String? = nil, photoURL: String? = nil, createdAt: Date = Date(), hasCompletedProfileSetup: Bool = false) {
        self.id = id
        self.email = email
        self.displayName = displayName ?? email.components(separatedBy: "@").first ?? "User"
        self.photoURL = photoURL
        self.createdAt = createdAt
        self.hasCompletedProfileSetup = hasCompletedProfileSetup
    }
    
    // MARK: - Firebase Conversion
    init?(from dictionary: [String: Any], id: String) {
        guard let email = dictionary["email"] as? String else { return nil }
        
        self.id = id
        self.email = email
        self.displayName = dictionary["displayName"] as? String ?? email.components(separatedBy: "@").first ?? "User"
        self.photoURL = dictionary["photoURL"] as? String
        self.createdAt = Date(timeIntervalSince1970: dictionary["createdAt"] as? TimeInterval ?? 0)
        self.hasCompletedProfileSetup = dictionary["hasCompletedProfileSetup"] as? Bool ?? false
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "email": email,
            "displayName": displayName,
            "photoURL": photoURL ?? "",
            "createdAt": createdAt.timeIntervalSince1970,
            "hasCompletedProfileSetup": hasCompletedProfileSetup
        ]
    }
}

// MARK: - Mentioned Message Model
struct MentionedMessage: Identifiable, Codable {
    var id: String
    var messageId: String
    var conversationId: String
    var conversationTitle: String
    var messageText: String
    var senderId: String
    var senderName: String
    var timestamp: Date
    var isRead: Bool
    var reason: Reason
    
    init(id: String = UUID().uuidString, messageId: String, conversationId: String, conversationTitle: String, messageText: String, senderId: String, senderName: String, timestamp: Date = Date(), isRead: Bool = false, reason: Reason) {
        self.id = id
        self.messageId = messageId
        self.conversationId = conversationId
        self.conversationTitle = conversationTitle
        self.messageText = messageText
        self.senderId = senderId
        self.senderName = senderName
        self.timestamp = timestamp
        self.isRead = isRead
        self.reason = reason
    }
    
    enum Reason: String, Codable {
        case mentioned // @mentioned in message
        case starred   // user starred/flagged message
    }
    
    // MARK: - Firebase Conversion
    init?(from dictionary: [String: Any], id: String) {
        guard let messageId = dictionary["messageId"] as? String,
              let messageText = dictionary["messageText"] as? String,
              let senderId = dictionary["senderId"] as? String,
              let senderName = dictionary["senderName"] as? String else {
            return nil
        }
        
        // Support both old chatId and new conversationId for backward compatibility
        let conversationId = dictionary["conversationId"] as? String ?? dictionary["chatId"] as? String ?? ""
        let conversationTitle = dictionary["conversationTitle"] as? String ?? dictionary["chatTitle"] as? String ?? "Chat"
        
        let reasonString = dictionary["reason"] as? String ?? "mentioned"
        let reason = Reason(rawValue: reasonString) ?? .mentioned
        
        self.id = id
        self.messageId = messageId
        self.conversationId = conversationId
        self.conversationTitle = conversationTitle
        self.messageText = messageText
        self.senderId = senderId
        self.senderName = senderName
        self.timestamp = Date(timeIntervalSince1970: dictionary["timestamp"] as? TimeInterval ?? 0)
        self.isRead = dictionary["isRead"] as? Bool ?? false
        self.reason = reason
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "messageId": messageId,
            "conversationId": conversationId,
            "conversationTitle": conversationTitle,
            "messageText": messageText,
            "senderId": senderId,
            "senderName": senderName,
            "timestamp": timestamp.timeIntervalSince1970,
            "isRead": isRead,
            "reason": reason.rawValue
        ]
    }
}


// MARK: - Conversation Metadata (RTDB)
struct ConversationRealtimeMetadata: Codable {
    var lastActivity: Double
    var typingUsers: [String: Double]
    
    init(lastActivity: Double = Date().timeIntervalSince1970 * 1000, typingUsers: [String: Double] = [:]) {
        self.lastActivity = lastActivity
        self.typingUsers = typingUsers
    }
    
    // RTDB Conversion
    init?(from dictionary: [String: Any]) {
        self.lastActivity = dictionary["lastActivity"] as? Double ?? Date().timeIntervalSince1970 * 1000
        self.typingUsers = dictionary["typingUsers"] as? [String: Double] ?? [:]
    }
    
    func toDictionary() -> [String: Any] {
        return [
            "lastActivity": lastActivity,
            "typingUsers": typingUsers
        ]
    }
}

// MARK: - FUTURE: Task Management (Action Items) - Currently Commented Out
/*
struct ActionItem: Identifiable, Codable {
    var id: String
    var title: String
    var isCompleted: Bool
    var dueDate: Date?
    var priority: Priority
    var chatId: String?
    var createdAt: Date
    
    init(id: String = UUID().uuidString, title: String, isCompleted: Bool = false, dueDate: Date? = nil, priority: Priority = .medium, chatId: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.priority = priority
        self.chatId = chatId
        self.createdAt = createdAt
    }
    
    enum Priority: String, Codable {
        case low, medium, high
    }
    
    // MARK: - Firebase Conversion
    init?(from dictionary: [String: Any], id: String) {
        guard let title = dictionary["title"] as? String else { return nil }
        
        let priorityString = dictionary["priority"] as? String ?? "medium"
        let priority = Priority(rawValue: priorityString) ?? .medium
        
        let dueDate: Date? = if let timestamp = dictionary["dueDate"] as? TimeInterval, timestamp > 0 {
            Date(timeIntervalSince1970: timestamp)
        } else {
            nil
        }
        
        let createdAt: Date = if let timestamp = dictionary["createdAt"] as? TimeInterval, timestamp > 0 {
            Date(timeIntervalSince1970: timestamp)
        } else {
            Date()
        }
        
        self.id = id
        self.title = title
        self.isCompleted = dictionary["isCompleted"] as? Bool ?? false
        self.dueDate = dueDate
        self.priority = priority
        self.chatId = dictionary["chatId"] as? String
        self.createdAt = createdAt
    }
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "title": title,
            "isCompleted": isCompleted,
            "priority": priority.rawValue,
            "dueDate": dueDate?.timeIntervalSince1970 ?? 0,
            "createdAt": createdAt.timeIntervalSince1970
        ]
        
        if let chatId = chatId {
            dict["chatId"] = chatId
        }
        
        return dict
    }
}
*/


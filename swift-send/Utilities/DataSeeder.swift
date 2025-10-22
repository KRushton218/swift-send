//
//  DataSeeder.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//

import Foundation
import FirebaseDatabase

class DataSeeder {
    private let realtimeManager = RealtimeManager()
    private let messagingManager = MessagingManager()
    private let profileManager = UserProfileManager()
    
    func seedSampleData(for userId: String) async {
        do {
            // Create demo user profiles
            try await profileManager.createUserProfile(
                userId: "demo_user_1",
                email: "alice@example.com",
                displayName: "Alice"
            )
            
            try await profileManager.createUserProfile(
                userId: "demo_user_2",
                email: "bob@example.com",
                displayName: "Bob"
            )
            
            // Create first chat with messages
            let chat1Id = try await messagingManager.createChat(
                participants: [userId, "demo_user_1"],
                title: "Project Planning",
                createdBy: userId
            )
            
            // Add messages to first chat
            _ = try await messagingManager.sendMessage(
                chatId: chat1Id,
                senderId: "demo_user_1",
                senderName: "Alice",
                text: "Hey! How's the project coming along?"
            )
            
            try await Task.sleep(nanoseconds: 100_000_000) // Small delay
            
            _ = try await messagingManager.sendMessage(
                chatId: chat1Id,
                senderId: userId,
                senderName: "You",
                text: "Going well! Just finishing up the authentication flow."
            )
            
            try await Task.sleep(nanoseconds: 100_000_000)
            
            _ = try await messagingManager.sendMessage(
                chatId: chat1Id,
                senderId: "demo_user_1",
                senderName: "Alice",
                text: "Great! Let's discuss the timeline for the new feature"
            )
            
            // Create second chat with messages
            let chat2Id = try await messagingManager.createChat(
                participants: [userId, "demo_user_2"],
                title: "Team Standup",
                createdBy: userId
            )
            
            _ = try await messagingManager.sendMessage(
                chatId: chat2Id,
                senderId: "demo_user_2",
                senderName: "Bob",
                text: "Morning! Ready for standup?"
            )
            
            try await Task.sleep(nanoseconds: 100_000_000)
            
            _ = try await messagingManager.sendMessage(
                chatId: chat2Id,
                senderId: userId,
                senderName: "You",
                text: "Yes! Daily sync at 10 AM"
            )
            
            // Add sample action items
            // Link action item 1 to Project Planning chat
            let actionItem1Data: [String: Any] = [
                "title": "Review pull request #123",
                "isCompleted": false,
                "dueDate": Date().addingTimeInterval(86400).timeIntervalSince1970,
                "priority": "high",
                "chatId": chat1Id
            ]
            
            // Link action item 2 to Team Standup chat
            let actionItem2Data: [String: Any] = [
                "title": "Update documentation",
                "isCompleted": false,
                "dueDate": Date().addingTimeInterval(172800).timeIntervalSince1970,
                "priority": "medium",
                "chatId": chat2Id
            ]
            
            // Action item 3 - no due date, no chat link
            let actionItem3Data: [String: Any] = [
                "title": "Fix bug in login flow",
                "isCompleted": true,
                "priority": "high",
                "dueDate": 0
            ]
            
            _ = try await realtimeManager.createItem(
                at: "users/\(userId)/actionItems",
                data: actionItem1Data
            )
            
            _ = try await realtimeManager.createItem(
                at: "users/\(userId)/actionItems",
                data: actionItem2Data
            )
            
            _ = try await realtimeManager.createItem(
                at: "users/\(userId)/actionItems",
                data: actionItem3Data
            )
            
            print("✅ Sample data seeded successfully!")
        } catch {
            print("❌ Error seeding data: \(error.localizedDescription)")
        }
    }
}


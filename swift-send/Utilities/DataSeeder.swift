//
//  DataSeeder.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//  Updated for hybrid architecture on 10/23/25.
//

import Foundation
import FirebaseDatabase
import FirebaseFirestore

class DataSeeder {
    private let realtimeManager = RealtimeManager()
    private let messagingManager = MessagingManager()
    private let profileManager = UserProfileManager()
    
    func seedSampleData(for userId: String) async {
        do {
            print("🌱 Starting to seed sample data...")
            print("⚠️  Note: Seeding data with current user only (demo users require separate authentication)")
            
            // Create a personal note/reminder conversation
            print("Creating personal notes conversation...")
            let notesId = try await messagingManager.createConversation(
                type: .direct,
                name: "Personal Notes",
                memberIds: [userId],
                createdBy: userId
            )
            
            // Add some sample notes
            try await Task.sleep(nanoseconds: 100_000_000)
            _ = try await messagingManager.sendMessage(
                conversationId: notesId,
                text: "Welcome to Swift Send! 🚀"
            )
            
            try await Task.sleep(nanoseconds: 100_000_000)
            _ = try await messagingManager.sendMessage(
                conversationId: notesId,
                text: "This is a sample conversation to demonstrate the app's features."
            )
            
            try await Task.sleep(nanoseconds: 100_000_000)
            _ = try await messagingManager.sendMessage(
                conversationId: notesId,
                text: "To chat with others, they need to create accounts and you can start conversations with them."
            )
            
            print("✅ Sample data seeded successfully!")
            print("   - Created 1 personal notes conversation")
            print("   - Added 3 sample messages")
            print("")
            print("💡 To test with multiple users:")
            print("   1. Create additional Firebase Auth accounts")
            print("   2. Log in with different accounts on separate devices/simulators")
            print("   3. Use the 'New Chat' button to start conversations")
        } catch {
            print("❌ Error seeding data: \(error.localizedDescription)")
        }
    }
    
    /// Seed data for testing the new hybrid architecture
    /// Creates a large conversation with many messages to test pagination
    func seedHybridArchitectureTest(for userId: String) async {
        do {
            print("🔬 Seeding hybrid architecture test data...")
            
            // Create a test conversation with just the current user
            let testGroupId = try await messagingManager.createConversation(
                type: .direct,
                name: "Architecture Test",
                memberIds: [userId],
                createdBy: userId
            )
            
            // Send 60 messages to test pagination and archiving
            print("Creating 60 test messages...")
            for i in 1...60 {
                try await Task.sleep(nanoseconds: 50_000_000)
                
                _ = try await messagingManager.sendMessage(
                    conversationId: testGroupId,
                    text: "Test message #\(i) - Testing hybrid RTDB + Firestore architecture with pagination and automatic archiving after 50 messages"
                )
                
                if i % 10 == 0 {
                    print("  Created \(i)/60 messages...")
                }
            }
            
            print("✅ Hybrid architecture test data seeded successfully!")
            print("   - Created 1 test conversation")
            print("   - Added 60 messages (50 active in RTDB, 10+ archived in Firestore)")
        } catch {
            print("❌ Error seeding test data: \(error.localizedDescription)")
        }
    }
}


//
//  PresenceManager.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/23/25.
//  Simplified to use onlineUsers set for fast presence checks.
//

import Foundation
import FirebaseDatabase
import FirebaseAuth

/// Manager for user presence tracking in RTDB
/// Uses simple onlineUsers set for fast online/offline detection
class PresenceManager {
    private let rtdb = Database.database().reference()
    private var onlineRef: DatabaseReference?
    private var connectedRef: DatabaseReference?
    private var connectionStateHandle: DatabaseHandle?
    
    // MARK: - Setup Presence
    
    /// Set up presence tracking for the current user
    /// Automatically adds/removes user from onlineUsers set based on connection
    func setupPresence() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        onlineRef = rtdb.child("onlineUsers").child(userId)
        connectedRef = Database.database().reference(withPath: ".info/connected")
        
        // Listen to connection state changes
        connectionStateHandle = connectedRef?.observe(.value) { [weak self] snapshot in
            guard let self = self,
                  let connected = snapshot.value as? Bool,
                  connected else { return }
            
            // When connected, set up auto-removal on disconnect
            self.onlineRef?.onDisconnectRemoveValue()
            
            // Set online status (just set to true)
            self.onlineRef?.setValue(true)
        }
    }
    
    /// Manually go offline (removes from online set)
    func goOffline() async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        try await rtdb.child("onlineUsers").child(userId).removeValue()
    }
    
    /// Manually go online (adds to online set)
    func goOnline() async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        try await rtdb.child("onlineUsers").child(userId).setValue(true)
    }
    
    /// Clean up presence tracking
    func cleanup() {
        if let handle = connectionStateHandle {
            connectedRef?.removeObserver(withHandle: handle)
        }
        connectionStateHandle = nil
        onlineRef = nil
        connectedRef = nil
    }
    
    // MARK: - Observe Presence
    
    /// Observe if a user is online (fast boolean check)
    func observePresence(userId: String, completion: @escaping (Bool) -> Void) -> DatabaseHandle {
        return rtdb.child("onlineUsers")
            .child(userId)
            .observe(.value) { snapshot in
                completion(snapshot.exists())
            }
    }
    
    /// Remove presence observer
    func removePresenceObserver(userId: String, handle: DatabaseHandle) {
        rtdb.child("onlineUsers")
            .child(userId)
            .removeObserver(withHandle: handle)
    }
    
    /// Observe presence for multiple users
    func observePresenceForUsers(
        userIds: [String],
        completion: @escaping ([String: Bool]) -> Void
    ) -> [String: DatabaseHandle] {
        var handles: [String: DatabaseHandle] = [:]
        var presenceData: [String: Bool] = [:]
        
        for userId in userIds {
            let handle = rtdb.child("onlineUsers")
                .child(userId)
                .observe(.value) { snapshot in
                    presenceData[userId] = snapshot.exists()
                    completion(presenceData)
                }
            handles[userId] = handle
        }
        
        return handles
    }
    
    // MARK: - Typing Indicators (kept separate, per-conversation)
    
    /// Set typing indicator for current user in a conversation
    func setTypingIndicator(conversationId: String, isTyping: Bool) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let typingRef = rtdb.child("conversations")
            .child(conversationId)
            .child("metadata")
            .child("typingUsers")
            .child(userId)
        
        if isTyping {
            try await typingRef.setValue(ServerValue.timestamp())
        } else {
            try await typingRef.removeValue()
        }
    }
    
    /// Clear typing indicator for current user
    func clearTypingIndicator(conversationId: String) async throws {
        try await setTypingIndicator(conversationId: conversationId, isTyping: false)
    }
    
    /// Observe typing indicators in a conversation
    func observeTypingIndicators(
        conversationId: String,
        completion: @escaping ([String]) -> Void
    ) -> DatabaseHandle {
        return rtdb.child("conversations")
            .child(conversationId)
            .child("metadata")
            .child("typingUsers")
            .observe(.value) { snapshot in
                guard let typingUsers = snapshot.value as? [String: Any] else {
                    completion([])
                    return
                }
                
                // Filter out stale typing indicators (older than 5 seconds)
                let currentTime = Date().timeIntervalSince1970 * 1000
                let activeTypingUsers = typingUsers.compactMap { userId, timestamp -> String? in
                    guard let timestamp = timestamp as? Double,
                          currentTime - timestamp < 5000 else {
                        return nil
                    }
                    return userId
                }
                
                completion(activeTypingUsers)
            }
    }
    
    /// Remove typing indicator observer
    func removeTypingObserver(conversationId: String, handle: DatabaseHandle) {
        rtdb.child("conversations")
            .child(conversationId)
            .child("metadata")
            .child("typingUsers")
            .removeObserver(withHandle: handle)
    }
}
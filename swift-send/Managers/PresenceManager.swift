//
//  PresenceManager.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/23/25.
//

import Foundation
import FirebaseDatabase
import FirebaseAuth

/// Manager for user presence tracking in RTDB
/// Handles online/offline status and typing indicators
class PresenceManager {
    private let rtdb = Database.database().reference()
    private var presenceRef: DatabaseReference?
    private var connectedRef: DatabaseReference?
    private var connectionStateHandle: DatabaseHandle?
    
    // MARK: - Setup Presence
    
    /// Set up presence tracking for the current user
    /// Automatically updates online/offline status based on connection
    func setupPresence() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        presenceRef = rtdb.child("presence").child(userId)
        connectedRef = Database.database().reference(withPath: ".info/connected")
        
        // Listen to connection state changes
        connectionStateHandle = connectedRef?.observe(.value) { [weak self] snapshot in
            guard let self = self,
                  let connected = snapshot.value as? Bool,
                  connected else { return }
            
            // When connected, set up disconnect handler
            self.presenceRef?.onDisconnectUpdateChildValues([
                "status": PresenceStatus.offline.rawValue,
                "lastSeen": ServerValue.timestamp()
            ])
            
            // Set online status
            self.presenceRef?.updateChildValues([
                "status": PresenceStatus.online.rawValue,
                "lastSeen": ServerValue.timestamp()
            ])
        }
    }
    
    /// Update presence status manually
    func updatePresenceStatus(_ status: PresenceStatus) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        try await rtdb.child("presence")
            .child(userId)
            .updateChildValues([
                "status": status.rawValue,
                "lastSeen": ServerValue.timestamp()
            ])
    }
    
    /// Set current conversation user is viewing
    func setCurrentConversation(_ conversationId: String?) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        if let conversationId = conversationId {
            try await rtdb.child("presence")
                .child(userId)
                .child("currentConversation")
                .setValue(conversationId)
        } else {
            try await rtdb.child("presence")
                .child(userId)
                .child("currentConversation")
                .removeValue()
        }
    }
    
    /// Observe presence for a specific user
    func observePresence(userId: String, completion: @escaping (UserPresence?) -> Void) -> DatabaseHandle {
        return rtdb.child("presence")
            .child(userId)
            .observe(.value) { snapshot in
                guard let data = snapshot.value as? [String: Any],
                      let presence = UserPresence(from: data) else {
                    completion(nil)
                    return
                }
                completion(presence)
            }
    }
    
    /// Observe presence for multiple users
    func observePresenceForUsers(
        userIds: [String],
        completion: @escaping ([String: UserPresence]) -> Void
    ) -> [String: DatabaseHandle] {
        var handles: [String: DatabaseHandle] = [:]
        var presenceData: [String: UserPresence] = [:]
        
        for userId in userIds {
            let handle = rtdb.child("presence")
                .child(userId)
                .observe(.value) { snapshot in
                    if let data = snapshot.value as? [String: Any],
                       let presence = UserPresence(from: data) {
                        presenceData[userId] = presence
                    } else {
                        presenceData.removeValue(forKey: userId)
                    }
                    completion(presenceData)
                }
            handles[userId] = handle
        }
        
        return handles
    }
    
    /// Remove presence observer
    func removePresenceObserver(userId: String, handle: DatabaseHandle) {
        rtdb.child("presence")
            .child(userId)
            .removeObserver(withHandle: handle)
    }
    
    // MARK: - Typing Indicators
    
    /// Set typing indicator for a conversation
    func setTypingIndicator(conversationId: String, isTyping: Bool) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let typingRef = rtdb.child("conversations")
            .child(conversationId)
            .child("metadata")
            .child("typingUsers")
            .child(userId)
        
        if isTyping {
            try await typingRef.setValue(ServerValue.timestamp())
            // Auto-remove after 5 seconds on disconnect
            try await typingRef.onDisconnectRemoveValue()
        } else {
            try await typingRef.removeValue()
        }
    }
    
    /// Clear typing indicator
    func clearTypingIndicator(conversationId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        try await rtdb.child("conversations")
            .child(conversationId)
            .child("metadata")
            .child("typingUsers")
            .child(userId)
            .removeValue()
    }
    
    /// Observe typing indicators for a conversation
    func observeTypingIndicators(
        conversationId: String,
        completion: @escaping ([String]) -> Void
    ) -> DatabaseHandle {
        return rtdb.child("conversations")
            .child(conversationId)
            .child("metadata")
            .child("typingUsers")
            .observe(.value) { snapshot in
                guard let userId = Auth.auth().currentUser?.uid,
                      let typingDict = snapshot.value as? [String: Double] else {
                    completion([])
                    return
                }
                
                let currentTime = Date().timeIntervalSince1970 * 1000
                
                // Filter out stale typing indicators (older than 5 seconds) and current user
                let typingUsers = typingDict
                    .filter { currentTime - $0.value < 5000 && $0.key != userId }
                    .map { $0.key }
                
                completion(typingUsers)
            }
    }
    
    /// Remove typing observer
    func removeTypingObserver(conversationId: String, handle: DatabaseHandle) {
        rtdb.child("conversations")
            .child(conversationId)
            .child("metadata")
            .child("typingUsers")
            .removeObserver(withHandle: handle)
    }
    
    // MARK: - Cleanup
    
    /// Clean up presence tracking
    func cleanup() {
        guard Auth.auth().currentUser?.uid != nil else { return }
        
        // Remove connection state listener
        if let handle = connectionStateHandle {
            connectedRef?.removeObserver(withHandle: handle)
        }
        
        // Set offline status
        presenceRef?.updateChildValues([
            "status": PresenceStatus.offline.rawValue,
            "lastSeen": ServerValue.timestamp()
        ])
        
        // Cancel disconnect handlers
        presenceRef?.cancelDisconnectOperations()
        
        presenceRef = nil
        connectedRef = nil
        connectionStateHandle = nil
    }
    
    deinit {
        cleanup()
    }
}


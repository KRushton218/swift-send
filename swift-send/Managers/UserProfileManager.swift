//
//  UserProfileManager.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//

import Foundation
import FirebaseAuth
import FirebaseDatabase

class UserProfileManager {
    private let realtimeManager = RealtimeManager()
    
    // MARK: - Create/Update Profile
    func createUserProfile(userId: String, email: String, displayName: String? = nil, photoURL: String? = nil) async throws {
        let profileData: [String: Any] = [
            "email": email,
            "displayName": displayName ?? email.components(separatedBy: "@").first ?? "User",
            "photoURL": photoURL ?? "",
            "createdAt": Date().timeIntervalSince1970
        ]
        
        try await realtimeManager.setData(at: "userProfiles/\(userId)", data: profileData)
    }
    
    func updateDisplayName(userId: String, displayName: String) async throws {
        try await realtimeManager.updateData(at: "userProfiles/\(userId)", data: ["displayName": displayName])
        
        // Also update Firebase Auth profile
        if let user = Auth.auth().currentUser {
            let changeRequest = user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()
        }
    }
    
    func updatePhotoURL(userId: String, photoURL: String) async throws {
        try await realtimeManager.updateData(at: "userProfiles/\(userId)", data: ["photoURL": photoURL])
        
        // Also update Firebase Auth profile
        if let user = Auth.auth().currentUser {
            let changeRequest = user.createProfileChangeRequest()
            changeRequest.photoURL = URL(string: photoURL)
            try await changeRequest.commitChanges()
        }
    }
    
    // MARK: - Fetch Profile
    func getUserProfile(userId: String) async throws -> UserProfile? {
        do {
            guard let data = try await realtimeManager.getData(at: "userProfiles/\(userId)") else {
                // Profile doesn't exist, try to create one from Auth
                if let user = Auth.auth().currentUser {
                    try await createUserProfile(
                        userId: userId,
                        email: user.email ?? "",
                        displayName: user.displayName,
                        photoURL: user.photoURL?.absoluteString
                    )
                    // Retry getting the profile
                    if let data = try await realtimeManager.getData(at: "userProfiles/\(userId)") {
                        return UserProfile(
                            id: userId,
                            email: data["email"] as? String ?? "",
                            displayName: data["displayName"] as? String ?? "User",
                            photoURL: data["photoURL"] as? String,
                            createdAt: Date(timeIntervalSince1970: data["createdAt"] as? TimeInterval ?? 0)
                        )
                    }
                }
                return nil
            }
            
            return UserProfile(
                id: userId,
                email: data["email"] as? String ?? "",
                displayName: data["displayName"] as? String ?? "User",
                photoURL: data["photoURL"] as? String,
                createdAt: Date(timeIntervalSince1970: data["createdAt"] as? TimeInterval ?? 0)
            )
        } catch {
            // If offline, return nil gracefully instead of throwing
            print("Error fetching user profile: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Batch Fetch Profiles
    func getUserProfiles(userIds: [String]) async throws -> [String: UserProfile] {
        var profiles: [String: UserProfile] = [:]
        
        for userId in userIds {
            if let profile = try await getUserProfile(userId: userId) {
                profiles[userId] = profile
            }
        }
        
        return profiles
    }
    
    // MARK: - Find User by Email
    func findUserByEmail(email: String) async throws -> UserProfile? {
        // Query all user profiles to find matching email
        // Note: This is inefficient for large user bases. In production, use:
        // - Firebase query with indexing on email field
        // - Or a dedicated search service like Algolia
        let snapshot = try await Database.database().reference().child("userProfiles").getData()
        
        guard let profiles = snapshot.value as? [String: [String: Any]] else {
            return nil
        }
        
        for (userId, profileData) in profiles {
            if let userEmail = profileData["email"] as? String,
               userEmail.lowercased() == email.lowercased() {
                return UserProfile(
                    id: userId,
                    email: userEmail,
                    displayName: profileData["displayName"] as? String ?? "User",
                    photoURL: profileData["photoURL"] as? String,
                    createdAt: Date(timeIntervalSince1970: profileData["createdAt"] as? TimeInterval ?? 0)
                )
            }
        }
        
        return nil
    }
    
    // MARK: - Search Users
    func searchUsers(query: String) async throws -> [UserProfile] {
        // For now, this is a simple implementation
        // In production, you'd want to use Firebase's querying capabilities
        // or a dedicated search service like Algolia
        
        // This is a placeholder - you'd need to implement proper search
        return []
    }
}


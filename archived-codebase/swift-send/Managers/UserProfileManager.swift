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
        let profile = UserProfile(
            id: userId,
            email: email,
            displayName: displayName,
            photoURL: photoURL
        )
        
        try await realtimeManager.setData(at: "userProfiles/\(userId)", data: profile.toDictionary())
    }
    
    func updateDisplayName(userId: String, displayName: String) async throws {
        try await realtimeManager.updateData(at: "userProfiles/\(userId)", data: [
            "displayName": displayName,
            "hasCompletedProfileSetup": true
        ])
        
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
                        return UserProfile(from: data, id: userId)
                    }
                }
                return nil
            }
            
            return UserProfile(from: data, id: userId)
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
                return UserProfile(from: profileData, id: userId)
            }
        }
        
        return nil
    }
    
    // MARK: - Search Users
    func searchUsers(query: String, limit: Int = 20) async throws -> [UserProfile] {
        guard !query.isEmpty else { return [] }
        
        let snapshot = try await Database.database().reference().child("userProfiles").getData()
        guard let profiles = snapshot.value as? [String: [String: Any]] else {
            return []
        }
        
        let lowercaseQuery = query.lowercased()
        var matchedProfiles: [UserProfile] = []
        
        for (userId, profileData) in profiles {
            guard let profile = UserProfile(from: profileData, id: userId) else { continue }
            
            // Search by display name (case-insensitive, partial match)
            let displayNameMatch = profile.displayName.lowercased().contains(lowercaseQuery)
            
            // Search by email (case-insensitive, partial match)
            let emailMatch = profile.email.lowercased().contains(lowercaseQuery)
            
            if displayNameMatch || emailMatch {
                matchedProfiles.append(profile)
            }
            
            // Limit results
            if matchedProfiles.count >= limit {
                break
            }
        }
        
        // Sort by relevance: exact matches first, then partial matches
        matchedProfiles.sort { profile1, profile2 in
            let name1Lower = profile1.displayName.lowercased()
            let name2Lower = profile2.displayName.lowercased()
            let email1Lower = profile1.email.lowercased()
            let email2Lower = profile2.email.lowercased()
            
            // Exact display name match gets highest priority
            if name1Lower == lowercaseQuery && name2Lower != lowercaseQuery {
                return true
            }
            if name2Lower == lowercaseQuery && name1Lower != lowercaseQuery {
                return false
            }
            
            // Exact email match gets second priority
            if email1Lower == lowercaseQuery && email2Lower != lowercaseQuery {
                return true
            }
            if email2Lower == lowercaseQuery && email1Lower != lowercaseQuery {
                return false
            }
            
            // Display name starts with query
            let name1Starts = name1Lower.hasPrefix(lowercaseQuery)
            let name2Starts = name2Lower.hasPrefix(lowercaseQuery)
            if name1Starts && !name2Starts {
                return true
            }
            if name2Starts && !name1Starts {
                return false
            }
            
            // Otherwise alphabetical by display name
            return profile1.displayName < profile2.displayName
        }
        
        return matchedProfiles
    }
}


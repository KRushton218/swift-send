//
//  AuthManager.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//

import Foundation
import Combine
import FirebaseAuth

class AuthManager: ObservableObject {
    @Published var user: User?
    @Published var isAuthenticated = false
    @Published var needsProfileSetup = false
    
    private var authStateHandler: AuthStateDidChangeListenerHandle?
    private var profileManager = UserProfileManager()
    
    init() {
        // Listen for auth state changes
        authStateHandler = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.user = user
            self?.isAuthenticated = user != nil
            
            // Check if user needs to set up profile
            if let user = user {
                Task {
                    await self?.checkProfileSetup(userId: user.uid)
                }
            }
        }
    }
    
    deinit {
        if let handler = authStateHandler {
            Auth.auth().removeStateDidChangeListener(handler)
        }
    }
    
    // Sign up with email
    func signUp(email: String, password: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        self.user = result.user
        
        // Create initial user profile
        try await profileManager.createUserProfile(
            userId: result.user.uid,
            email: email
        )
        
        // User needs to set display name
        await MainActor.run {
            self.needsProfileSetup = true
        }
    }
    
    // Sign in with email
    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        self.user = result.user
    }
    
    // Sign out
    func signOut() throws {
        try Auth.auth().signOut()
        self.user = nil
        self.needsProfileSetup = false
    }
    
    // Check if profile setup is needed
    private func checkProfileSetup(userId: String) async {
        do {
            let profile = try await profileManager.getUserProfile(userId: userId)
            await MainActor.run {
                // If display name is just email prefix, prompt for setup
                let emailPrefix = profile?.email.components(separatedBy: "@").first ?? ""
                self.needsProfileSetup = profile?.displayName == emailPrefix
            }
        } catch {
            print("Error checking profile setup: \(error.localizedDescription)")
        }
    }
}


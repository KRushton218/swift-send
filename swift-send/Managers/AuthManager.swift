//
//  AuthManager.swift
//  swift-send
//

import Foundation
import Combine
import FirebaseAuth

@MainActor
class AuthManager: ObservableObject {
    @Published var user: User?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var authStateHandler: AuthStateDidChangeListenerHandle?
    private let realtimeManager = RealtimeManager.shared

    init() {
        registerAuthStateHandler()
    }

    deinit {
        if let handle = authStateHandler {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    private func registerAuthStateHandler() {
        authStateHandler = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user

                // Set up presence when user signs in
                if let user = user {
                    await self?.setupUserOnSignIn(userId: user.uid, email: user.email ?? "")
                }
            }
        }
    }

    private func setupUserOnSignIn(userId: String, email: String) async {
        do {
            // Register user in RTDB if not exists
            let existingUser = try await realtimeManager.getUser(userId: userId)
            if existingUser == nil {
                try await realtimeManager.registerUser(userId: userId, email: email, displayName: email)
            }

            // Set presence
            try await realtimeManager.setPresence(userId: userId, name: email)

            // Request notification permissions
            await NotificationManager.shared.requestPermission()
        } catch {
            print("Error setting up user: \(error)")
        }
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil

        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func signUp(email: String, password: String) async {
        isLoading = true
        errorMessage = nil

        do {
            try await Auth.auth().createUser(withEmail: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func signOut() {
        // Update last online before signing out
        if let userId = user?.uid {
            Task {
                try? await realtimeManager.updateLastOnline(userId: userId)
            }
        }

        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

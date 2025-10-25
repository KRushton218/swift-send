//
//  AuthManager.swift
//  swift-send
//

import Foundation
import Combine
import FirebaseAuth
import UIKit

@MainActor
class AuthManager: ObservableObject {
    @Published var user: User?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var authStateHandler: AuthStateDidChangeListenerHandle?
    private let realtimeManager = RealtimeManager.shared
    nonisolated(unsafe) private var presenceHeartbeatTimer: Timer?
    private var lifecycleObservers: [NSObjectProtocol] = []

    init() {
        registerAuthStateHandler()
        setupLifecycleObservers()
    }

    deinit {
        if let handle = authStateHandler {
            Auth.auth().removeStateDidChangeListener(handle)
        }

        // Stop presence heartbeat timer
        presenceHeartbeatTimer?.invalidate()

        // Remove lifecycle observers
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
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

    private func setupLifecycleObservers() {
        // Observe when app enters background
        let backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleAppDidEnterBackground()
            }
        }
        lifecycleObservers.append(backgroundObserver)

        // Observe when app enters foreground
        let foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleAppWillEnterForeground()
            }
        }
        lifecycleObservers.append(foregroundObserver)
    }

    private func handleAppDidEnterBackground() async {
        // Stop heartbeat to save battery
        stopPresenceHeartbeat()

        // Mark as offline before going inactive
        if let userId = user?.uid {
            do {
                try await realtimeManager.setOffline(userId: userId)
            } catch {
                print("Error setting offline on background: \(error)")
            }
        }
    }

    private func handleAppWillEnterForeground() async {
        // Mark as online and resume heartbeat if user is signed in
        if let userId = user?.uid {
            do {
                try await realtimeManager.setOnline(userId: userId)
            } catch {
                print("Error setting online on foreground: \(error)")
            }
            startPresenceHeartbeat()
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

            // Start presence heartbeat to update every 1 second
            startPresenceHeartbeat()

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
        // Stop presence heartbeat
        stopPresenceHeartbeat()

        // Mark as offline before signing out
        if let userId = user?.uid {
            Task {
                try? await realtimeManager.setOffline(userId: userId)
            }
        }

        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Presence Heartbeat

    private func startPresenceHeartbeat() {
        // Stop any existing timer
        stopPresenceHeartbeat()

        // Create timer that fires every 1 second
        presenceHeartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let userId = self.user?.uid else { return }

                do {
                    try await self.realtimeManager.updateLastOnline(userId: userId)
                } catch {
                    print("Error updating presence heartbeat: \(error)")
                }
            }
        }
    }

    private func stopPresenceHeartbeat() {
        presenceHeartbeatTimer?.invalidate()
        presenceHeartbeatTimer = nil
    }
}

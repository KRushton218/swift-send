//
//  swift_sendApp.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//

import SwiftUI
import Firebase
import FirebaseDatabase

@main
struct swift_sendApp: App {
    @StateObject private var authManager = AuthManager()

    init() {
        FirebaseApp.configure()

        // Enable offline persistence for Realtime Database
        // This allows messages to be queued offline and synced when connection is restored
        Database.database().isPersistenceEnabled = true

        // Keep data synced even when offline (10MB cache)
        Database.database().persistenceCacheSizeBytes = 10 * 1024 * 1024
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
        }
    }
}

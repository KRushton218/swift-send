//
//  swift_sendApp.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//

import SwiftUI
import Firebase
import FirebaseDatabase
import FirebaseFirestore

@main
struct swift_sendApp: App {
    @StateObject private var authManager = AuthManager()
    
    init() {
        FirebaseApp.configure()
        
        // Enable offline persistence for Realtime Database
        Database.database().isPersistenceEnabled = true
        
        // Configure Firestore settings
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: FirestoreCacheSizeUnlimited as NSNumber)
        Firestore.firestore().settings = settings
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
        }
    }
}

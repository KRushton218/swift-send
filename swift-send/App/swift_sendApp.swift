//
//  swift_sendApp.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//

import SwiftUI
import Firebase

@main
struct swift_sendApp: App {
    @StateObject private var authManager = AuthManager()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
        }
    }
}

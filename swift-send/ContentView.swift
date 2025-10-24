//
//  ContentView.swift
//  swift-send
//

import SwiftUI
import FirebaseAuth

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        if authManager.user != nil {
            // Authenticated view - show messaging interface
            MainMessagingView()
        } else {
            // Not authenticated - show login
            LoginView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
}

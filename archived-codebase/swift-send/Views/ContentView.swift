//
//  ContentView.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//

import SwiftUI
import FirebaseAuth

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage = ""
    
    var body: some View {
        if authManager.isAuthenticated {
            if authManager.needsProfileSetup {
                // Show profile setup
                ProfileSetupView()
            } else {
                // User is logged in - show main view with chats and action items
                MainView()
            }
        } else {
            // Login screen
            VStack(spacing: 20) {
                Text("Login")
                    .font(.largeTitle)
                
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                HStack {
                    Button("Sign Up") {
                        Task {
                            do {
                                try await authManager.signUp(email: email, password: password)
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Sign In") {
                        Task {
                            do {
                                try await authManager.signIn(email: email, password: password)
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}

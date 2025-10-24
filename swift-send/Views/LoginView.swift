//
//  LoginView.swift
//  swift-send
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUpMode = false

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("Swift Send")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
            .padding(.bottom, 20)

            // Form fields
            VStack(spacing: 16) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
            }
            .padding(.horizontal)

            // Error message
            if let errorMessage = authManager.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Action button
            Button {
                Task {
                    if isSignUpMode {
                        await authManager.signUp(email: email, password: password)
                    } else {
                        await authManager.signIn(email: email, password: password)
                    }
                }
            } label: {
                if authManager.isLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    Text(isSignUpMode ? "Sign Up" : "Sign In")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .background(Color.blue)
            .cornerRadius(10)
            .padding(.horizontal)
            .disabled(authManager.isLoading || email.isEmpty || password.isEmpty)

            // Toggle mode
            Button {
                isSignUpMode.toggle()
                authManager.errorMessage = nil
            } label: {
                Text(isSignUpMode ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
        }
        .padding()
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}

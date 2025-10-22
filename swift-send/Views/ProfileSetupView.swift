//
//  ProfileSetupView.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//

import SwiftUI
import FirebaseAuth

struct ProfileSetupView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var displayName = ""
    @State private var isUpdating = false
    @State private var errorMessage = ""
    
    private var profileManager = UserProfileManager()
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Profile Icon
            Image(systemName: "person.circle.fill")
                .font(.system(size: 100))
                .foregroundColor(.blue)
            
            VStack(spacing: 12) {
                Text("Set Up Your Profile")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Choose a display name that others will see")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 16) {
                TextField("Display Name", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.name)
                    .autocapitalization(.words)
                    .padding(.horizontal)
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                Button(action: saveProfile) {
                    if isUpdating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Continue")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.horizontal)
                .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isUpdating)
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            // Pre-fill with email prefix
            if let email = authManager.user?.email {
                displayName = email.components(separatedBy: "@").first ?? ""
            }
        }
    }
    
    private func saveProfile() {
        guard let userId = authManager.user?.uid else { return }
        
        isUpdating = true
        errorMessage = ""
        
        Task {
            do {
                try await profileManager.updateDisplayName(
                    userId: userId,
                    displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                
                await MainActor.run {
                    authManager.needsProfileSetup = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to update profile: \(error.localizedDescription)"
                    isUpdating = false
                }
            }
        }
    }
}

#Preview {
    ProfileSetupView()
        .environmentObject(AuthManager())
}


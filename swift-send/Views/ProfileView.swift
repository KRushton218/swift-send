//
//  ProfileView.swift
//  swift-send
//
//  Created by Kiran Rushton on 10/22/25.
//

import SwiftUI
import FirebaseAuth

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var photoURL = ""
    @State private var isUpdating = false
    @State private var errorMessage = ""
    @State private var successMessage = ""
    
    private var profileManager = UserProfileManager()
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack {
                        Spacer()
                        ProfilePictureView(photoURL: photoURL.isEmpty ? nil : photoURL, size: 100)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                
                Section("Profile Information") {
                    TextField("Display Name", text: $displayName)
                        .textContentType(.name)
                        .autocapitalization(.words)
                    
                    TextField("Photo URL (optional)", text: $photoURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    
                    if let email = authManager.user?.email {
                        HStack {
                            Text("Email")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(email)
                        }
                    }
                }
                
                if !errorMessage.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                            
                            Button("Retry") {
                                errorMessage = ""
                                loadProfile()
                            }
                            .font(.caption)
                        }
                    }
                }
                
                if !successMessage.isEmpty {
                    Section {
                        Text(successMessage)
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                
                Section {
                    Button(action: saveProfile) {
                        if isUpdating {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            Text("Save Changes")
                        }
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isUpdating)
                }
                
                Section {
                    Button(role: .destructive) {
                        try? authManager.signOut()
                        dismiss()
                    } label: {
                        Text("Sign Out")
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadProfile()
            }
        }
    }
    
    private func loadProfile() {
        guard let userId = authManager.user?.uid else { return }
        
        // First, try to load from Firebase Auth
        if let user = authManager.user {
            displayName = user.displayName ?? ""
            if let photoURLString = user.photoURL?.absoluteString {
                photoURL = photoURLString
            }
        }
        
        // Then try to load from database (will update if available)
        Task {
            do {
                if let profile = try await profileManager.getUserProfile(userId: userId) {
                    await MainActor.run {
                        displayName = profile.displayName
                        photoURL = profile.photoURL ?? ""
                        errorMessage = "" // Clear any previous errors
                    }
                }
            } catch {
                // Only show error if we couldn't load from Auth either
                if displayName.isEmpty {
                    await MainActor.run {
                        errorMessage = "Unable to load profile. Please check your connection."
                    }
                }
            }
        }
    }
    
    private func saveProfile() {
        guard let userId = authManager.user?.uid else { return }
        
        isUpdating = true
        errorMessage = ""
        successMessage = ""
        
        Task {
            do {
                try await profileManager.updateDisplayName(
                    userId: userId,
                    displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                
                if !photoURL.isEmpty {
                    try await profileManager.updatePhotoURL(
                        userId: userId,
                        photoURL: photoURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                
                await MainActor.run {
                    successMessage = "Profile updated successfully!"
                    isUpdating = false
                }
                
                // Dismiss after a short delay
                try await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    dismiss()
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
    ProfileView()
        .environmentObject(AuthManager())
}


//
//  ProfileView.swift
//  swift-send
//

import SwiftUI
import FirebaseAuth

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var showPreferences = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Profile Image
                Circle()
                    .fill(Color.blue.gradient)
                    .frame(width: 120, height: 120)
                    .overlay {
                        Text(initials)
                            .font(.system(size: 48, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 40)

                // User Info
                VStack(spacing: 8) {
                    Text(displayName)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(email)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                // Settings Section
                VStack(spacing: 12) {
                    NavigationLink(destination: LanguagePreferencesView()) {
                        HStack {
                            Image(systemName: "globe")
                                .foregroundColor(.blue)
                                .frame(width: 30)
                            Text("Language & Translation")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)

                Spacer()

                // Sign Out Button
                Button {
                    authManager.signOut()
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign Out")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
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
        }
    }

    private var email: String {
        authManager.user?.email ?? "Unknown"
    }

    private var displayName: String {
        authManager.user?.email?.components(separatedBy: "@").first?.capitalized ?? "User"
    }

    private var initials: String {
        let name = displayName
        let components = name.components(separatedBy: " ")
        if components.count > 1 {
            let firstInitial = components[0].prefix(1)
            let lastInitial = components[1].prefix(1)
            return "\(firstInitial)\(lastInitial)".uppercased()
        } else {
            return String(name.prefix(2)).uppercased()
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(AuthManager())
}

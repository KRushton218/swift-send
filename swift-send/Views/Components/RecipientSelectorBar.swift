//
//  RecipientSelectorBar.swift
//  swift-send
//
//  Created on 10/23/25.
//  Reusable recipient selector component with search and chips.
//

import SwiftUI

/// Reusable recipient selector bar
/// Shows search field, selected recipients as chips, and search results
struct RecipientSelectorBar: View {
    @Binding var searchText: String
    @Binding var selectedRecipients: [UserProfile]
    let searchResults: [UserProfile]
    let isSearching: Bool
    let onAddRecipient: (UserProfile) -> Void
    let onRemoveRecipient: (UserProfile) -> Void
    let onAddByEmail: (String) -> Void
    let isValidEmail: (String) -> Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search by name or email", text: $searchText)
                    .textFieldStyle(.plain)
                    .autocapitalization(.none)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            
            // Selected recipients chips
            if !selectedRecipients.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedRecipients) { recipient in
                            RecipientChip(
                                recipient: recipient,
                                onRemove: {
                                    onRemoveRecipient(recipient)
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color(.systemBackground))
            }
            
            Divider()
            
            // Search results or empty state
            if isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if !searchText.isEmpty {
                if searchResults.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        
                        Text("No users found")
                            .font(.headline)
                        
                        Text("Try searching by name or email")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Option to add by email if it looks like an email
                        if isValidEmail(searchText) {
                            Button {
                                onAddByEmail(searchText)
                            } label: {
                                Label("Add \(searchText)", systemImage: "plus.circle.fill")
                            }
                            .buttonStyle(.bordered)
                            .padding(.top, 8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(searchResults) { user in
                                Button {
                                    onAddRecipient(user)
                                } label: {
                                    HStack(spacing: 12) {
                                        ProfilePictureView(photoURL: user.photoURL, size: 40)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(user.displayName)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Text(user.email)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        if selectedRecipients.contains(where: { $0.id == user.id }) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    .padding()
                                    .background(Color(.systemBackground))
                                }
                                .disabled(selectedRecipients.contains(where: { $0.id == user.id }))
                                
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Recipient chip view (reused from RecipientSelectionView)
struct RecipientChip: View {
    let recipient: UserProfile
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 6) {
            ProfilePictureView(photoURL: recipient.photoURL, size: 24)
            
            Text(recipient.displayName)
                .font(.subheadline)
                .lineLimit(1)
            
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.1))
        .foregroundColor(.blue)
        .cornerRadius(16)
    }
}


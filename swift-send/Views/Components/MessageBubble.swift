//
//  MessageBubble.swift
//  swift-send
//
//  Extracted from ChatDetailView.swift on 10/23/25.
//  Reusable message bubble component for displaying messages.
//

import SwiftUI

/// Reusable message bubble component
/// Displays a message with sender info, timestamp, and delivery status
struct MessageBubble: View {
    let message: Message
    let isFromCurrentUser: Bool
    let conversation: Conversation?
    let onStarMessage: () -> Void
    let onDeleteMessage: () -> Void
    
    var senderPhotoURL: String? {
        if !isFromCurrentUser {
            return conversation?.memberDetails[message.senderId]?.photoURL
        }
        return nil
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isFromCurrentUser { Spacer() }
            
            // Profile picture for other users
            if !isFromCurrentUser {
                ProfilePictureView(photoURL: senderPhotoURL, size: 32)
            }
            
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // Show sender name in group chats
                if !isFromCurrentUser && conversation?.type == .group {
                    Text(message.senderName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
                
                if message.type == .actionItem {
                    // Action Item Message
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text(message.text)
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(16)
                } else if message.type == .system {
                    // System Message
                    Text(message.text)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                } else {
                    // Regular Text Message
                    VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                        Text(message.text)
                            .padding(12)
                            .background(isFromCurrentUser ? Color.blue : Color.gray.opacity(0.2))
                            .foregroundColor(isFromCurrentUser ? .white : .primary)
                            .cornerRadius(16)
                            .contextMenu {
                                Button {
                                    onStarMessage()
                                } label: {
                                    Label("Star Message", systemImage: "star.fill")
                                }
                                
                                Button {
                                    UIPasteboard.general.string = message.text
                                } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                
                                if isFromCurrentUser {
                                    Button(role: .destructive) {
                                        onDeleteMessage()
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        
                        // Delivery/read status for current user's messages
                        if isFromCurrentUser, let readBy = message.readBy {
                            HStack(spacing: 4) {
                                if readBy.count > 1 {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                } else {
                                    Image(systemName: "checkmark")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }
                                Text(message.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text(message.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Spacer for current user's messages
            if isFromCurrentUser {
                if let currentUserProfile = conversation?.memberDetails[message.senderId] {
                    ProfilePictureView(photoURL: currentUserProfile.photoURL, size: 32)
                } else {
                    ProfilePictureView(size: 32)
                }
            }
            
            if !isFromCurrentUser { Spacer() }
        }
    }
}


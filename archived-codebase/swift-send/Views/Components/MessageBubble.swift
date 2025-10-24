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

    private var otherReadersCount: Int {
        guard let readBy = message.readBy else { return 0 }
        return readBy.keys.filter { $0 != message.senderId }.count
    }
    
    private enum GroupReadState {
        case sent
        case partiallyRead(unreadCount: Int)
        case allRead
    }
    
    private var groupReadState: GroupReadState? {
        guard
            let conversation,
            conversation.type == .group
        else {
            return nil
        }
        
        let recipientsExcludingSender = conversation.memberIds.filter { $0 != message.senderId }
        guard !recipientsExcludingSender.isEmpty else { return .allRead }
        
        let unreadCount = max(recipientsExcludingSender.count - otherReadersCount, 0)
        
        if unreadCount == 0 {
            return .allRead
        } else if unreadCount == recipientsExcludingSender.count {
            return .sent
        } else {
            return .partiallyRead(unreadCount: unreadCount)
        }
    }
    
    var senderPhotoURL: String? {
        if !isFromCurrentUser {
            return conversation?.memberDetails[message.senderId]?.photoURL
        }
        return nil
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isFromCurrentUser { Spacer() }
            
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
                }
            }
            
            if !isFromCurrentUser { Spacer() }
        }
    }
}

//
//  TypingIndicatorView.swift
//  swift-send
//
//  Extracted from ChatDetailView.swift on 10/23/25.
//  Reusable typing indicator component.
//

import SwiftUI

/// Reusable typing indicator view
/// Shows who is currently typing in a conversation
struct TypingIndicatorView: View {
    let typingUserIds: [String]
    let conversation: Conversation?
    
    var typingText: String {
        guard let conversation = conversation else { return "Someone is typing..." }
        
        let typingNames = typingUserIds.compactMap { userId in
            conversation.memberDetails[userId]?.displayName
        }
        
        if typingNames.isEmpty {
            return "Someone is typing..."
        } else if typingNames.count == 1 {
            return "\(typingNames[0]) is typing..."
        } else if typingNames.count == 2 {
            return "\(typingNames[0]) and \(typingNames[1]) are typing..."
        } else {
            return "\(typingNames.count) people are typing..."
        }
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ProfilePictureView(size: 32)
            
            HStack(spacing: 4) {
                Text(typingText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Animated dots
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 6, height: 6)
                        .opacity(0.5)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: typingUserIds.count
                        )
                }
            }
            .padding(12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(16)
            
            Spacer()
        }
    }
}


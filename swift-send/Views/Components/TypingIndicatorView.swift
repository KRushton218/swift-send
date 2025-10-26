//
//  TypingIndicatorView.swift
//  swift-send
//

import SwiftUI
import Combine

struct TypingIndicatorView: View {
    let typingUsers: [TypingIndicator]

    var body: some View {
        if !typingUsers.isEmpty {
            HStack(spacing: 4) {
                Text(typingText)
                    .font(.caption)
                    .foregroundColor(.gray)

                AnimatedDotsView()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private var typingText: String {
        switch typingUsers.count {
        case 0:
            return ""
        case 1:
            return "\(typingUsers[0].name) is typing"
        case 2:
            return "\(typingUsers[0].name) and \(typingUsers[1].name) are typing"
        case 3:
            return "\(typingUsers[0].name), \(typingUsers[1].name), and \(typingUsers[2].name) are typing"
        default:
            // Show first 2 names and count of others
            let othersCount = typingUsers.count - 2
            return "\(typingUsers[0].name), \(typingUsers[1].name), and \(othersCount) \(othersCount == 1 ? "other" : "others") are typing"
        }
    }
}

struct AnimatedDotsView: View {
    @State private var numberOfDots = 0

    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(String(repeating: ".", count: numberOfDots))
            .font(.caption)
            .foregroundColor(.gray)
            .frame(width: 15, alignment: .leading)
            .onReceive(timer) { _ in
                numberOfDots = (numberOfDots + 1) % 4
            }
    }
}

#Preview {
    VStack(spacing: 20) {
        TypingIndicatorView(typingUsers: [
            TypingIndicator(id: "1", name: "Alice", timestamp: 0, isTyping: true)
        ])

        TypingIndicatorView(typingUsers: [
            TypingIndicator(id: "1", name: "Alice", timestamp: 0, isTyping: true),
            TypingIndicator(id: "2", name: "Bob", timestamp: 0, isTyping: true)
        ])

        TypingIndicatorView(typingUsers: [
            TypingIndicator(id: "1", name: "Alice", timestamp: 0, isTyping: true),
            TypingIndicator(id: "2", name: "Bob", timestamp: 0, isTyping: true),
            TypingIndicator(id: "3", name: "Charlie", timestamp: 0, isTyping: true)
        ])

        TypingIndicatorView(typingUsers: [
            TypingIndicator(id: "1", name: "Alice", timestamp: 0, isTyping: true),
            TypingIndicator(id: "2", name: "Bob", timestamp: 0, isTyping: true),
            TypingIndicator(id: "3", name: "Charlie", timestamp: 0, isTyping: true),
            TypingIndicator(id: "4", name: "David", timestamp: 0, isTyping: true),
            TypingIndicator(id: "5", name: "Eve", timestamp: 0, isTyping: true)
        ])
    }
}

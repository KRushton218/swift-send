//
//  MessageBubble.swift
//  swift-send
//

import SwiftUI

struct MessageBubble: View {
    let message: Message
    let isFromCurrentUser: Bool
    let userNames: [String: String] // userId -> displayName

    var body: some View {
        HStack {
            if isFromCurrentUser {
                Spacer()
            }

            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .padding(12)
                    .background(isFromCurrentUser ? Color.blue : Color(.systemGray5))
                    .foregroundColor(isFromCurrentUser ? .white : .primary)
                    .cornerRadius(16)

                VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(Date(timeIntervalSince1970: message.timestamp / 1000), style: .time)
                            .font(.caption2)
                            .foregroundColor(.gray)

                        if isFromCurrentUser {
                            statusIcon
                        }
                    }

                    // Show read receipts for group messages
                    if isFromCurrentUser && !readByNames.isEmpty {
                        Text("Read by \(readByNames)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
            }

            if !isFromCurrentUser {
                Spacer()
            }
        }
        .padding(.horizontal)
    }

    private var statusIcon: some View {
        Group {
            switch message.status {
            case .sending:
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundColor(.gray)
            case .delivered:
                Image(systemName: "checkmark.circle")
                    .font(.caption2)
                    .foregroundColor(.gray)
            case .read:
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
        }
    }

    private var readByNames: String {
        let readers = message.readByUsers(excluding: message.senderId)
        let names = readers.compactMap { userNames[$0] }
        return names.joined(separator: ", ")
    }
}

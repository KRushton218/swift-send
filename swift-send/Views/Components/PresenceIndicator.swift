//
//  PresenceIndicator.swift
//  swift-send
//

import SwiftUI

struct PresenceIndicator: View {
    let isOnline: Bool

    var body: some View {
        Circle()
            .fill(isOnline ? Color.green : Color.gray)
            .frame(width: 8, height: 8)
    }
}

struct ParticipantHeader: View {
    let participants: [ParticipantInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(participants) { participant in
                HStack(spacing: 8) {
                    PresenceIndicator(isOnline: participant.isOnline)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(participant.name)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text(participant.statusText)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
}

struct ParticipantInfo: Identifiable {
    let id: String
    let name: String
    let isOnline: Bool
    let lastOnline: TimeInterval?

    var statusText: String {
        if isOnline {
            return "Online"
        } else if let lastOnline = lastOnline {
            let offset = RealtimeManager.shared.serverTimeOffset
            return "Last seen \(PresenceManager.shared.formatLastSeen(lastOnline, serverTimeOffset: offset))"
        } else {
            return "Offline"
        }
    }
}

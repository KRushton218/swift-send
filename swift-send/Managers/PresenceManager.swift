//
//  PresenceManager.swift
//  swift-send
//
//  Centralized presence management with timer-based status updates
//

import Foundation
import Combine

@MainActor
class PresenceManager: ObservableObject {
    static let shared = PresenceManager()

    // Timer that ticks every second - shared across all views
    // Used to update "Last seen" text in real-time (e.g., "1m ago" → "2m ago")
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private init() {}

    /// Formats a "last seen" string for offline users
    /// - Parameters:
    ///   - lastOnline: Timestamp in milliseconds since epoch
    ///   - serverTimeOffset: Offset in milliseconds to sync with server time
    /// - Returns: Formatted relative time string (e.g., "2m ago", "1h ago")
    func formatLastSeen(_ lastOnline: TimeInterval, serverTimeOffset: TimeInterval = 0) -> String {
        // Convert to seconds and adjust for server time offset
        let serverTimestampSeconds = lastOnline / 1000
        let currentServerTime = Date().timeIntervalSince1970 + (serverTimeOffset / 1000)

        let date = Date(timeIntervalSince1970: serverTimestampSeconds)
        let now = Date(timeIntervalSince1970: currentServerTime)

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

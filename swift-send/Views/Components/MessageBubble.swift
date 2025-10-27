//
//  MessageBubble.swift
//  swift-send
//

import SwiftUI

struct MessageBubble: View {
    let message: Message
    let isFromCurrentUser: Bool
    let currentUserId: String // Current user's ID for per-user translations
    let userNames: [String: String] // userId -> displayName
    let preferredLanguage: String // User's preferred language for translation
    let isGroupChat: Bool // Whether this is a group chat
    var onRetry: ((Message) -> Void)? = nil // Callback for retry action

    @StateObject private var translationManager = TranslationManager.shared
    @State private var showTranslateButton = true

    var body: some View {
        HStack {
            if isFromCurrentUser {
                Spacer()
            }

            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                // Sender name (only for group chats, only for messages from others)
                if isGroupChat && !isFromCurrentUser {
                    Text(senderName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 4)
                }

                // Main message bubble
                VStack(alignment: .leading, spacing: 8) {
                    // Original text
                    Text(message.text)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Translated text (if available from in-memory cache)
                    if let translation = translationManager.translations[message.id] {
                        Divider()
                            .background(Color.white.opacity(0.3))

                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "globe")
                                .font(.caption2)
                                .foregroundColor(isFromCurrentUser ? .white.opacity(0.8) : .secondary)

                            Text(translation.translatedText)
                                .font(.body)
                                .italic()
                                .foregroundColor(isFromCurrentUser ? .white.opacity(0.9) : .secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    }
                    // Fallback to message.translatedText for messages translated before app restart
                    else if message.hasTranslation, let translatedText = message.translatedText {
                        Divider()
                            .background(Color.white.opacity(0.3))

                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "globe")
                                .font(.caption2)
                                .foregroundColor(isFromCurrentUser ? .white.opacity(0.8) : .secondary)

                            Text(translatedText)
                                .font(.body)
                                .italic()
                                .foregroundColor(isFromCurrentUser ? .white.opacity(0.9) : .secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    }

                    // Translation loading indicator
                    if translationManager.isTranslating[message.id] == true {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Translating...")
                                .font(.caption)
                                .foregroundColor(isFromCurrentUser ? .white.opacity(0.8) : .secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    }
                }
                .background(isFromCurrentUser ? Color.blue : Color(.systemGray5))
                .foregroundColor(isFromCurrentUser ? .white : .primary)
                .cornerRadius(16)

                // Language badge and translate button
                if !isFromCurrentUser {
                    HStack(spacing: 8) {
                        // Language badge (if detected) - prefer in-memory translation data
                        if let translation = translationManager.translations[message.id] {
                            Text(translationManager.getLanguageName(code: translation.detectedLanguage))
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.systemGray6))
                                .foregroundColor(.secondary)
                                .cornerRadius(4)
                        } else if let detectedLang = message.detectedLanguage {
                            Text(translationManager.getLanguageName(code: detectedLang))
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.systemGray6))
                                .foregroundColor(.secondary)
                                .cornerRadius(4)
                        }

                        // Translate button - show if no translation in memory or RTDB
                        if showTranslateButton && translationManager.translations[message.id] == nil && !message.hasTranslation {
                            Button(action: { translateMessage() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "globe")
                                    Text("Translate")
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                            .disabled(translationManager.isTranslating[message.id] == true)
                        }

                        // Clear translation button - show if translation exists in memory or RTDB
                        if translationManager.translations[message.id] != nil || message.hasTranslation {
                            Button(action: { clearTranslation() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle")
                                    Text("Show original")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Translation error
                if let error = translationManager.translationErrors[message.id] {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .padding(.horizontal, 4)
                }

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

    // MARK: - Actions

    private func translateMessage() {
        Task {
            do {
                try await translationManager.translateMessage(
                    message,
                    to: preferredLanguage,
                    userId: currentUserId
                )
            } catch {
                print("Translation error: \(error)")
            }
        }
    }

    private func clearTranslation() {
        Task {
            do {
                try await translationManager.clearTranslation(
                    userId: currentUserId,
                    messageId: message.id
                )
            } catch {
                print("Clear translation error: \(error)")
            }
        }
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
            case .failed:
                Button(action: {
                    onRetry?(message)
                }) {
                    HStack(spacing: 2) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.red)
                        Text("Tap to retry")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }

    private var readByNames: String {
        let readers = message.readByUsers(excluding: message.senderId)
        let names = readers.compactMap { userNames[$0] }
        return names.joined(separator: ", ")
    }

    private var senderName: String {
        userNames[message.senderId] ?? "Unknown"
    }
}

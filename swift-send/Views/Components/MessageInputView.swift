//
//  MessageInputView.swift
//  swift-send
//
//  Extracted from ChatDetailView.swift on 10/23/25.
//  Reusable message input component.
//

import SwiftUI

/// Reusable message input view
/// Text field with send button for composing messages
struct MessageInputView: View {
    @Binding var messageText: String
    let onSend: () -> Void
    let onTextChanged: ((String) -> Void)?
    
    init(messageText: Binding<String>, onSend: @escaping () -> Void, onTextChanged: ((String) -> Void)? = nil) {
        self._messageText = messageText
        self.onSend = onSend
        self.onTextChanged = onTextChanged
    }
    
    var body: some View {
        HStack(spacing: 12) {
            TextField("Message", text: $messageText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .onChange(of: messageText) { oldValue, newValue in
                    onTextChanged?(newValue)
                }
            
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.gray.opacity(0.3)),
            alignment: .top
        )
    }
}


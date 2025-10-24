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
    let isSendEnabled: Bool
    private let focusBinding: FocusState<Bool>.Binding?

    init(
        messageText: Binding<String>,
        isSendEnabled: Bool = true,
        onSend: @escaping () -> Void,
        onTextChanged: ((String) -> Void)? = nil,
        focus: FocusState<Bool>.Binding? = nil
    ) {
        self._messageText = messageText
        self.isSendEnabled = isSendEnabled
        self.onSend = onSend
        self.onTextChanged = onTextChanged
        self.focusBinding = focus
    }

    var body: some View {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSend = isSendEnabled && !trimmed.isEmpty

        return HStack(spacing: 12) {
            buildTextField()
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .onChange(of: messageText) { _, newValue in
                    onTextChanged?(newValue)
                }
                .onSubmit {
                    if canSend {
                        onSend()
                    }
                }

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(canSend ? .blue : .gray)
            }
            .disabled(!canSend)
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

    @ViewBuilder
    private func buildTextField() -> some View {
        if let focusBinding {
            TextField("Message", text: $messageText, axis: .vertical)
                .focused(focusBinding)
        } else {
            TextField("Message", text: $messageText, axis: .vertical)
        }
    }
}

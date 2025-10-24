//
//  RecipientSelectorBar.swift
//  swift-send
//
//  Created on 10/23/25.
//  Reusable recipient selector component with search and chips.
//

import SwiftUI

/// Reusable recipient selector bar
/// Shows search field, selected recipients as chips, and search results
struct RecipientSelectorBar: View {
    @Binding var searchText: String
    @Binding var selectedRecipients: [UserProfile]
    let searchResults: [UserProfile]
    let isSearching: Bool
    let onAddRecipient: (UserProfile) -> Void
    let onRemoveRecipient: (UserProfile) -> Void
    let onAddByEmail: (String) -> Void
    let isValidEmail: (String) -> Bool

    private let focusBinding: FocusState<Bool>.Binding?

    init(
        searchText: Binding<String>,
        selectedRecipients: Binding<[UserProfile]>,
        searchResults: [UserProfile],
        isSearching: Bool,
        onAddRecipient: @escaping (UserProfile) -> Void,
        onRemoveRecipient: @escaping (UserProfile) -> Void,
        onAddByEmail: @escaping (String) -> Void,
        isValidEmail: @escaping (String) -> Bool,
        focus: FocusState<Bool>.Binding? = nil
    ) {
        _searchText = searchText
        _selectedRecipients = selectedRecipients
        self.searchResults = searchResults
        self.isSearching = isSearching
        self.onAddRecipient = onAddRecipient
        self.onRemoveRecipient = onRemoveRecipient
        self.onAddByEmail = onAddByEmail
        self.isValidEmail = isValidEmail
        self.focusBinding = focus
    }

    var body: some View {
        VStack(spacing: 0) {
            addressField

            if isSearching || !searchText.isEmpty {
                Divider()
                resultsSection
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Address Field

    private var addressField: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Text("To:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.top, selectedRecipients.isEmpty ? 10 : 6)

                WrappingLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(selectedRecipients) { recipient in
                        RecipientChip(
                            recipient: recipient,
                            onRemove: {
                                onRemoveRecipient(recipient)
                            }
                        )
                    }

                    searchEntry
                }
                .animation(.easeInOut(duration: 0.15), value: selectedRecipients.map(\.id))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
            )

            if selectedRecipients.isEmpty && searchText.isEmpty {
                Text("Type a name or email address to start a conversation.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    private var searchEntry: some View {
        buildSearchTextField()
            .font(.body)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .submitLabel(.search)
            .onSubmit(handleSubmit)
            .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .frame(minWidth: 140, alignment: .leading)
        .layoutPriority(1)
    }

    @ViewBuilder
    private func buildSearchTextField() -> some View {
        if let focusBinding {
            TextField("Search by name or email", text: $searchText)
                .focused(focusBinding)
        } else {
            TextField("Search by name or email", text: $searchText)
        }
    }

    private func handleSubmit() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let firstResult = searchResults.first {
            onAddRecipient(firstResult)
            return
        }

        if isValidEmail(trimmed) {
            onAddByEmail(trimmed)
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSection: some View {
        if isSearching {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        } else if !searchText.isEmpty {
            if searchResults.isEmpty {
                emptyResults
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(searchResults) { user in
                            Button {
                                onAddRecipient(user)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(user.displayName)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text(user.email)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    if selectedRecipients.contains(where: { $0.id == user.id }) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .disabled(selectedRecipients.contains(where: { $0.id == user.id }))

                            Divider()
                                .padding(.leading)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
    }

    private var emptyResults: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 42))
                .foregroundColor(.secondary)

            Text("No matches yet")
                .font(.headline)

            Text("Invite someone by typing their full email address.")
                .font(.caption)
                .foregroundColor(.secondary)

            if isValidEmail(searchText) {
                Button {
                    onAddByEmail(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
                } label: {
                    Label("Add \(searchText)", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 8)
    }
}

/// Recipient chip view (reused from RecipientSelectionView)
struct RecipientChip: View {
    let recipient: UserProfile
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(recipient.displayName)
                .font(.subheadline)
                .lineLimit(1)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.12))
        .foregroundColor(.blue)
        .cornerRadius(16)
    }
}

// MARK: - Wrapping Layout Helper

private struct WrappingLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    typealias Cache = Void

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard !subviews.isEmpty else { return .zero }

        let availableWidth = proposal.width ?? .greatestFiniteMagnitude
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: availableWidth, height: proposal.height))

            if lineWidth > 0 && lineWidth + spacing + size.width > availableWidth {
                maxLineWidth = max(maxLineWidth, lineWidth)
                totalHeight += lineHeight + lineSpacing
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth = lineWidth > 0 ? lineWidth + spacing + size.width : size.width
                lineHeight = max(lineHeight, size.height)
            }
        }

        maxLineWidth = max(maxLineWidth, lineWidth)
        totalHeight += lineHeight

        return CGSize(width: maxLineWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard !subviews.isEmpty else { return }

        let availableWidth = bounds.width > 0 ? bounds.width : .greatestFiniteMagnitude
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: availableWidth, height: proposal.height))

            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

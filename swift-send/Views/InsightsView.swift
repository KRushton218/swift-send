//
//  InsightsView.swift
//  swift-send
//
//  RAG-powered conversation insights view
//

import SwiftUI

struct InsightsView: View {
    let conversationId: String

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var insight: String?
    @State private var relevantMessages: [RelevantMessage] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let aiService = AIServiceManager.shared

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Instructions
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.orange)
                        Text("Ask about this conversation")
                            .font(.headline)
                    }

                    Text("I can help you find information from your chat history using AI-powered search.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Example queries
                VStack(alignment: .leading, spacing: 8) {
                    Text("Example questions:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(exampleQueries, id: \.self) { example in
                        Button(action: {
                            query = example
                        }) {
                            HStack {
                                Image(systemName: "arrow.right.circle")
                                    .font(.caption)
                                Text(example)
                                    .font(.caption)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal)

                // Query input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your question:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    TextField("What did we discuss about...?", text: $query, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)

                    Button(action: { generateInsight() }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(isLoading ? "Analyzing..." : "Get Insight")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(query.isEmpty || isLoading ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(query.isEmpty || isLoading)
                }
                .padding(.horizontal)

                // Error message
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }

                // Insight result
                if let insight = insight {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // AI Response
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Insight")
                                        .font(.headline)
                                }

                                Text(insight)
                                    .padding()
                                    .background(Color.green.opacity(0.1))
                                    .cornerRadius(8)
                            }

                            // Relevant messages
                            if !relevantMessages.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Based on these messages:")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)

                                    ForEach(relevantMessages, id: \.messageId) { message in
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "quote.bubble")
                                                .font(.caption)
                                                .foregroundColor(.secondary)

                                            Text(message.text)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(3)
                                        }
                                        .padding(8)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(6)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                } else {
                    Spacer()
                }
            }
            .padding(.vertical)
            .navigationTitle("Conversation Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Example Queries

    private var exampleQueries: [String] {
        [
            "When did we last talk about the project?",
            "What plans did we make?",
            "Did we decide on a meeting time?",
            "What topics have we discussed?"
        ]
    }

    // MARK: - Actions

    private func generateInsight() {
        guard !query.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        insight = nil
        relevantMessages = []

        Task {
            do {
                let response = try await aiService.generateInsights(
                    conversationId: conversationId,
                    query: query
                )

                await MainActor.run {
                    insight = response.insight
                    relevantMessages = response.relevantMessages
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    InsightsView(conversationId: "test123")
}

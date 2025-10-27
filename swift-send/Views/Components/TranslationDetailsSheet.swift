//
//  TranslationDetailsSheet.swift
//  swift-send
//
//  Translation details modal showing cultural context and slang explanations
//

import SwiftUI

struct TranslationDetailsSheet: View {
    let originalText: String
    let translatedText: String
    let detectedLanguage: String
    let targetLanguage: String
    let culturalNotes: [String]?
    let slangExplanations: [SlangExplanation]?

    @Environment(\.dismiss) private var dismiss
    private let translationManager = TranslationManager.shared

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Original & Translated Text Section
                    VStack(alignment: .leading, spacing: 16) {
                        // Original
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "text.quote")
                                    .foregroundColor(.secondary)
                                Text("Original (\(languageName(detectedLanguage)))")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                            }

                            Text(originalText)
                                .font(.body)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                        }

                        // Translated
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "arrow.right")
                                    .foregroundColor(.blue)
                                Text("Translation (\(languageName(targetLanguage)))")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                            }

                            Text(translatedText)
                                .font(.body)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)

                    Divider()
                        .padding(.horizontal)

                    // Cultural Context Section
                    if let culturalNotes = culturalNotes, !culturalNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "globe")
                                    .foregroundColor(.orange)
                                    .font(.title3)
                                Text("Cultural Context")
                                    .font(.headline)
                            }
                            .padding(.horizontal)

                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(culturalNotes.enumerated()), id: \.offset) { index, note in
                                    HStack(alignment: .top, spacing: 12) {
                                        Circle()
                                            .fill(Color.orange.opacity(0.3))
                                            .frame(width: 8, height: 8)
                                            .padding(.top, 6)

                                        Text(note)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.05))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                    }

                    // Slang & Idioms Section
                    if let slangExplanations = slangExplanations, !slangExplanations.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .foregroundColor(.purple)
                                    .font(.title3)
                                Text("Slang & Idioms")
                                    .font(.headline)
                            }
                            .padding(.horizontal)

                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(Array(slangExplanations.enumerated()), id: \.offset) { index, slang in
                                    VStack(alignment: .leading, spacing: 8) {
                                        // Term
                                        HStack {
                                            Text(slang.term)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.purple)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 4)
                                                .background(Color.purple.opacity(0.15))
                                                .cornerRadius(6)

                                            Spacer()
                                        }

                                        // Explanation
                                        Text(slang.explanation)
                                            .font(.body)
                                            .foregroundColor(.primary)

                                        // Literal translation (if available)
                                        if let literal = slang.literal {
                                            HStack(spacing: 6) {
                                                Image(systemName: "text.alignleft")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                Text("Literal: \(literal)")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .italic()
                                            }
                                        }
                                    }
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Info Note
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text("Cultural context and slang explanations are AI-generated and may vary by region or context.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                .padding(.top)
            }
            .navigationTitle("Translation Details")
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

    private func languageName(_ code: String) -> String {
        translationManager.getLanguageName(code: code)
    }
}

#Preview {
    TranslationDetailsSheet(
        originalText: "Break a leg at your interview tomorrow!",
        translatedText: "¡Mucha suerte en tu entrevista de mañana!",
        detectedLanguage: "en",
        targetLanguage: "es",
        culturalNotes: [
            "\"Break a leg\" is an English idiom meaning \"good luck,\" especially in performance contexts.",
            "Saying \"good luck\" directly is considered bad luck in theatrical tradition."
        ],
        slangExplanations: [
            SlangExplanation(
                term: "Break a leg",
                explanation: "Theatrical expression wishing good luck (saying \"good luck\" is considered bad luck in theater)",
                literal: "Rómpete una pierna"
            )
        ]
    )
}

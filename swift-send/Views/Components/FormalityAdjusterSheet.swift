//
//  FormalityAdjusterSheet.swift
//  swift-send
//
//  Formality adjuster for message composition
//

import SwiftUI

struct FormalityAdjusterSheet: View {
    let formalityData: FormalityResponse
    @Binding var selectedText: String
    @Environment(\.dismiss) private var dismiss

    @State private var selectedLevel: String

    init(formalityData: FormalityResponse, selectedText: Binding<String>) {
        self.formalityData = formalityData
        self._selectedText = selectedText
        // Initialize with current level
        self._selectedLevel = State(initialValue: formalityData.analysis.currentLevel)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Original Message Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Original Message")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        Text(formalityData.originalText)
                            .font(.body)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    // Formality Analysis Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "chart.bar.fill")
                                .foregroundColor(.blue)
                            Text("Current Formality: \(formalityData.analysis.currentLevel.capitalized) (\(formalityData.analysis.score)/10)")
                                .font(.headline)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            FactorRow(icon: "text.word.spacing", title: "Conjugations", description: formalityData.analysis.factors.conjugations)
                            FactorRow(icon: "text.bubble", title: "Phrasing", description: formalityData.analysis.factors.phrasing)
                            FactorRow(icon: "quote.bubble", title: "Figures of Speech", description: formalityData.analysis.factors.figuresOfSpeech)
                            FactorRow(icon: "character.cursor.ibeam", title: "Verb Choice", description: formalityData.analysis.factors.verbChoice)
                            FactorRow(icon: "waveform", title: "Tone", description: formalityData.analysis.factors.tone)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    Divider()
                        .padding(.horizontal)

                    // Formality Level Selection
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Select Formality Level")
                            .font(.headline)
                            .padding(.horizontal)

                        FormalityLevelCard(
                            level: "casual",
                            score: 2,
                            text: formalityData.variations.casual,
                            isSelected: selectedLevel == "casual"
                        ) {
                            selectedLevel = "casual"
                        }

                        FormalityLevelCard(
                            level: "neutral",
                            score: 5,
                            text: formalityData.variations.neutral,
                            isSelected: selectedLevel == "neutral"
                        ) {
                            selectedLevel = "neutral"
                        }

                        FormalityLevelCard(
                            level: "formal",
                            score: 7,
                            text: formalityData.variations.formal,
                            isSelected: selectedLevel == "formal"
                        ) {
                            selectedLevel = "formal"
                        }

                        FormalityLevelCard(
                            level: "business",
                            score: 9,
                            text: formalityData.variations.business,
                            isSelected: selectedLevel == "business"
                        ) {
                            selectedLevel = "business"
                        }
                    }
                    .padding(.bottom, 20)
                }
                .padding(.top)
            }
            .navigationTitle("Adjust Formality")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Use \(selectedLevel.capitalized)") {
                        applySelection()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func applySelection() {
        switch selectedLevel {
        case "casual":
            selectedText = formalityData.variations.casual
        case "neutral":
            selectedText = formalityData.variations.neutral
        case "formal":
            selectedText = formalityData.variations.formal
        case "business":
            selectedText = formalityData.variations.business
        default:
            break
        }
        dismiss()
    }
}

// MARK: - Supporting Views

struct FactorRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.blue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
    }
}

struct FormalityLevelCard: View {
    let level: String
    let score: Int
    let text: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                // Radio button
                Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .gray)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(level.capitalized)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Text("(\(score)/10)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(text)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

#Preview {
    FormalityAdjusterSheet(
        formalityData: FormalityResponse(
            originalText: "Hey! Can you send me that doc? Thanks!",
            analysis: FormalityAnalysis(
                currentLevel: "casual",
                score: 2,
                factors: FormalityFactors(
                    conjugations: "Informal greeting 'Hey' and exclamations",
                    phrasing: "Direct question without please/softeners",
                    figuresOfSpeech: "Casual abbreviation 'doc' instead of 'document'",
                    verbChoice: "Simple verbs with informal tone",
                    tone: "Very friendly and relaxed"
                )
            ),
            variations: FormalityVariations(
                casual: "Hey! Can you send me that doc? Thanks!",
                neutral: "Hi! Could you send me that document? Thanks!",
                formal: "Hello. Would you be able to send me that document? Thank you.",
                business: "Good morning. I would appreciate if you could send me the document at your earliest convenience. Thank you."
            )
        ),
        selectedText: .constant("Hey! Can you send me that doc? Thanks!")
    )
}

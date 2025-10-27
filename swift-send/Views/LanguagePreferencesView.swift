//
//  LanguagePreferencesView.swift
//  swift-send
//
//  User language and translation preferences
//

import SwiftUI
import FirebaseAuth

struct LanguagePreferencesView: View {
    @State private var preferences = UserPreferences.defaultPreferences
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showSuccessMessage = false

    private let realtimeManager = RealtimeManager.shared
    private let translationManager = TranslationManager.shared

    var body: some View {
        Form {
            // Preferred Language Section
            Section {
                Picker("Preferred Language", selection: $preferences.preferredLanguage) {
                    ForEach(Array(translationManager.supportedLanguages.keys.sorted()), id: \.self) { code in
                        Text(translationManager.getLanguageName(code: code))
                            .tag(code)
                    }
                }
                .pickerStyle(.menu)

                Text("Messages will be translated to this language when you tap 'Translate'")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Translation Settings")
            }

            // Translation Options Section
            Section {
                Toggle("Auto-translate messages", isOn: $preferences.autoTranslate)

                if preferences.autoTranslate {
                    Text("Automatically translate messages from other languages")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Toggle("Show language badges", isOn: $preferences.showLanguageBadges)

                if preferences.showLanguageBadges {
                    Text("Display detected language on message bubbles")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Toggle("Show cultural context & slang", isOn: $preferences.showTranslationExtras)

                if preferences.showTranslationExtras {
                    Text("Display sparkles icon (✨) to view cultural context and slang explanations")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Options")
            }

            // Supported Languages Section
            Section {
                ForEach(Array(translationManager.supportedLanguages.keys.sorted()), id: \.self) { code in
                    HStack {
                        Text(translationManager.getLanguageName(code: code))
                        Spacer()
                        Text(code.uppercased())
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray6))
                            .cornerRadius(4)
                    }
                }
            } header: {
                Text("Supported Languages")
            }

            // Information Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("About Translation")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    Text("Translations are powered by AI and cached to reduce costs. The first translation of a message may take a few seconds.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }

            // Error Message
            if let error = errorMessage {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }

            // Success Message
            if showSuccessMessage {
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Preferences saved successfully")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .navigationTitle("Language & Translation")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading {
                ProgressView("Loading preferences...")
            }
        }
        .task {
            await loadPreferences()
        }
        .onChange(of: preferences) { _, newValue in
            // Auto-save on change
            Task {
                await savePreferences()
            }
        }
    }

    // MARK: - Actions

    private func loadPreferences() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        isLoading = true
        errorMessage = nil

        do {
            if let loadedPrefs = try await realtimeManager.getUserPreferences(userId: userId) {
                preferences = loadedPrefs
            }
            isLoading = false
        } catch {
            errorMessage = "Failed to load preferences: \(error.localizedDescription)"
            isLoading = false
        }
    }

    private func savePreferences() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        isSaving = true
        errorMessage = nil
        showSuccessMessage = false

        do {
            try await realtimeManager.saveUserPreferences(userId: userId, preferences: preferences)

            // Show success message briefly
            showSuccessMessage = true
            isSaving = false

            // Hide success message after 2 seconds
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showSuccessMessage = false
        } catch {
            errorMessage = "Failed to save preferences: \(error.localizedDescription)"
            isSaving = false
        }
    }
}

#Preview {
    NavigationStack {
        LanguagePreferencesView()
    }
}

// MARK: - GroupChatInfoView
//
//  GroupChatInfoView.swift
//  swift-send
//
//  Created by AI Assistant on 10/23/25.
//

import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct GroupChatInfoView: View {
    let conversation: Conversation
    let currentUserId: String
    let onUpdate: () -> Void
    
    @State private var editingName: String
    @Environment(\.dismiss) private var dismiss
    
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    init(conversation: Conversation, currentUserId: String, onUpdate: @escaping () -> Void) {
        self.conversation = conversation
        self.currentUserId = currentUserId
        self.onUpdate = onUpdate
        self._editingName = State(initialValue: conversation.name ?? "")
    }
    
    private var otherMemberIds: [String] {
        conversation.memberIds.filter { $0 != currentUserId }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Editable Group Name
                VStack(alignment: .leading, spacing: 8) {
                    Text("Group Name")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("Enter group name", text: $editingName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal)
                }
                .padding()
                .background(Color(.systemGray6))
                
                
                // Members List
                List {
                    Section(header: Text("Members (\(conversation.memberIds.count))")) {
                        ForEach(otherMemberIds, id: \.self) { memberId in
                            if let detail = conversation.memberDetails[memberId] {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(detail.displayName)
                                            .font(.body)
                                            .fontWeight(.medium)
                                        
                                        Text("Joined \(detail.joinedAt, style: .date)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if conversation.createdBy == memberId {
                                        Image(systemName: "crown.fill")
                                            .foregroundColor(.yellow)
                                            .font(.caption)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .navigationTitle("Group Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveName()
                    }
                    .disabled(isSaving || editingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Save Changes?", isPresented: $isSaving) {
                Button("Save", role: .destructive) {
                    performSave()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will update the group name for all members.")
            }
        }
    }
    
    private func saveName() {
        let trimmedName = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            editingName = ""
            return
        }
        
        isSaving = true
    }
    
    private func performSave() {
        guard let conversationId = conversation.id,
              conversation.type == .group else {
            dismiss()
            return
        }
        
        let trimmedName = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Task {
            do {
                let firestoreManager = FirestoreManager()
                try await firestoreManager.updateConversation(id: conversationId, data: ["name": trimmedName])
                
                await MainActor.run {
                    onUpdate()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to update group name: \(error.localizedDescription)"
                    isSaving = false
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        GroupChatInfoView(
            conversation: Conversation(
                id: "test-group",
                type: .group,
                name: "My Group Chat",
                createdBy: "creator",
                memberIds: ["current", "user1", "user2"],
                memberDetails: [
                    "current": Conversation.MemberDetail(displayName: "You", joinedAt: Date()),
                    "user1": Conversation.MemberDetail(displayName: "John Doe", photoURL: nil, joinedAt: Date().addingTimeInterval(-86400)),
                    "user2": Conversation.MemberDetail(displayName: "Jane Smith", joinedAt: Date().addingTimeInterval(-172800))
                ]
            ),
            currentUserId: "current"
        ) {
            print("Updated")
        }
    }
}

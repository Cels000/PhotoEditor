// RecipeNamePromptView.swift
// Modal sheet for entering a recipe name.
// Used by both "Save Recipe" (creates new) and "Rename" (edits existing).
// RECIPE-01, RECIPE-03.

import SwiftUI

struct RecipeNamePromptView: View {
    let title: String
    let initialName: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Recipe name", text: $name)
                    .focused($nameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { submit() }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { submit() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                name = initialName
                nameFieldFocused = true
            }
        }
        .presentationDetents([.height(200)])
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
    }
}

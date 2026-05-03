// LibraryGridView.swift
// PhotoEditor
//
// Sheet-presented grid of saved edits. Tap to re-open; long-press for Delete
// with a confirmation alert before calling store.delete (LIB-03).
// Sort order (updatedAt DESC) is owned by LibraryStore.refresh().

import SwiftUI

struct LibraryGridView: View {
    let store: LibraryStore
    var onOpen: (LibraryItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pendingDelete: LibraryItem?

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(store.items) { item in
                                Button {
                                    onOpen(item)
                                    dismiss()
                                } label: {
                                    LibraryItemThumbnail(item: item)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        pendingDelete = item
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                "Delete edit?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                presenting: pendingDelete
            ) { item in
                Button("Cancel", role: .cancel) { pendingDelete = nil }
                Button("Delete", role: .destructive) {
                    store.delete(item)
                    pendingDelete = nil
                }
            } message: { _ in
                Text("This removes the edit from your library. Your original photo in Photos is not affected.")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("No edits yet")
                .font(.headline)
            Text("Save an edit to see it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

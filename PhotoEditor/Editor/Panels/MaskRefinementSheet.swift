// PhotoEditor/Editor/Panels/MaskRefinementSheet.swift
//
// Bottom sheet for tuning the active subject mask. Surfaces feather, invert,
// per-instance include/exclude, and Remove Mask. Opened by tapping the
// toolbar mask button while a mask is active.

import SwiftUI

struct MaskRefinementSheet: View {
    @Bindable var viewModel: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingRemove: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.lastDetectedInstanceCount > 0 {
                    InstancePickerOverlay(viewModel: viewModel)
                        .padding(.bottom, 8)
                }
                Form {
                    Section("Edge") {
                        HStack {
                            Text("Feather")
                                .foregroundStyle(Theme.Colors.text)
                            Slider(value: Binding(
                                get: { viewModel.document.mask?.feather ?? 0 },
                                set: { viewModel.updateMaskFeather($0) }
                            ), in: 0...1)
                        }
                        Toggle("Invert", isOn: Binding(
                            get: { viewModel.document.mask?.invert ?? false },
                            set: { viewModel.setMaskInvert($0) }
                        ))
                    }

                    if viewModel.lastDetectedInstanceCount > 1 {
                        Section("Subjects") {
                            ForEach(0..<viewModel.lastDetectedInstanceCount, id: \.self) { i in
                                Button {
                                    viewModel.toggleInstanceExcluded(i)
                                } label: {
                                    HStack {
                                        Text("Subject \(i + 1)")
                                            .foregroundStyle(Theme.Colors.text)
                                        Spacer()
                                        Image(systemName: isExcluded(i) ? "circle" : "checkmark.circle.fill")
                                            .foregroundStyle(isExcluded(i) ? Theme.Colors.secondary : Theme.Colors.accent)
                                    }
                                }
                            }
                        }
                    }

                    Section {
                        Button(role: .destructive) {
                            confirmingRemove = true
                        } label: {
                            Text("Remove Mask")
                        }
                    }
                }
            }
            .navigationTitle("Edit Mask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Remove subject mask? Background edits will be discarded.",
                isPresented: $confirmingRemove,
                titleVisibility: .visible
            ) {
                Button("Remove Mask", role: .destructive) {
                    viewModel.removeMask()
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    private func isExcluded(_ i: Int) -> Bool {
        viewModel.document.mask?.excludedInstances.contains(i) ?? false
    }
}

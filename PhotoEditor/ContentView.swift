import PhotosUI
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = PhotoEditorViewModel()
    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    editorPreview
                    actionBar
                    filterStrip
                    adjustments
                    saveSection
                }
                .padding(20)
            }
            .navigationTitle("Photo Editor")
            .background(Color(.systemGroupedBackground))
        }
        .task(id: selectedItem) {
            await loadSelectedPhoto()
        }
        .alert("Error", isPresented: Binding(present: $viewModel.errorMessage), presenting: viewModel.errorMessage) { _ in
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: { Text($0) }
        .alert("Saved", isPresented: Binding(present: $viewModel.successMessage), presenting: viewModel.successMessage) { _ in
            Button("OK", role: .cancel) { viewModel.successMessage = nil }
        } message: { Text($0) }
    }

    private var editorPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(maxWidth: .infinity)
                .aspectRatio(3 / 4, contentMode: .fit)

            if let image = viewModel.editedImage ?? viewModel.sourceImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(12)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text("Pick a photo to start editing")
                        .font(.headline)
                    Text("Apply filters, tune light and color, rotate, then save.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                .padding(32)
            }
        }
        .shadow(color: Color.black.opacity(0.08), radius: 20, y: 12)
    }

    private var actionBar: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $selectedItem, matching: .images, preferredItemEncoding: .automatic) {
                Label(viewModel.sourceImage == nil ? "Choose Photo" : "Replace Photo", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())

            HStack(spacing: 12) {
                Button {
                    viewModel.rotateLeft()
                } label: {
                    Label("Left", systemImage: "rotate.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(viewModel.sourceImage == nil)

                Button {
                    viewModel.rotateRight()
                } label: {
                    Label("Right", systemImage: "rotate.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(viewModel.sourceImage == nil)
            }

            Button {
                viewModel.resetAdjustments(clearImage: false)
            } label: {
                Label("Reset Edits", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(viewModel.sourceImage == nil)
        }
    }

    private var filterStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filters")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PhotoEditorViewModel.FilterPreset.allCases) { preset in
                        Button {
                            viewModel.selectedFilter = preset
                        } label: {
                            Text(preset.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(viewModel.selectedFilter == preset ? Color.blue : Color(.secondarySystemBackground))
                                .foregroundStyle(viewModel.selectedFilter == preset ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .disabled(viewModel.sourceImage == nil)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var adjustments: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Adjustments")
                .font(.headline)

            AdjustmentSlider(title: "Brightness", value: $viewModel.brightness, range: -1...1)
            AdjustmentSlider(title: "Contrast", value: $viewModel.contrast, range: 0.5...2)
            AdjustmentSlider(title: "Saturation", value: $viewModel.saturation, range: 0...2)
        }
        .padding(18)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .disabled(viewModel.sourceImage == nil)
    }

    private var saveSection: some View {
        Button {
            Task {
                await viewModel.saveImage()
            }
        } label: {
            HStack {
                if viewModel.isSaving {
                    ProgressView()
                        .tint(.white)
                }
                Text(viewModel.isSaving ? "Saving..." : "Save to Photos")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(viewModel.sourceImage == nil || viewModel.isSaving)
    }

    private func loadSelectedPhoto() async {
        guard let selectedItem else { return }

        do {
            if let data = try await selectedItem.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                viewModel.loadImage(image)
            } else {
                viewModel.errorMessage = "The selected photo could not be loaded."
            }
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
}

private extension Binding where Value == Bool {
    init<T>(present source: Binding<T?>) {
        self.init(
            get: { source.wrappedValue != nil },
            set: { if !$0 { source.wrappedValue = nil } }
        )
    }
}

private struct AdjustmentSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(value.formatted(.number.precision(.fractionLength(2))))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: $value, in: range)
                .tint(.blue)
        }
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(Color.blue.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

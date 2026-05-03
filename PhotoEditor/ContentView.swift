import CoreImage
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = EditorViewModel()
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedTab: EditorPanelTab = .filters
    @State private var showOriginal: Bool = false
    @State private var originalPreviewImage: UIImage?
    @State private var originalContext: CIContext = CIContext(options: [.useSoftwareRenderer: false])
    @State private var libraryStore: LibraryStore?
    @State private var isLibraryPresented: Bool = false
    @State private var isExportSheetPresented: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                UndoToolbar(viewModel: viewModel)
                editorPreview
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                PanelContainerView(viewModel: viewModel, selectedTab: $selectedTab)
            }
            .navigationTitle("Photo Editor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isLibraryPresented = true
                    } label: {
                        Image(systemName: "photo.on.rectangle.angled")
                    }
                    .disabled(libraryStore == nil)
                    .accessibilityLabel("Library")
                }
                ToolbarItem(placement: .topBarLeading) {
                    PhotosPicker(selection: $selectedItem, matching: .images, preferredItemEncoding: .automatic) {
                        Image(systemName: "photo.on.rectangle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.saveToLibrary() }
                    } label: {
                        Image(systemName: "tray.and.arrow.down")
                    }
                    .disabled(viewModel.importedImage == nil || viewModel.isSaving || libraryStore == nil)
                    .accessibilityLabel("Save to Library")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isExportSheetPresented = true
                    } label: {
                        if viewModel.isExporting {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up.on.square")
                        }
                    }
                    .disabled(viewModel.importedImage == nil || viewModel.isExporting)
                    .accessibilityLabel("Export")
                }
            }
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $isLibraryPresented) {
                if let store = libraryStore {
                    LibraryGridView(store: store) { item in
                        Task { await viewModel.openLibraryItem(item) }
                    }
                }
            }
            .sheet(isPresented: $isExportSheetPresented) {
                ExportSheetView(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: Binding(
                get: { viewModel.shareData != nil },
                set: { if !$0 { viewModel.shareData = nil; viewModel.shareFormat = nil } }
            )) {
                if let data = viewModel.shareData, let format = viewModel.shareFormat {
                    ShareSheetView(data: data, format: format) {
                        viewModel.shareData = nil
                        viewModel.shareFormat = nil
                    }
                }
            }
        }
        .task(id: selectedItem) { await loadSelectedPhoto() }
        .task(id: importedIdentity) { await rebuildOriginalPreview() }
        .task {
            if libraryStore == nil {
                let store = LibraryStore(context: modelContext)
                libraryStore = store
                viewModel.libraryStore = store
            }
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
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
                .aspectRatio(3 / 4, contentMode: .fit)

            if let image = displayedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(8)
                    .overlay(alignment: .topLeading) {
                        if showOriginal {
                            Text("Original")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.thinMaterial, in: Capsule())
                                .padding(12)
                        }
                    }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text("Pick a photo to start editing")
                        .font(.headline)
                }
            }
        }
        .compareOnLongPress(showOriginal: $showOriginal)
        .accessibilityLabel("Photo canvas")
        .accessibilityHint("Press and hold to compare with the original.")
    }

    private var displayedImage: UIImage? {
        if showOriginal, let original = originalPreviewImage { return original }
        return viewModel.previewImage
    }

    private var importedIdentity: String {
        guard let img = viewModel.importedImage else { return "" }
        return img.previewCIImage.extent.debugDescription
    }

    @MainActor
    private func rebuildOriginalPreview() async {
        guard let imported = viewModel.importedImage else {
            originalPreviewImage = nil
            return
        }
        let src = imported.previewCIImage
        if let cg = originalContext.createCGImage(src, from: src.extent) {
            originalPreviewImage = UIImage(cgImage: cg)
        }
    }

    private func loadSelectedPhoto() async {
        guard let selectedItem else { return }
        let assetID = selectedItem.itemIdentifier   // PHAsset.localIdentifier when picking from library
        do {
            if let data = try await selectedItem.loadTransferable(type: Data.self) {
                await viewModel.importPhoto(data: data, sourceAssetID: assetID)
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

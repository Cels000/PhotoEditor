import PhotosUI
import SwiftUI

enum StudioSegment: Hashable {
    case edits
    case cameraRoll
}

/// Studio tab — the unified entry point for getting a photo into the editor.
/// Two segments: EDITS (your saved app library) and CAMERA ROLL (system picker).
/// Solves the previous icon ambiguity (Library vs Add Photo were near-identical).
struct StudioTabView: View {
    @Bindable var viewModel: EditorViewModel
    let libraryStore: LibraryStore?
    var onPhotoOpened: () -> Void

    @State private var segment: StudioSegment = .edits
    @State private var pickerSelection: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            // Title — large, restrained, VSCO-style.
            HStack {
                Text("STUDIO")
                    .font(Theme.Typography.label)
                    .tracking(2)
                    .foregroundStyle(Theme.Colors.secondary)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)

            // Segmented control: EDITS | CAMERA ROLL.
            Picker("", selection: $segment) {
                Text("EDITS").tag(StudioSegment.edits)
                Text("CAMERA ROLL").tag(StudioSegment.cameraRoll)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)

            Group {
                switch segment {
                case .edits:
                    editsGrid
                case .cameraRoll:
                    cameraRollPicker
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.Colors.canvas.ignoresSafeArea())
        .toolbarBackground(Theme.Colors.canvas, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .task(id: pickerSelection) { await loadPickedPhoto() }
    }

    // MARK: - EDITS segment

    @ViewBuilder
    private var editsGrid: some View {
        if let store = libraryStore {
            LibraryGridView(store: store) { item in
                Task {
                    await viewModel.openLibraryItem(item)
                    onPhotoOpened()
                }
            }
        } else {
            ProgressView()
        }
    }

    // MARK: - CAMERA ROLL segment

    private var cameraRollPicker: some View {
        // v1: a single full-area "tap to pick" tile that triggers PhotosPicker.
        // v2: a real PHAsset thumbnail grid. PhotosPicker handles permission UX
        // and limited-library access for free, so v1 is fine to ship.
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            PhotosPicker(selection: $pickerSelection, matching: .images, preferredItemEncoding: .automatic) {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Theme.Colors.text)
                    Text("PICK FROM CAMERA ROLL")
                        .font(Theme.Typography.label)
                        .tracking(1.5)
                        .foregroundStyle(Theme.Colors.text)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xl * 2)
                .background(Theme.Colors.panel)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            Text("Photos open in the editor.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondary)
            Spacer()
        }
    }

    @MainActor
    private func loadPickedPhoto() async {
        guard let item = pickerSelection else { return }
        let assetID = item.itemIdentifier
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                await viewModel.importPhoto(data: data, sourceAssetID: assetID)
                onPhotoOpened()
            } else {
                viewModel.errorMessage = "The selected photo could not be loaded."
            }
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
        pickerSelection = nil
    }
}

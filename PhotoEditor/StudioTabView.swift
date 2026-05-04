import SwiftUI

enum StudioSegment: Hashable {
    case edits
    case cameraRoll
}

/// Studio tab — the unified entry point for getting a photo into the editor.
/// Two segments: CAMERA ROLL (inline PHAsset grid) and EDITS (your saved
/// app library). Camera Roll is the default landing — most sessions start
/// from a fresh photo. Solves the previous icon ambiguity in v1 (Library
/// vs Add Photo were near-identical).
struct StudioTabView: View {
    @Bindable var viewModel: EditorViewModel
    let libraryStore: LibraryStore?
    var onPhotoOpened: () -> Void

    @State private var segment: StudioSegment = .cameraRoll

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

            // Segmented control: CAMERA ROLL is the default landing — most
            // sessions start by picking a fresh photo, not browsing past edits.
            Picker("", selection: $segment) {
                Text("CAMERA ROLL").tag(StudioSegment.cameraRoll)
                Text("EDITS").tag(StudioSegment.edits)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)

            Group {
                switch segment {
                case .cameraRoll:
                    CameraRollGridView(viewModel: viewModel, onPhotoOpened: onPhotoOpened)
                case .edits:
                    editsGrid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.Colors.canvas.ignoresSafeArea())
        .toolbarBackground(Theme.Colors.canvas, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
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
}

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
    @State private var showCamera: Bool = false
    // Hoisted so they survive parent body re-evaluations. Creating these
    // inside the .fullScreenCover content closure made every parent re-eval
    // mint a fresh CameraViewModel — wiping the carousel thumbnailer's
    // rendered cache and leaving every preset thumbnail grey on the next
    // tap. State storage gives them stable identity across the cover's
    // lifetime.
    @State private var cameraVM: CameraViewModel?
    @State private var cameraSession: CameraSession?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
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

            cameraFAB
                .padding(.trailing, 16)
                .padding(.bottom, 16)
        }
        .fullScreenCover(
            isPresented: $showCamera,
            onDismiss: {
                cameraVM = nil
                cameraSession = nil
            }
        ) {
            if let cameraVM, let cameraSession {
                CameraView(viewModel: cameraVM, session: cameraSession)
            }
        }
    }

    private var cameraFAB: some View {
        Button { presentCamera() } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.Colors.canvas)
                .frame(width: 56, height: 56)
                .background(Theme.Colors.text)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        }
        .accessibilityLabel("Open Camera")
    }

    private func presentCamera() {
        guard let libraryStore, let recipeStore = viewModel.recipeStore else { return }
        let library = viewModel.filterLibrary
        cameraVM = CameraViewModel(
            libraryStore: libraryStore,
            recipeStore: recipeStore,
            cubeResolver: { id in library.filter(withID: id)?.cube() }
        )
        cameraSession = CameraSession()
        showCamera = true
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

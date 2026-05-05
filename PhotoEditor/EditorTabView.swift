import CoreImage
import SwiftUI
import UIKit

/// Editor tab — the active editing session. Slimmed top bar (undo/redo + a
/// single ✓ menu replacing the previous 5 ambiguous toolbar icons) and full
/// edge-to-edge canvas. Tap the canvas to hide chrome entirely.
struct EditorTabView: View {
    @Bindable var viewModel: EditorViewModel
    @Binding var showLimitedBanner: Bool

    @State private var selectedPanel: EditorPanelTab = .looks
    @State private var showOriginal: Bool = false
    @State private var originalPreviewImage: UIImage?
    @State private var originalContext: CIContext = CIContext(options: [.useSoftwareRenderer: false])
    @State private var isChromeHidden: Bool = false
    @State private var didDismissLimitedBanner: Bool = false

    /// Split-compare mode: original on the left of a draggable vertical
    /// divider, edited on the right. Toggled via a top-bar button. Independent
    /// of the press-and-hold quick-compare gesture (which still shows full
    /// original anywhere on the canvas while held).
    @State private var isSplitCompareActive: Bool = false
    /// Divider X position in 0...1 of the canvas width. Resets to 0.5 each
    /// time split mode is entered so the user starts at center.
    @State private var splitPosition: CGFloat = 0.5

    @State private var isExportSheetPresented: Bool = false
    @State private var isNamePromptPresented: Bool = false
    @State private var showingMaskRefinement: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if !isChromeHidden {
                if showLimitedBanner && !didDismissLimitedBanner {
                    limitedAccessBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                editorTopBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            editorPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(isChromeHidden ? .all : [], edges: isChromeHidden ? [.top, .bottom] : [])

            if !isChromeHidden && viewModel.importedImage != nil {
                PanelContainerView(viewModel: viewModel, selectedTab: $selectedPanel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Theme.Colors.canvas.ignoresSafeArea())
        .statusBarHidden(isChromeHidden)
        .persistentSystemOverlays(isChromeHidden ? .hidden : .automatic)
        // Make the system tab bar disappear into the canvas — no system
        // material strip at the bottom of the screen. When the user taps the
        // canvas to hide chrome, the tab bar hides too for true full-screen.
        .toolbarBackground(Theme.Colors.canvas, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbar(isChromeHidden ? .hidden : .visible, for: .tabBar)
        // Tool, not reading content — clamp Dynamic Type so chrome doesn't
        // overwhelm the canvas at high settings.
        .dynamicTypeSize(.xSmall ... .large)
        .task(id: importedIdentity) { await rebuildOriginalPreview() }
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
        .sheet(isPresented: $isNamePromptPresented) {
            let defaultName: String = {
                if let filterID = viewModel.stack.filter?.filterID,
                   let f = viewModel.filterLibrary.filter(withID: filterID) {
                    return "\(f.displayName) Look"
                }
                return "Untitled Look"
            }()
            RecipeNamePromptView(
                title: "Save Recipe",
                initialName: defaultName,
                onSubmit: { name in
                    isNamePromptPresented = false
                    Task { await viewModel.saveCurrentAsRecipe(name: name) }
                },
                onCancel: { isNamePromptPresented = false }
            )
        }
        .sheet(isPresented: $showingMaskRefinement) {
            MaskRefinementSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Top bar

    private var editorTopBar: some View {
        HStack(spacing: Theme.Spacing.lg) {
            // Undo / Redo on the left, sized like VSCO's hairline icons.
            Button {
                Haptic.play(.undoRedo)
                viewModel.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 15, weight: .semibold))
            }
            .disabled(!viewModel.canUndo)
            .accessibilityLabel("Undo")

            Button {
                Haptic.play(.undoRedo)
                viewModel.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 15, weight: .semibold))
            }
            .disabled(!viewModel.canRedo)
            .accessibilityLabel("Redo")

            // Mask button: enter masked mode (Vision compute) or open refinement.
            MaskToolbarButton(viewModel: viewModel, onTapRefine: {
                showingMaskRefinement = true
            })

            // Histogram overlay toggle. Disabled until a photo is loaded.
            Button {
                Haptic.play(.undoRedo)
                viewModel.toggleHistogram()
            } label: {
                Image(systemName: viewModel.isHistogramVisible ? "chart.bar.fill" : "chart.bar")
                    .font(.system(size: 15, weight: .semibold))
            }
            .disabled(viewModel.importedImage == nil)
            .accessibilityLabel("Histogram")
            .accessibilityValue(viewModel.isHistogramVisible ? "On" : "Off")

            // Side-by-side compare toggle. Recenters the divider every entry.
            Button {
                Haptic.play(.undoRedo)
                if !isSplitCompareActive { splitPosition = 0.5 }
                withAnimation(Motion.adaptive(Motion.panel)) {
                    isSplitCompareActive.toggle()
                }
            } label: {
                Image(systemName: isSplitCompareActive
                      ? "rectangle.split.2x1.fill"
                      : "rectangle.split.2x1")
                    .font(.system(size: 15, weight: .semibold))
            }
            .disabled(viewModel.importedImage == nil)
            .accessibilityLabel("Side-by-side compare")
            .accessibilityValue(isSplitCompareActive ? "On" : "Off")

            Spacer()

            // Single labeled "save" affordance. Replaces the previous 4-icon
            // toolbar where Save-to-Library / Save-as-Recipe / Save-to-Photos /
            // Reset were all separate icons with no labels.
            Menu {
                Button {
                    Task { await viewModel.saveToLibrary() }
                } label: {
                    Label("Save to Library", systemImage: "tray.and.arrow.down")
                }
                .disabled(viewModel.importedImage == nil || viewModel.isSaving)

                Button {
                    isNamePromptPresented = true
                } label: {
                    Label("Save as Recipe", systemImage: "doc.badge.plus")
                }
                .disabled(viewModel.importedImage == nil || viewModel.stack == .identity)

                Button {
                    isExportSheetPresented = true
                } label: {
                    Label("Save to Photos…", systemImage: "square.and.arrow.up.on.square")
                }
                .disabled(viewModel.importedImage == nil)

                Divider()

                Button(role: .destructive) {
                    viewModel.resetAdjustments()
                } label: {
                    Label("Reset All Edits", systemImage: "arrow.counterclockwise")
                }
                .disabled(viewModel.importedImage == nil || viewModel.stack == .identity)
            } label: {
                Text("DONE")
                    .font(Theme.Typography.label)
                    .tracking(1.5)
                    .foregroundStyle(viewModel.importedImage == nil ? Theme.Colors.secondary : Theme.Colors.text)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)
            }
            .disabled(viewModel.importedImage == nil)
            .accessibilityLabel("Save options")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .frame(height: 44)
    }

    // MARK: - Limited-access banner

    private var limitedAccessBanner: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Theme.Colors.text)
            Text("Limited photo access — tap to manage")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.text)
            Spacer()
            Button { didDismissLimitedBanner = true } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.secondary)
            }
            .accessibilityLabel("Dismiss limited access banner")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.panel)
        .contentShape(Rectangle())
        .onTapGesture { PhotoLibraryAccess.presentLimitedPicker() }
    }

    // MARK: - Canvas

    private var editorPreview: some View {
        ZStack {
            Theme.Colors.canvas.ignoresSafeArea()

            if isSplitCompareActive,
               let edited = viewModel.previewImage,
               let original = originalPreviewImage {
                // Side-by-side split: original on left of the divider, edited
                // on the right, draggable vertical handle in between.
                SplitCompareView(
                    original: original,
                    edited: edited,
                    splitPosition: $splitPosition
                )
                .overlay(alignment: .topLeading) {
                    Text("COMPARE")
                        .font(Theme.Typography.label)
                        .tracking(1.5)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(.thinMaterial, in: Capsule())
                        .padding(Theme.Spacing.md)
                }
            } else if let image = displayedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topLeading) {
                        if showOriginal {
                            Text("ORIGINAL")
                                .font(Theme.Typography.label)
                                .tracking(1.5)
                                .padding(.horizontal, Theme.Spacing.sm)
                                .padding(.vertical, Theme.Spacing.xs)
                                .background(.thinMaterial, in: Capsule())
                                .padding(Theme.Spacing.md)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if viewModel.isHistogramVisible, viewModel.importedImage != nil {
                            HistogramOverlayView(image: viewModel.histogramImage)
                                .padding(Theme.Spacing.md)
                                .transition(.opacity)
                        }
                    }
            } else if viewModel.importedImage != nil {
                ProgressView().controlSize(.large)
            } else {
                emptyEditorState
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // In split mode, taps are reserved for the divider drag — don't
            // toggle chrome out from under the user.
            guard viewModel.importedImage != nil, !isSplitCompareActive else { return }
            withAnimation(Motion.adaptive(Motion.panel)) { isChromeHidden.toggle() }
        }
        // Press-and-hold quick-compare is suppressed in split mode so the
        // gesture doesn't fight with the divider drag.
        .compareOnLongPress(showOriginal: isSplitCompareActive
                            ? .constant(false)
                            : $showOriginal)
        .accessibilityLabel("Photo canvas")
        .accessibilityHint("Tap to toggle full-screen. Press and hold to compare with the original.")
    }

    private var emptyEditorState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "photo")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.Colors.secondary)
            Text("NO PHOTO LOADED")
                .font(Theme.Typography.label)
                .tracking(1.5)
                .foregroundStyle(Theme.Colors.text)
            Text("Pick one from the Studio tab")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondary)
        }
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
}

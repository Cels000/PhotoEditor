import AudioToolbox
import AVFoundation
import SwiftUI

/// Full-screen camera modal. Composed of preview, top bar, bottom carousel,
/// shutter, and tap-to-focus overlays. This file scaffolds the chrome;
/// preview composition lands in Task 10, carousel UI in Task 11.
struct CameraView: View {

    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: CameraViewModel
    let session: CameraSession

    @State private var permissionStatus: AVAuthorizationStatus = .notDetermined
    @State private var renderer: CameraPreviewRenderer?
    @State private var focusPoint: CGPoint?
    @State private var exposureBias: Float = 0
    @State private var showExposureSlider: Bool = false
    @State private var hideSliderTask: Task<Void, Never>?
    @State private var scrolledID: String?
    @State private var showPresetGrid: Bool = false
    @State private var shutterFlash: Bool = false
    @State private var shutterPress: Bool = false

    var body: some View {
        ZStack {
            Theme.Colors.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                if let renderer {
                    previewArea(renderer: renderer)
                        .aspectRatio(3/4, contentMode: .fit)
                }
                Spacer(minLength: 0)
                bottomDeck
            }

            Color.black
                .ignoresSafeArea()
                .opacity(shutterFlash ? 1 : 0)
                .allowsHitTesting(false)
        }
        .task {
            permissionStatus = await CameraPermissions.request()
            guard permissionStatus == .authorized else { return }
            let r = CameraPreviewRenderer(cubeResolver: viewModel.cubeResolver)
            r.setStack(viewModel.selectedSlot.stack)
            r.isFrontCamera = (session.position == .front)
            session.sampleBufferDelegate = r
            renderer = r
            viewModel.attachThumbnailer(renderer: r)
            viewModel.bindHEIC(provider: { try await session.capturePhoto() })
            viewModel.bindFront(isFront: { session.position == .front })
            session.start()
        }
        .onChange(of: viewModel.selectedSlotID) { _, _ in
            renderer?.setStack(viewModel.selectedSlot.stack)
        }
        .onDisappear {
            session.stop()
            viewModel.detachThumbnailer()
        }
        .alert("Camera access needed", isPresented: Binding(
            get: { permissionStatus == .denied || permissionStatus == .restricted },
            set: { _ in })) {
            Button("Open Settings") { CameraPermissions.openSettings() }
            Button("Close", role: .cancel) { dismiss() }
        } message: {
            Text("Enable camera access in Settings to shoot through your presets.")
        }
        .sheet(isPresented: $showPresetGrid) {
            CameraPresetGridView(viewModel: viewModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
            }
            Spacer()
            if session.hasFlash {
                Button { cycleFlash() } label: {
                    Image(systemName: flashIconName)
                        .font(.system(size: 18, weight: .medium))
                }
            }
            Button { showPresetGrid = true } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 18, weight: .medium))
            }
            Button { viewModel.gridEnabled.toggle() } label: {
                Image(systemName: viewModel.gridEnabled ? "grid" : "grid")
                    .font(.system(size: 18, weight: .medium))
                    .opacity(viewModel.gridEnabled ? 1.0 : 0.5)
            }
        }
        .frame(height: 44)
        .padding(.horizontal, Theme.Spacing.lg)
        .foregroundStyle(Theme.Colors.text)
    }

    private var flashIconName: String {
        switch viewModel.flashMode {
        case .on:   return "bolt.fill"
        case .off:  return "bolt.slash.fill"
        default:    return "bolt.badge.a.fill"
        }
    }

    private func cycleFlash() {
        let next: AVCaptureDevice.FlashMode
        switch viewModel.flashMode {
        case .auto: next = .on
        case .on:   next = .off
        default:    next = .auto
        }
        viewModel.flashMode = next
        session.setFlashMode(next)
    }

    // MARK: - Shutter row

    private var shutterRow: some View {
        HStack {
            // Leading 44×44 slot — recent-shot thumbnail (Apple Camera convention)
            // or invisible placeholder so the shutter stays geometrically centered.
            recentShotTile
            Spacer()
            Button {
                Task {
                    withAnimation(.easeOut(duration: 0.08)) { shutterPress = true }
                    await runCapture()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { shutterPress = false }
                }
            } label: {
                ZStack {
                    // Outer ring + inner disc both use Theme.Colors.text so the
                    // shutter has contrast against canvas in both light and dark
                    // modes (canvas is pure white / pure black).
                    Circle()
                        .stroke(Theme.Colors.text, lineWidth: 3)
                        .frame(width: 72, height: 72)
                    Circle()
                        .fill(Theme.Colors.text)
                        .frame(width: 60, height: 60)
                        .scaleEffect(shutterPress ? 0.78 : 1.0)
                }
                .frame(width: 80, height: 80)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.captureInFlight)
            .opacity(viewModel.captureInFlight ? 0.85 : 1.0)
            Spacer()
            if session.hasFrontCamera {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    session.flipCamera()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Theme.Colors.text)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .frame(height: 96)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.lg)
    }

    @ViewBuilder
    private var recentShotTile: some View {
        if let item = viewModel.libraryStore.items.first,
           let data = item.thumbnailData,
           let ui = UIImage(data: data) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(uiImage: ui)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Theme.Colors.text.opacity(0.4), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private func runCapture() async {
        // System shutter sound (1108) — same id Apple's Camera plays.
        AudioServicesPlaySystemSound(1108)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        shutterFlash = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            withAnimation(.easeOut(duration: 0.15)) { shutterFlash = false }
        }
        do { try await viewModel.capture() }
        catch { viewModel.errorMessage = "Couldn't save photo." }
    }

    // MARK: - Bottom deck (carousel + label + shutter)

    private var bottomDeck: some View {
        VStack(spacing: Theme.Spacing.sm) {
            categoryLine
            presetStrip
            shutterRow
        }
    }

    @ViewBuilder
    private var categoryLine: some View {
        let slot = viewModel.selectedSlot
        if let categoryText = slot.categoryDisplayName {
            Button {
                jumpToNextCategory()
            } label: {
                HStack(spacing: 2) {
                    Text(categoryText)
                        .font(Theme.Typography.label)
                        .tracking(2)
                        .foregroundStyle(Theme.Colors.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Theme.Colors.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(height: 16)
        } else {
            Color.clear.frame(height: 16)
        }
    }

    private var presetStrip: some View {
        let cellWidth: CGFloat = 80
        let edge: CGFloat = 72
        let selectedIdx = viewModel.slots.firstIndex(where: { $0.id == viewModel.selectedSlotID })
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: Theme.Spacing.xs) {
                    HStack(spacing: 0) {
                        ForEach(Array(viewModel.slots.enumerated()), id: \.element.id) { idx, slot in
                            let distance: Int = {
                                guard let selectedIdx else { return 0 }
                                return abs(idx - selectedIdx)
                            }()
                            let (color, opacity, scale): (Color, Double, CGFloat) = {
                                switch distance {
                                case 0: return (Theme.Colors.text, 1.0, 1.0)
                                case 1: return (Theme.Colors.secondary, 0.7, 0.9)
                                case 2: return (Theme.Colors.secondary, 0.35, 0.85)
                                default: return (Theme.Colors.secondary, 0.0, 0.85)
                                }
                            }()
                            Text(slot.displayName.uppercased())
                                .font(Theme.Typography.label)
                                .tracking(2)
                                .foregroundStyle(color)
                                .opacity(opacity)
                                .scaleEffect(scale)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: cellWidth, height: 36, alignment: .bottom)
                        }
                    }
                    HStack(spacing: 0) {
                        ForEach(Array(viewModel.slots.enumerated()), id: \.element.id) { idx, slot in
                            thumbnailCell(for: slot, edge: edge, index: idx)
                                .frame(width: cellWidth)
                                .id(slot.id)
                                .onAppear { addVisible(slot.id) }
                                .onDisappear { removeVisible(slot.id) }
                        }
                    }
                    .scrollTargetLayout()
                }
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrolledID, anchor: .center)
            .frame(height: 36 + Theme.Spacing.xs + edge + 8)
            .onAppear {
                scrolledID = viewModel.selectedSlotID
                proxy.scrollTo(viewModel.selectedSlotID, anchor: .center)
            }
            .onChange(of: scrolledID) { _, newID in
                guard let newID, newID != viewModel.selectedSlotID,
                      let slot = viewModel.slots.first(where: { $0.id == newID })
                else { return }
                viewModel.selectSlot(slot)
            }
            .onChange(of: viewModel.selectedSlotID) { _, newID in
                // Skip programmatic scrollTo when the selection change came
                // from the user's own scroll — otherwise we fight their flick
                // and the carousel jitters.
                if scrolledID == newID { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
    }

    private func thumbnailCell(for slot: CameraSlot, edge: CGFloat, index: Int) -> some View {
        let isSelected = slot.id == viewModel.selectedSlotID
        let cg = viewModel.thumbnailer?.thumbnails[slot.id]
        let showsCategoryBoundary: Bool = {
            guard index > 0 else { return false }
            return categoryKey(for: slot) != categoryKey(for: viewModel.slots[index - 1])
        }()
        return Button {
            viewModel.selectSlot(slot)
        } label: {
            ZStack {
                if let cg {
                    Image(cg, scale: 1, label: Text(slot.displayName))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: edge, height: edge)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Theme.Colors.secondary.opacity(0.2))
                        .frame(width: edge, height: edge)
                }
            }
            .overlay(
                Rectangle()
                    .stroke(Color.white,
                            lineWidth: isSelected ? 2 : 0)
            )
            .overlay(alignment: .leading) {
                if showsCategoryBoundary {
                    Rectangle()
                        .fill(Theme.Colors.secondary.opacity(0.3))
                        .frame(width: 1, height: edge)
                        .offset(x: -4)
                }
            }
            .scaleEffect(isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
    }

    private func categoryKey(for slot: CameraSlot) -> String {
        switch slot {
        case .original:        return "__original__"
        case .recipe:          return slot.categoryDisplayName ?? "__uncategorized__"
        }
    }

    private func firstSlotIDOfNextCategory(after slotID: String) -> String? {
        let slots = viewModel.slots
        guard let idx = slots.firstIndex(where: { $0.id == slotID }) else { return nil }
        let currentKey = categoryKey(for: slots[idx])
        for i in (idx + 1)..<slots.count {
            if categoryKey(for: slots[i]) != currentKey {
                return slots[i].id
            }
        }
        return CameraSlot.originalID
    }

    private func jumpToNextCategory() {
        guard let nextID = firstSlotIDOfNextCategory(after: viewModel.selectedSlotID),
              let nextSlot = viewModel.slots.first(where: { $0.id == nextID })
        else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        viewModel.selectSlot(nextSlot)
    }

    private func addVisible(_ id: String) {
        var s = viewModel.thumbnailer?.visibleSlotIDs ?? []
        s.insert(id)
        viewModel.thumbnailer?.setVisibleSlotIDs(s)
    }

    private func removeVisible(_ id: String) {
        var s = viewModel.thumbnailer?.visibleSlotIDs ?? []
        s.remove(id)
        viewModel.thumbnailer?.setVisibleSlotIDs(s)
    }

    // MARK: - Preview area

    @ViewBuilder
    private func previewArea(renderer: CameraPreviewRenderer) -> some View {
        GeometryReader { geo in
            ZStack {
                CameraPreviewView(renderer: renderer)
                if viewModel.gridEnabled {
                    gridOverlay
                }
                if let p = focusPoint {
                    Circle()
                        .stroke(Color.white, lineWidth: 1.5)
                        .frame(width: 64, height: 64)
                        .position(p)
                        .transition(.opacity)
                }
                if showExposureSlider {
                    HStack {
                        Spacer()
                        exposureSlider
                            .frame(width: 32, height: 200)
                            .padding(.trailing, Theme.Spacing.md)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleTap(at: location, in: geo.size)
            }
        }
    }

    private var gridOverlay: some View {
        GeometryReader { geo in
            Path { p in
                let w = geo.size.width, h = geo.size.height
                p.move(to: CGPoint(x: w/3, y: 0));    p.addLine(to: CGPoint(x: w/3,   y: h))
                p.move(to: CGPoint(x: 2*w/3, y: 0));  p.addLine(to: CGPoint(x: 2*w/3, y: h))
                p.move(to: CGPoint(x: 0, y: h/3));    p.addLine(to: CGPoint(x: w,     y: h/3))
                p.move(to: CGPoint(x: 0, y: 2*h/3));  p.addLine(to: CGPoint(x: w,     y: 2*h/3))
            }
            .stroke(Color.white.opacity(0.3), lineWidth: 1)
        }
    }

    private var exposureSlider: some View {
        VStack {
            Image(systemName: "sun.max.fill").foregroundStyle(.white)
            Slider(value: Binding(
                get: { Double(exposureBias) },
                set: { newVal in
                    exposureBias = Float(newVal)
                    session.setExposureCompensation(exposureBias)
                    rescheduleSliderHide()
                }),
                in: -2...2)
                .rotationEffect(.degrees(-90))
                .frame(width: 200)
                .tint(.white)
            Text(String(format: "%+.1f", exposureBias))
                .font(.caption2).foregroundStyle(.white)
        }
    }

    private func handleTap(at location: CGPoint, in size: CGSize) {
        focusPoint = location
        let nx = location.x / size.width
        let ny = location.y / size.height
        session.setFocusPoint(CGPoint(x: nx, y: ny))
        showExposureSlider = true
        rescheduleSliderHide()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            withAnimation { focusPoint = nil }
        }
    }

    private func rescheduleSliderHide() {
        hideSliderTask?.cancel()
        hideSliderTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { withAnimation { showExposureSlider = false } }
        }
    }
}

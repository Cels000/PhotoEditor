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
    @State private var ghostsVisible: Bool = false
    @State private var scrolledID: String?

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
            Button { viewModel.gridEnabled.toggle() } label: {
                Image(systemName: viewModel.gridEnabled ? "grid" : "grid")
                    .font(.system(size: 18, weight: .medium))
                    .opacity(viewModel.gridEnabled ? 1.0 : 0.5)
            }
            if session.hasFrontCamera {
                Button { session.flipCamera() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 18, weight: .medium))
                }
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
        Button {
            Task { await runCapture() }
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
            }
            .frame(width: 80, height: 80)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.captureInFlight)
        .opacity(viewModel.captureInFlight ? 0.6 : 1.0)
        .frame(height: 96)
        .padding(.bottom, Theme.Spacing.lg)
    }

    private func runCapture() async {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        do { try await viewModel.capture() }
        catch { viewModel.errorMessage = "Couldn't save photo." }
    }

    // MARK: - Bottom deck (carousel + label + shutter)

    private var bottomDeck: some View {
        VStack(spacing: Theme.Spacing.sm) {
            carousel
            labelRow
            shutterRow
        }
    }

    private var labelRow: some View {
        let cellEdge: CGFloat = 72
        let cellSpacing: CGFloat = 8
        let neighborOffset: CGFloat = cellEdge + cellSpacing
        let slot = viewModel.selectedSlot
        let idx = viewModel.slots.firstIndex(where: { $0.id == slot.id })
        let leftSlot: CameraSlot? = {
            guard let idx, idx > 0 else { return nil }
            return viewModel.slots[idx - 1]
        }()
        let rightSlot: CameraSlot? = {
            guard let idx, idx < viewModel.slots.count - 1 else { return nil }
            return viewModel.slots[idx + 1]
        }()

        return ZStack {
            if let leftSlot {
                ghostLabel(for: leftSlot)
                    .offset(x: -neighborOffset)
            }
            if let rightSlot {
                ghostLabel(for: rightSlot)
                    .offset(x: neighborOffset)
            }
            centeredLabel(for: slot)
        }
        .frame(height: 16)
    }

    @ViewBuilder
    private func centeredLabel(for slot: CameraSlot) -> some View {
        let name = Text(slot.displayName.uppercased())
            .font(Theme.Typography.label)
            .tracking(2)
            .foregroundStyle(Theme.Colors.text)

        if let categoryText = slot.categoryDisplayName {
            HStack(spacing: 6) {
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
                Text("·")
                    .font(Theme.Typography.label)
                    .tracking(2)
                    .foregroundStyle(Theme.Colors.secondary)
                name
            }
        } else {
            name
        }
    }

    @ViewBuilder
    private func ghostLabel(for slot: CameraSlot) -> some View {
        Text(slot.displayName.uppercased())
            .font(Theme.Typography.label)
            .tracking(2)
            .foregroundStyle(Theme.Colors.text.opacity(0.4))
            .scaleEffect(0.85)
            .opacity(ghostsVisible ? 1 : 0)
    }

    @ViewBuilder
    private var carousel: some View {
        let edge: CGFloat = 72
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(viewModel.slots.enumerated()), id: \.element.id) { idx, slot in
                        carouselCell(for: slot, edge: edge, index: idx)
                            .id(slot.id)
                            .onAppear { addVisible(slot.id) }
                            .onDisappear { removeVisible(slot.id) }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $scrolledID, anchor: .center)
            .frame(height: edge + 8)
            .onAppear {
                scrolledID = viewModel.selectedSlotID
                proxy.scrollTo(viewModel.selectedSlotID, anchor: .center)
            }
            // Guard prevents scroll<->select feedback loop with the
            // proxy.scrollTo below.
            .onChange(of: scrolledID) { _, newID in
                guard let newID, newID != viewModel.selectedSlotID,
                      let slot = viewModel.slots.first(where: { $0.id == newID })
                else { return }
                viewModel.selectSlot(slot)
            }
            // Ghost labels are tied to scroll phase rather than centered-cell
            // identity so they fade out only after the user releases, not on
            // every snap during a continuous flick.
            .onScrollPhaseChange { _, newPhase in
                let active = (newPhase != .idle)
                withAnimation(.easeInOut(duration: active ? 0.12 : 0.25)) {
                    ghostsVisible = active
                }
            }
            .onChange(of: viewModel.selectedSlotID) { _, newID in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
    }


    private func carouselCell(for slot: CameraSlot, edge: CGFloat, index: Int) -> some View {
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

import AudioToolbox
import AVFoundation
import CoreMotion
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
    @State private var showSaveRecipe: Bool = false
    @State private var comparing: Bool = false
    @State private var shutterFlash: Bool = false
    @State private var shutterPress: Bool = false
    @State private var pinchBaseZoom: CGFloat = 1.0
    @State private var liveZoom: CGFloat = 1.0
    @State private var zoomPillVisible: Bool = false
    @State private var zoomPillHideTask: Task<Void, Never>?
    @State private var countdown: Int = 0
    @State private var countingDown: Bool = false
    @State private var motionManager = CMMotionManager()
    @State private var roll: Double = 0

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
            r.setStack(viewModel.effectiveStack)
            r.isFrontCamera = (session.position == .front)
            session.sampleBufferDelegate = r
            renderer = r
            viewModel.attachThumbnailer(renderer: r)
            viewModel.bindHEIC(provider: { try await session.capturePhoto() })
            viewModel.bindFront(isFront: { session.position == .front })
            session.start()
            session.startVolumeButtonShutter {
                Task { @MainActor in
                    if !viewModel.captureInFlight && !countingDown {
                        await runCapture()
                    }
                }
            }
            startMotionIfNeeded()
        }
        .onChange(of: viewModel.levelEnabled) { _, enabled in
            if enabled { startMotionIfNeeded() } else { stopMotion() }
        }
        .onChange(of: viewModel.selectedSlotID) { _, _ in
            renderer?.setStack(viewModel.effectiveStack)
        }
        .onChange(of: viewModel.slotIntensities) { _, _ in
            renderer?.setStack(viewModel.effectiveStack)
        }
        .onDisappear {
            session.stop()
            session.stopVolumeButtonShutter()
            stopMotion()
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
        .sheet(isPresented: $showSaveRecipe) {
            RecipeNamePromptView(
                title: "Save Recipe",
                initialName: viewModel.selectedSlot.displayName,
                onSubmit: { name in
                    viewModel.saveCurrentAsRecipe(named: name)
                    showSaveRecipe = false
                },
                onCancel: { showSaveRecipe = false }
            )
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
            Button { cycleTimer() } label: {
                HStack(spacing: 2) {
                    Image(systemName: "timer")
                        .font(.system(size: 18, weight: .medium))
                        .opacity(viewModel.timerSeconds == 0 ? 0.5 : 1.0)
                    if viewModel.timerSeconds > 0 {
                        Text("\(viewModel.timerSeconds)s")
                            .font(Theme.Typography.label)
                            .tracking(1)
                    }
                }
            }
            Button {
                viewModel.levelEnabled.toggle()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "level")
                    .font(.system(size: 18, weight: .medium))
                    .opacity(viewModel.levelEnabled ? 1.0 : 0.5)
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
            .disabled(viewModel.captureInFlight || countingDown)
            .opacity((viewModel.captureInFlight || countingDown) ? 0.85 : 1.0)
            Spacer()
            if session.hasFrontCamera {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    session.flipCamera()
                    pinchBaseZoom = 1.0
                    liveZoom = 1.0
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

    private func cycleTimer() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        switch viewModel.timerSeconds {
        case 0:  viewModel.timerSeconds = 3
        case 3:  viewModel.timerSeconds = 10
        default: viewModel.timerSeconds = 0
        }
    }

    private func runCapture() async {
        if viewModel.timerSeconds > 0 {
            countingDown = true
            countdown = viewModel.timerSeconds
            for _ in 0..<viewModel.timerSeconds {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                countdown -= 1
            }
            countingDown = false
        }
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
            intensityControl
            shutterRow
        }
    }

    @ViewBuilder
    private var intensityControl: some View {
        let slot = viewModel.selectedSlot
        if case .original = slot {
            // Reserve the height so the deck doesn't jitter when switching to/from
            // the original slot.
            Color.clear.frame(height: 28)
        } else {
            let current = viewModel.intensity(for: viewModel.selectedSlotID)
            HStack(spacing: Theme.Spacing.sm) {
                Text("INTENSITY")
                    .font(Theme.Typography.label)
                    .tracking(2)
                    .foregroundStyle(Theme.Colors.secondary)
                    .frame(width: 90, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { current },
                        set: { viewModel.setIntensity($0, for: viewModel.selectedSlotID) }
                    ),
                    in: 0...1
                )
                .tint(Theme.Colors.text)
                Text("\(Int(current * 100))%")
                    .font(Theme.Typography.label)
                    .tracking(1)
                    .foregroundStyle(Theme.Colors.secondary)
                    .frame(width: 44, alignment: .trailing)
                    .monospacedDigit()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showSaveRecipe = true
                } label: {
                    Image(systemName: "bookmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.Colors.text)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(height: 28)
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
        let displayed = viewModel.displayedSlots
        let selectedIdx = displayed.firstIndex(where: { $0.id == viewModel.selectedSlotID })
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: Theme.Spacing.xs) {
                    HStack(spacing: 0) {
                        ForEach(Array(displayed.enumerated()), id: \.element.id) { idx, slot in
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
                        ForEach(Array(displayed.enumerated()), id: \.element.id) { idx, slot in
                            thumbnailCell(for: slot, edge: edge, index: idx, displayed: displayed)
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
                      let slot = viewModel.displayedSlots.first(where: { $0.id == newID })
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

    private func thumbnailCell(for slot: CameraSlot, edge: CGFloat, index: Int, displayed: [CameraSlot]) -> some View {
        let isSelected = slot.id == viewModel.selectedSlotID
        let cg = viewModel.thumbnailer?.thumbnails[slot.id]
        let recentsIDs = viewModel.recentsSectionIDs
        let showsCategoryBoundary: Bool = {
            guard index > 0 else { return false }
            return categoryKey(for: slot, recentsIDs: recentsIDs) != categoryKey(for: displayed[index - 1], recentsIDs: recentsIDs)
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
            .overlay(alignment: .bottomTrailing) {
                let pct = viewModel.intensity(for: slot.id)
                if isSelected, !slot.isOriginal, pct < 0.999 {
                    Text("\(Int(pct * 100))%")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.65))
                        .clipShape(Capsule())
                        .padding(4)
                        .monospacedDigit()
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func categoryKey(for slot: CameraSlot, recentsIDs: Set<String> = []) -> String {
        if recentsIDs.contains(slot.id) { return "__recents__" }
        switch slot {
        case .original:        return "__original__"
        case .recipe:          return slot.categoryDisplayName ?? "__uncategorized__"
        }
    }

    private func firstSlotIDOfNextCategory(after slotID: String) -> String? {
        let slots = viewModel.displayedSlots
        let recentsIDs = viewModel.recentsSectionIDs
        guard let idx = slots.firstIndex(where: { $0.id == slotID }) else { return nil }
        let currentKey = categoryKey(for: slots[idx], recentsIDs: recentsIDs)
        for i in (idx + 1)..<slots.count {
            if categoryKey(for: slots[i], recentsIDs: recentsIDs) != currentKey {
                return slots[i].id
            }
        }
        return CameraSlot.originalID
    }

    private func jumpToNextCategory() {
        guard let nextID = firstSlotIDOfNextCategory(after: viewModel.selectedSlotID),
              let nextSlot = viewModel.displayedSlots.first(where: { $0.id == nextID })
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
                if viewModel.levelEnabled {
                    levelLine(in: geo.size)
                }
                if countdown > 0 {
                    Text("\(countdown)")
                        .font(.system(size: 96, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(.black.opacity(0.5))
                        .clipShape(Capsule())
                        .transition(.opacity)
                        .id(countdown)
                }
                VStack {
                    if zoomPillVisible && liveZoom > 1.05 {
                        Text(String(format: "%.1f×", liveZoom))
                            .font(Theme.Typography.label)
                            .tracking(1)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.5))
                            .clipShape(Capsule())
                            .padding(.top, Theme.Spacing.md)
                            .transition(.opacity)
                    }
                    Spacer()
                }
                VStack {
                    Text("ORIGINAL")
                        .font(Theme.Typography.label)
                        .tracking(2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.5))
                        .clipShape(Capsule())
                        .padding(.top, Theme.Spacing.md)
                        .opacity(comparing ? 1 : 0)
                        .animation(.easeInOut(duration: 0.15), value: comparing)
                    Spacer()
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleTap(at: location, in: geo.size)
            }
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { scale in
                        let target = pinchBaseZoom * scale
                        let clamped = min(5.0, max(1.0, target))
                        liveZoom = clamped
                        session.setZoomFactor(target)
                        zoomPillVisible = true
                        zoomPillHideTask?.cancel()
                    }
                    .onEnded { _ in
                        pinchBaseZoom = session.zoomFactor
                        liveZoom = session.zoomFactor
                        zoomPillHideTask?.cancel()
                        zoomPillHideTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            if !Task.isCancelled {
                                withAnimation(.easeOut(duration: 0.25)) { zoomPillVisible = false }
                            }
                        }
                    }
            )
            .gesture(
                LongPressGesture(minimumDuration: 0.4)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onChanged { value in
                        if case .second(true, _) = value, !comparing {
                            comparing = true
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            renderer.setStack(.identity)
                        }
                    }
                    .onEnded { _ in
                        if comparing {
                            comparing = false
                            renderer.setStack(viewModel.effectiveStack)
                        }
                    }
            )
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

    @ViewBuilder
    private func levelLine(in size: CGSize) -> some View {
        // Add π/2: portrait device frame's roll axis is rotated 90° relative
        // to the screen's horizontal.
        let adjusted = roll + .pi / 2
        let isLevel = abs(adjusted.truncatingRemainder(dividingBy: .pi)) < 0.03
            || abs(abs(adjusted.truncatingRemainder(dividingBy: .pi)) - .pi) < 0.03
        Rectangle()
            .fill(isLevel ? Color.yellow : Color.white.opacity(0.4))
            .frame(width: size.width * 0.7, height: 1)
            .position(x: size.width / 2, y: size.height / 2)
            .rotationEffect(.radians(adjusted))
            .allowsHitTesting(false)
    }

    private func startMotionIfNeeded() {
        guard viewModel.levelEnabled,
              motionManager.isDeviceMotionAvailable,
              !motionManager.isDeviceMotionActive else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let m = motion else { return }
            roll = m.attitude.roll
        }
    }

    private func stopMotion() {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
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

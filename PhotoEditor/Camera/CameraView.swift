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

    var body: some View {
        ZStack {
            Theme.Colors.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                shutterRow
            }
        }
        .task {
            permissionStatus = await CameraPermissions.request()
            if permissionStatus == .authorized {
                session.start()
            }
        }
        .onDisappear { session.stop() }
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
        ZStack {
            Button {
                Task { await runCapture() }
            } label: {
                Circle()
                    .fill(Color.white)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 72, height: 72)
                    )
            }
            .disabled(viewModel.captureInFlight)
            .opacity(viewModel.captureInFlight ? 0.6 : 1.0)
        }
        .frame(height: 96)
        .padding(.bottom, Theme.Spacing.lg)
    }

    private func runCapture() async {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        do { try await viewModel.capture() }
        catch { viewModel.errorMessage = "Couldn't save photo." }
    }
}

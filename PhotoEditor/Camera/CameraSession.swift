import AVFoundation
import CoreMedia
import Foundation
import UIKit

enum CameraPosition { case back, front }

enum CameraError: Error {
    case noCameraAvailable
    case noPhotoOutput
    case captureFailed(Error?)
    case captureInFlight
}

/// Wraps AVCaptureSession. Owns inputs (back/front), the video data output
/// for live frames, and the photo output for stills. All session mutations
/// run on a serial sessionQueue per Apple's guidance, while the public API
/// is @MainActor so SwiftUI can call it ergonomically.
@MainActor
final class CameraSession: NSObject {

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.photoeditor.camera.session")
    private(set) var position: CameraPosition = .back

    private var videoInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var volumeObservation: NSKeyValueObservation?

    /// Set this BEFORE `start()` so the renderer receives sample buffers.
    weak var sampleBufferDelegate: AVCaptureVideoDataOutputSampleBufferDelegate?
    var sampleBufferQueue: DispatchQueue = DispatchQueue(label: "com.photoeditor.camera.preview")

    private var photoContinuation: CheckedContinuation<Data, Error>?

    func start() {
        sessionQueue.async { [weak self] in
            self?.configureIfNeeded()
            if self?.session.isRunning == false { self?.session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            if self?.session.isRunning == true { self?.session.stopRunning() }
        }
    }

    private func configureIfNeeded() {
        guard videoInput == nil else { return }   // first-time only
        session.beginConfiguration()
        // Setting device.activeFormat below switches the session to
        // .inputPriority automatically; explicit preset would just be
        // overridden, so we don't set one.
        attachInput(position: position)
        applyHighQualityFormat()

        videoOutput.setSampleBufferDelegate(sampleBufferDelegate, queue: sampleBufferQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        if let conn = videoOutput.connection(with: .video),
           conn.isVideoStabilizationSupported {
            conn.preferredVideoStabilizationMode = .auto
        }

        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        photoOutput.maxPhotoQualityPrioritization = .quality

        session.commitConfiguration()

        // Activate the audio session AFTER commitConfiguration — setting the
        // category mid-config can interfere with capture session setup.
        // Failure isn't fatal; volume-button shutter just won't work.
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord,
                                                        options: [.mixWithOthers,
                                                                  .defaultToSpeaker])
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
    }

    // MARK: - Zoom

    func setZoomFactor(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                let cap = min(device.activeFormat.videoMaxZoomFactor, 5.0)
                // Cap at 5× — beyond that the digital crop quality falls
                // apart on wide-angle sensors.
                device.videoZoomFactor = min(cap, max(1.0, factor))
                device.unlockForConfiguration()
            } catch {}
        }
    }

    var zoomFactor: CGFloat {
        videoInput?.device.videoZoomFactor ?? 1.0
    }

    // MARK: - Volume button shutter

    func startVolumeButtonShutter(handler: @escaping () -> Void) {
        let session = AVAudioSession.sharedInstance()
        volumeObservation = session.observe(\.outputVolume, options: [.new, .old]) { _, change in
            guard let new = change.newValue, let old = change.oldValue, new != old else { return }
            Task { @MainActor in handler() }
        }
    }

    func stopVolumeButtonShutter() {
        volumeObservation?.invalidate()
        volumeObservation = nil
    }

    /// Pick the highest-resolution 4:3 format on the active device, capped at
    /// ~8 MP per frame so the LUT pipeline can hold 30 fps without thermal
    /// throttling. Enables HDR when the chosen format supports it.
    private func applyHighQualityFormat() {
        guard let device = videoInput?.device else { return }
        let pixelCap: Int64 = 8_000_000
        let candidates = device.formats.filter { format in
            let dim = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dim.width > 0, dim.height > 0 else { return false }
            let aspect = Double(dim.width) / Double(dim.height)
            let pixels = Int64(dim.width) * Int64(dim.height)
            return abs(aspect - 4.0/3.0) < 0.05 && pixels <= pixelCap
        }
        let best = candidates.max { a, b in
            let dimA = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
            let dimB = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
            return Int64(dimA.width) * Int64(dimA.height)
                 < Int64(dimB.width) * Int64(dimB.height)
        }
        guard let format = best else { return }
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            if format.isVideoHDRSupported {
                device.automaticallyAdjustsVideoHDREnabled = false
                device.isVideoHDREnabled = true
            }
            device.unlockForConfiguration()
        } catch {
            // Fall back to whatever default the session picked.
        }
    }

    private func attachInput(position: CameraPosition) {
        let avPosition: AVCaptureDevice.Position = position == .back ? .back : .front
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: avPosition),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }
        if let existing = videoInput { session.removeInput(existing) }
        if session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
            self.position = position
        }
    }

    func flipCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let next: CameraPosition = self.position == .back ? .front : .back
            self.session.beginConfiguration()
            self.attachInput(position: next)
            self.applyHighQualityFormat()
            self.session.commitConfiguration()
        }
    }

    func setFlashMode(_ mode: AVCaptureDevice.FlashMode) {
        // Flash is set per-photo via AVCapturePhotoSettings; remember the choice.
        currentFlashMode = mode
    }

    private var currentFlashMode: AVCaptureDevice.FlashMode = .auto

    /// Normalized 0…1 focus point in the *device's* coordinate system (origin
    /// top-left when the device is in portrait — caller is responsible for
    /// the orientation conversion when mapping from a tap location).
    func setFocusPoint(_ point: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = point
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .autoExpose
                }
                device.unlockForConfiguration()
            } catch {
                // No-op: focus failures are non-fatal during shooting.
            }
        }
    }

    /// EV in the device's supported range (typically -2…+2).
    func setExposureCompensation(_ ev: Float) {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                let clamped = max(device.minExposureTargetBias,
                                  min(device.maxExposureTargetBias, ev))
                device.setExposureTargetBias(clamped, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {}
        }
    }

    var hasFrontCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    }

    var hasFlash: Bool {
        videoInput?.device.hasFlash ?? false
    }

    /// Capture a single HEIC photo at full sensor resolution. Resumes the
    /// returned async value from the AVCapturePhotoCaptureDelegate callback.
    /// Rejects re-entry while a capture is already in flight — overwriting
    /// `photoContinuation` would leak the prior continuation (CheckedContinuation
    /// runtime crash). UI should also disable the shutter while capturing.
    func capturePhoto() async throws -> Data {
        if photoContinuation != nil {
            throw CameraError.captureInFlight
        }
        return try await withCheckedThrowingContinuation { cont in
            sessionQueue.async { [weak self] in
                guard let self else {
                    cont.resume(throwing: CameraError.noPhotoOutput)
                    return
                }
                let settings = AVCapturePhotoSettings(format: [
                    AVVideoCodecKey: AVVideoCodecType.hevc
                ])
                if self.photoOutput.supportedFlashModes.contains(self.currentFlashMode) {
                    settings.flashMode = self.currentFlashMode
                }
                settings.photoQualityPrioritization = .quality
                Task { @MainActor in
                    // Guard again on MainActor — the in-flight check above ran
                    // synchronously on the caller's actor hop, but if two awaits
                    // race here, only the first wins; the second resumes its
                    // continuation with .captureInFlight rather than leaking.
                    if self.photoContinuation != nil {
                        cont.resume(throwing: CameraError.captureInFlight)
                        return
                    }
                    self.photoContinuation = cont
                    self.photoOutput.capturePhoto(with: settings, delegate: self)
                }
            }
        }
    }
}

extension CameraSession: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        Task { @MainActor in
            defer { self.photoContinuation = nil }
            if let error {
                self.photoContinuation?.resume(throwing: CameraError.captureFailed(error))
                return
            }
            guard let data = photo.fileDataRepresentation() else {
                self.photoContinuation?.resume(throwing: CameraError.captureFailed(nil))
                return
            }
            self.photoContinuation?.resume(returning: data)
        }
    }
}

import AVFoundation
import CoreMedia
import Foundation
import UIKit

enum CameraPosition { case back, front }

enum CameraError: Error {
    case noCameraAvailable
    case noPhotoOutput
    case captureFailed(Error?)
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
        session.sessionPreset = .photo            // 4:3 native
        attachInput(position: position)

        videoOutput.setSampleBufferDelegate(sampleBufferDelegate, queue: sampleBufferQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        photoOutput.maxPhotoQualityPrioritization = .quality

        session.commitConfiguration()
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
    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
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

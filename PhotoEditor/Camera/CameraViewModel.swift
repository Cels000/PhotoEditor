import AVFoundation
import CoreImage
import Foundation
import ImageIO
import Observation
import Photos
import UIKit

/// Side-effect injection seam so the view-model is unit-testable without
/// hitting the Photos library.
protocol PhotosWriter {
    /// Write a HEIC blob to the user's photo library and return the new
    /// PHAsset.localIdentifier.
    func writeHEIC(_ data: Data) async throws -> String
}

struct DefaultPhotosWriter: PhotosWriter {
    func writeHEIC(_ data: Data) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            var assetID: String?
            PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                let opts = PHAssetResourceCreationOptions()
                opts.uniformTypeIdentifier = "public.heic"
                req.addResource(with: .photo, data: data, options: opts)
                assetID = req.placeholderForCreatedAsset?.localIdentifier
            } completionHandler: { ok, err in
                if let err { cont.resume(throwing: err); return }
                guard ok, let id = assetID else {
                    cont.resume(throwing: CameraError.captureFailed(nil))
                    return
                }
                cont.resume(returning: id)
            }
        }
    }
}

@MainActor
@Observable
final class CameraViewModel {

    // MARK: - Persistence keys
    static let lastSlotKey = "camera.lastRecipeID"
    static let flashKey    = "camera.flashMode"
    static let gridKey     = "camera.gridEnabled"
    static let intensitiesKey = "camera.slotIntensities"

    // MARK: - Dependencies
    let libraryStore: LibraryStore
    let recipeStore: RecipeStore
    let cubeResolver: CubeResolver
    let photosWriter: PhotosWriter
    let heicProvider: () async throws -> Data
    /// Test seam — applies a stack to raw HEIC bytes and returns cooked HEIC
    /// bytes. Default uses RenderEngine + ExportService; tests pass a passthrough.
    let heicCooker: (Data, AdjustmentStack, Bool) async throws -> Data
    private let userDefaults: UserDefaults

    // MARK: - State
    private(set) var slots: [CameraSlot] = []
    private(set) var selectedSlotID: String = CameraSlot.originalID
    var flashMode: AVCaptureDevice.FlashMode = .auto {
        didSet { userDefaults.set(flashMode.rawValue, forKey: Self.flashKey) }
    }
    var gridEnabled: Bool = false {
        didSet { userDefaults.set(gridEnabled, forKey: Self.gridKey) }
    }
    var errorMessage: String?
    var captureInFlight: Bool = false
    private(set) var slotIntensities: [String: Double] = [:]

    // MARK: - Override hooks (wired in Task 9)
    private var heicProviderOverride: (() async throws -> Data)?
    private var isFrontProvider: (() -> Bool)?

    // MARK: - Init
    init(libraryStore: LibraryStore,
         recipeStore: RecipeStore,
         cubeResolver: @escaping CubeResolver,
         photosWriter: PhotosWriter = DefaultPhotosWriter(),
         heicProvider: (@escaping () async throws -> Data) = { throw CameraError.noPhotoOutput },
         heicCooker: (@escaping (Data, AdjustmentStack, Bool) async throws -> Data) = CameraViewModel.defaultCookHEIC,
         userDefaults: UserDefaults = .standard) {
        self.libraryStore = libraryStore
        self.recipeStore = recipeStore
        self.cubeResolver = cubeResolver
        self.photosWriter = photosWriter
        self.heicProvider = heicProvider
        self.heicCooker = heicCooker
        self.userDefaults = userDefaults

        self.slots = CameraSlot.build(from: recipeStore.items)
        self.selectedSlotID = userDefaults.string(forKey: Self.lastSlotKey) ?? CameraSlot.originalID
        if let raw = userDefaults.object(forKey: Self.flashKey) as? Int,
           let mode = AVCaptureDevice.FlashMode(rawValue: raw) {
            self.flashMode = mode
        }
        self.gridEnabled = userDefaults.bool(forKey: Self.gridKey)

        // If the persisted slot ID is no longer present (recipe deleted), fall
        // back to ORIGINAL.
        if !slots.contains(where: { $0.id == selectedSlotID }) {
            selectedSlotID = CameraSlot.originalID
        }

        if let data = userDefaults.data(forKey: Self.intensitiesKey),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            slotIntensities = decoded
        }
    }

    func intensity(for slotID: String) -> Double {
        slotIntensities[slotID] ?? 1.0
    }

    func setIntensity(_ value: Double, for slotID: String) {
        let clamped = max(0, min(1, value))
        slotIntensities[slotID] = clamped
        if let encoded = try? JSONEncoder().encode(slotIntensities) {
            userDefaults.set(encoded, forKey: Self.intensitiesKey)
        }
    }

    var effectiveStack: AdjustmentStack {
        selectedSlot.stack.scaled(by: intensity(for: selectedSlotID))
    }

    // MARK: - Public API
    var selectedSlot: CameraSlot {
        slots.first(where: { $0.id == selectedSlotID }) ?? .original
    }

    func selectSlot(_ slot: CameraSlot) {
        selectedSlotID = slot.id
        userDefaults.set(slot.id, forKey: Self.lastSlotKey)
    }

    func bindHEIC(provider: @escaping () async throws -> Data) {
        heicProviderOverride = provider
    }

    func bindFront(isFront: @escaping () -> Bool) {
        isFrontProvider = isFront
    }

    /// Capture flow: get HEIC bytes → write to Photos → import to Library
    /// with the selected slot's full stack.
    func capture() async throws {
        guard !captureInFlight else { return }
        captureInFlight = true
        defer { captureInFlight = false }

        let rawBytes = try await (heicProviderOverride ?? heicProvider)()
        let cookedStack = effectiveStack
        let isFront = isFrontProvider?() ?? false
        // Save the cooked HEIC (filter baked in) so Photos shows what the user
        // saw through the preset. Library row stores `.identity` because the
        // look is already in the pixels — re-applying the stack on open would
        // double-process. If the slot is identity AND we're not on the front
        // camera, skip the round-trip; front-cam always cooks so the preview
        // mirror flip can be baked in.
        let bytesToSave: Data
        if cookedStack == .identity && !isFront {
            bytesToSave = rawBytes
        } else {
            do {
                bytesToSave = try await heicCooker(rawBytes, cookedStack, isFront)
            } catch {
                errorMessage = "Couldn't apply preset to photo."
                throw error
            }
        }
        let assetID = try await photosWriter.writeHEIC(bytesToSave)
        // Derive a 400px thumbnail from the saved bytes so the recent-shot
        // tile in the camera + the library grid have something to show
        // immediately, before any async PHAsset thumbnail backfill.
        let thumb = Self.makeThumbnail(from: bytesToSave)
        _ = libraryStore.importFromCamera(
            assetID: assetID,
            stack: .identity,
            thumbnail: thumb
        )
    }

    private static func makeThumbnail(from heic: Data) -> Data? {
        guard let src = CGImageSourceCreateWithData(heic as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 400,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.85)
    }

    /// Default cooker: decodes the raw HEIC, runs it through the export render
    /// pipeline with the slot's stack, and re-encodes as HEIC at q=0.95.
    nonisolated static func defaultCookHEIC(_ rawData: Data, stack: AdjustmentStack, isFront: Bool) async throws -> Data {
        guard let source = CIImage(data: rawData, options: [.applyOrientationProperty: true]) else {
            throw CameraError.captureFailed(nil)
        }
        // Mirror front-cam captures so the saved photo matches the mirrored
        // live preview the user composed against (matches Apple Camera in iOS 14+).
        let oriented: CIImage = isFront
            ? source.transformed(by: CGAffineTransform(scaleX: -1, y: 1)
                .translatedBy(x: -source.extent.width, y: 0))
            : source
        let engine = try RenderEngine()
        let cookedCG = try await engine.renderExport(stack: stack, source: oriented, cubeResolver: nil)

        let props: [CFString: Any] = {
            guard let imgSource = CGImageSourceCreateWithData(rawData as CFData, nil),
                  let p = CGImageSourceCopyPropertiesAtIndex(imgSource, 0, nil) as? [CFString: Any]
            else { return [:] }
            return p
        }()

        return try ExportService.encode(
            cgImage: cookedCG,
            sourceProperties: props,
            colorSpace: cookedCG.colorSpace,
            options: ExportOptions(format: .heic, size: .full, quality: 0.95)
        )
    }

    // MARK: - Carousel thumbnailer

    var thumbnailer: CameraCarouselThumbnailer?

    func attachThumbnailer(renderer: CameraPreviewRenderer) {
        let t = CameraCarouselThumbnailer(renderer: renderer, cubeResolver: cubeResolver)
        t.setSlots(slots)
        thumbnailer = t
        t.start()
    }

    func detachThumbnailer() {
        thumbnailer?.stop()
        thumbnailer = nil
    }

    /// Persist the current preset+intensity combo as a new recipe so the
    /// scaled-down look becomes a one-tap entry. Saves the *effective* stack
    /// (intensity baked in) so the new recipe IS that look at 100%.
    func saveCurrentAsRecipe(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let baked = effectiveStack
        let saved = recipeStore.save(name: trimmed, stack: baked, thumbnail: nil)
        slots = CameraSlot.build(from: recipeStore.items)
        thumbnailer?.setSlots(slots)
        if let newSlot = slots.first(where: {
            if case .recipe(let item) = $0 { return item.id == saved.id }
            return false
        }) {
            selectSlot(newSlot)
        }
    }
}

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import Photos
import SwiftUI
import UIKit

@MainActor
final class PhotoEditorViewModel: ObservableObject {
    enum FilterPreset: String, CaseIterable, Identifiable {
        case original = "Original"
        case noir = "Noir"
        case chrome = "Chrome"
        case fade = "Fade"
        case instant = "Instant"
        case mono = "Mono"
        case process = "Process"
        case tonal = "Tonal"
        case transfer = "Transfer"
        case sepia = "Sepia"

        var id: String { rawValue }

        fileprivate var ciFilterName: String? {
            switch self {
            case .original: return nil
            case .sepia: return "CISepiaTone"
            case .chrome: return "CIPhotoEffectChrome"
            case .fade: return "CIPhotoEffectFade"
            case .instant: return "CIPhotoEffectInstant"
            case .mono: return "CIPhotoEffectMono"
            case .noir: return "CIPhotoEffectNoir"
            case .process: return "CIPhotoEffectProcess"
            case .tonal: return "CIPhotoEffectTonal"
            case .transfer: return "CIPhotoEffectTransfer"
            }
        }
    }

    @Published var sourceImage: UIImage?
    @Published var editedImage: UIImage?
    @Published var selectedFilter: FilterPreset = .original {
        didSet { scheduleRender() }
    }
    @Published var brightness: Double = 0 {
        didSet { scheduleRender() }
    }
    @Published var contrast: Double = 1 {
        didSet { scheduleRender() }
    }
    @Published var saturation: Double = 1 {
        didSet { scheduleRender() }
    }
    @Published var rotationAngle: Double = 0 {
        didSet { scheduleRender() }
    }
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let context = CIContext()
    private var sourceCIImage: CIImage?
    private var renderTask: Task<Void, Never>?
    private static let maxPixelDimension: CGFloat = 2048

    private struct UncheckedSendable<T>: @unchecked Sendable {
        let value: T
    }

    func loadImage(_ image: UIImage) {
        let downsampled = downsample(image: image, maxDimension: Self.maxPixelDimension)
        sourceImage = downsampled
        sourceCIImage = downsampled.flatMap { CIImage(image: $0) }
        resetAdjustments(clearImage: false)
    }

    func resetAdjustments(clearImage: Bool = false) {
        brightness = 0
        contrast = 1
        saturation = 1
        rotationAngle = 0
        selectedFilter = .original
        errorMessage = nil
        successMessage = nil

        if clearImage {
            sourceImage = nil
            sourceCIImage = nil
            editedImage = nil
            renderTask?.cancel()
            return
        }

        scheduleRender()
    }

    func rotateLeft() {
        rotationAngle = normalizeAngle(rotationAngle - 90)
    }

    func rotateRight() {
        rotationAngle = normalizeAngle(rotationAngle + 90)
    }

    func saveImage() async {
        guard let sourceImage else {
            errorMessage = "Choose a photo before saving."
            return
        }

        isSaving = true
        errorMessage = nil
        successMessage = nil

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            isSaving = false
            errorMessage = "Photo Library access is required to save edits."
            return
        }

        let imageToSave = await renderCurrent() ?? sourceImage

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: imageToSave)
            }
            successMessage = "Saved to Photos."
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }

    private func renderCurrent() async -> UIImage? {
        guard let inputCIImage = sourceCIImage, let sourceImage else { return nil }
        renderTask?.cancel()
        let input = UncheckedSendable(value: inputCIImage)
        let ctx = UncheckedSendable(value: context)
        let filter = selectedFilter
        let brightness = self.brightness
        let contrast = self.contrast
        let saturation = self.saturation
        let rotationAngle = self.rotationAngle
        let scale = sourceImage.scale

        let result = await Task.detached(priority: .userInitiated) {
            Self.render(
                input: input.value,
                filter: filter,
                brightness: brightness,
                contrast: contrast,
                saturation: saturation,
                rotationAngle: rotationAngle,
                context: ctx.value,
                scale: scale
            )
        }.value

        if let result { editedImage = result }
        return result
    }

    private func scheduleRender() {
        renderTask?.cancel()
        guard let inputCIImage = sourceCIImage, let sourceImage else {
            editedImage = nil
            return
        }

        if selectedFilter == .original
            && brightness == 0
            && contrast == 1
            && saturation == 1
            && rotationAngle.truncatingRemainder(dividingBy: 360) == 0 {
            editedImage = nil
            return
        }

        let input = UncheckedSendable(value: inputCIImage)
        let ctx = UncheckedSendable(value: context)
        let filter = selectedFilter
        let brightness = self.brightness
        let contrast = self.contrast
        let saturation = self.saturation
        let rotationAngle = self.rotationAngle
        let scale = sourceImage.scale

        renderTask = Task.detached(priority: .userInitiated) { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000)
            if Task.isCancelled { return }

            let rendered = Self.render(
                input: input.value,
                filter: filter,
                brightness: brightness,
                contrast: contrast,
                saturation: saturation,
                rotationAngle: rotationAngle,
                context: ctx.value,
                scale: scale
            )

            if Task.isCancelled { return }
            await MainActor.run {
                guard let self else { return }
                if let rendered { self.editedImage = rendered }
            }
        }
    }

    private static func render(
        input: CIImage,
        filter: FilterPreset,
        brightness: Double,
        contrast: Double,
        saturation: Double,
        rotationAngle: Double,
        context: CIContext,
        scale: CGFloat
    ) -> UIImage? {
        var output = input

        if let name = filter.ciFilterName, let preset = CIFilter(name: name) {
            preset.setValue(output, forKey: kCIInputImageKey)
            if filter == .sepia {
                preset.setValue(0.9, forKey: kCIInputIntensityKey)
            }
            if let result = preset.outputImage {
                output = result
            }
        }

        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = output
        colorControls.brightness = Float(brightness)
        colorControls.contrast = Float(contrast)
        colorControls.saturation = Float(saturation)
        if let result = colorControls.outputImage {
            output = result
        }

        if rotationAngle.truncatingRemainder(dividingBy: 360) != 0 {
            let radians = CGFloat(rotationAngle * .pi / 180)
            let extent = output.extent.integral
            let center = CGPoint(x: extent.midX, y: extent.midY)
            let centered = output.transformed(by: CGAffineTransform(translationX: -center.x, y: -center.y))
            let rotated = centered.transformed(by: CGAffineTransform(rotationAngle: radians))
            let rotatedExtent = rotated.extent.integral
            output = rotated.transformed(by: CGAffineTransform(translationX: -rotatedExtent.origin.x, y: -rotatedExtent.origin.y))
        }

        guard let cgImage = context.createCGImage(output, from: output.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    private func normalizeAngle(_ angle: Double) -> Double {
        let remainder = angle.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }

    private func downsample(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        let needsResize = longest > maxDimension
        let needsOrientationFix = image.imageOrientation != .up

        if !needsResize && !needsOrientationFix {
            return image
        }

        let targetSize: CGSize
        if needsResize {
            let scale = maxDimension / longest
            targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        } else {
            targetSize = size
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

}

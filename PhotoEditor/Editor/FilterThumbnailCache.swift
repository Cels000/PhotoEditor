import CoreImage
import Foundation
import UIKit

/// NSCache-backed thumbnail cache keyed by "<photoID>#<filterID>".
/// `photoID` should be a stable identity for the source image (we use
/// the imported source CIImage's ObjectIdentifier-derived hash; importing
/// a new photo changes this and effectively invalidates all thumbnails).
final class FilterThumbnailCache {

    static let thumbnailSide: CGFloat = 200

    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 64
        return c
    }()

    func image(forPhotoID photoID: String, filterID: String) -> UIImage? {
        cache.object(forKey: NSString(string: "\(photoID)#\(filterID)"))
    }

    func setImage(_ image: UIImage, forPhotoID photoID: String, filterID: String) {
        cache.setObject(image, forKey: NSString(string: "\(photoID)#\(filterID)"))
    }

    func clear() {
        cache.removeAllObjects()
    }

    /// Render a thumbnail by applying the supplied cube to the given preview source.
    /// Caller passes a small (e.g. 200px) downsampled CIImage to keep render fast.
    /// Returns nil on render failure.
    static func renderThumbnail(source: CIImage,
                                cube: ColorCubeData?,
                                strength: Double = 1.0,
                                context: CIContext) -> UIImage? {
        var output = source
        if let cube = cube, strength > 0 {
            let cubeFilter = CIFilter(name: "CIColorCubeWithColorSpace")
            cubeFilter?.setValue(source, forKey: kCIInputImageKey)
            cubeFilter?.setValue(Float(ColorCubeData.dimension), forKey: "inputCubeDimension")
            cubeFilter?.setValue(cube.rawData, forKey: "inputCubeData")
            cubeFilter?.setValue(CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!, forKey: "inputColorSpace")
            if let result = cubeFilter?.outputImage { output = result }
        }
        guard let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

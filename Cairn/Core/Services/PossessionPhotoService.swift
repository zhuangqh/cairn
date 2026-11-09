import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Turns a user-picked photo into showcase artwork entirely on device:
/// the image is oriented and downscaled, then Vision's foreground-instance
/// mask lifts the subject onto a transparent background. Nothing leaves the
/// device.
///
/// Not main-actor isolated: callers `await` it from the UI so decoding and
/// segmentation run off the main thread. Only `Data` crosses the boundary.
public enum PossessionPhotoService {
    /// Longest edge, in pixels, of every stored photo.
    public static let maxPixelSize = 1024

    public struct Prepared: Sendable, Equatable {
        /// Oriented, downscaled original encoded as JPEG.
        public let original: Data
        /// Transparent PNG of the detected subject cropped to its extent, or
        /// `nil` when Vision found no foreground subject (or can't run, as
        /// on some simulators).
        public let cutout: Data?
    }

    public enum PhotoError: Error, Equatable {
        /// The data isn't an image ImageIO can decode.
        case unreadableImage
    }

    public static func prepare(_ data: Data) async throws -> Prepared {
        let image = try downscaledImage(from: data)
        guard let original = encode(image, as: .jpeg) else { throw PhotoError.unreadableImage }
        return Prepared(original: original, cutout: subjectCutout(of: image))
    }

    /// Decodes `data` with EXIF orientation applied and the longest edge
    /// capped at `maxPixelSize` (smaller images are not upscaled).
    static func downscaledImage(from data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw PhotoError.unreadableImage
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PhotoError.unreadableImage
        }
        return image
    }

    private static func subjectCutout(of image: CGImage) -> Data? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        do {
            try handler.perform([request])
            guard let observation = request.results?.first,
                  !observation.allInstances.isEmpty else { return nil }
            let buffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
            let ciImage = CIImage(cvPixelBuffer: buffer)
            guard let masked = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return nil }
            return encode(masked, as: .png)
        } catch {
            return nil
        }
    }

    private static func encode(_ image: CGImage, as type: UTType) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, type.identifier as CFString, 1, nil
        ) else { return nil }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

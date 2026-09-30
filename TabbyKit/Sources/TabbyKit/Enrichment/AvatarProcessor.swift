import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Avatars are stored as small JPEGs so the share extension stays well under its memory
/// limit and the database stays small.
public enum AvatarProcessor {
    public static let maxPixelSize = 400

    /// Decodes straight to at most `maxPixelSize` on the long edge (never the full image) and
    /// re-encodes as JPEG. Nil when the data isn't an image.
    public static func downscaledJPEG(_ data: Data, maxPixelSize: Int = maxPixelSize, quality: Double = 0.82) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    public static func download(_ url: URL, client: any HTTPClient) async -> Data? {
        guard let response = try? await client.get(url), (200..<300).contains(response.statusCode) else { return nil }
        return downscaledJPEG(response.body)
    }
}

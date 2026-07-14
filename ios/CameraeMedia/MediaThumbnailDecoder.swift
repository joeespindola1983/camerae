import AVFoundation
import Foundation
import UIKit

public struct AVAssetThumbnailDecoder: ThumbnailDecoding {
    public init() {}

    public func decode(url: URL, maxPixelSize: Int) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: max(maxPixelSize, 1), height: max(maxPixelSize, 1))
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        return await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(
                for: CMTime(seconds: 0.05, preferredTimescale: 600)
            ) { image, _, _ in
                continuation.resume(returning: image.map(UIImage.init(cgImage:)))
            }
        }
    }
}

public struct MediaThumbnailDecoder: ThumbnailDecoding {
    private let imageDecoder: any ThumbnailDecoding
    private let videoDecoder: any ThumbnailDecoding

    public init(
        imageDecoder: any ThumbnailDecoding = ImageIOThumbnailDecoder(),
        videoDecoder: any ThumbnailDecoding = AVAssetThumbnailDecoder()
    ) {
        self.imageDecoder = imageDecoder
        self.videoDecoder = videoDecoder
    }

    public func decode(url: URL, maxPixelSize: Int) async -> UIImage? {
        switch url.pathExtension.lowercased() {
        case "mp4", "mov", "m4v":
            return await videoDecoder.decode(url: url, maxPixelSize: maxPixelSize)
        default:
            return await imageDecoder.decode(url: url, maxPixelSize: maxPixelSize)
        }
    }
}

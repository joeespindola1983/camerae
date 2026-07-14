import AVFoundation
import CameraeCore
import CoreGraphics
import Foundation

public struct MediaAssetTechnicalMetadata: Equatable, Sendable {
    public let duration: TimeInterval
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let hasAudio: Bool
    public let fileSize: UInt64

    public init(
        duration: TimeInterval,
        pixelWidth: Int,
        pixelHeight: Int,
        hasAudio: Bool,
        fileSize: UInt64
    ) {
        self.duration = duration
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.hasAudio = hasAudio
        self.fileSize = fileSize
    }
}

public protocol MediaAssetProbing: Sendable {
    func probe(url: URL) async throws -> MediaAssetTechnicalMetadata
}

public struct MediaAssetProbe: MediaAssetProbing {
    public init() {}

    public func probe(url: URL) async throws -> MediaAssetTechnicalMetadata {
        guard let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, fileSize > 0 else {
            throw MediaAssetProbeError.emptyFile
        }

        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw MediaAssetProbeError.missingVideoTrack
        }
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else {
            throw MediaAssetProbeError.invalidDuration
        }
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let oriented = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let width = Int(abs(oriented.width).rounded())
        let height = Int(abs(oriented.height).rounded())
        guard width > 0, height > 0 else {
            throw MediaAssetProbeError.invalidDimensions
        }
        let hasAudio = try await !asset.loadTracks(withMediaType: .audio).isEmpty

        return MediaAssetTechnicalMetadata(
            duration: seconds,
            pixelWidth: width,
            pixelHeight: height,
            hasAudio: hasAudio,
            fileSize: UInt64(fileSize)
        )
    }
}

public enum MediaAssetProbeError: Error, Equatable {
    case emptyFile
    case missingVideoTrack
    case invalidDuration
    case invalidDimensions
}

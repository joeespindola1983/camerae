import CameraeCore
import Foundation

public struct EditCompositionSegment: Equatable, Sendable {
    public let itemID: UUID
    public let assetID: MediaAssetID
    public let startTime: TimeInterval
    public let duration: TimeInterval
    public let sourcePixelWidth: Int
    public let sourcePixelHeight: Int
    public let sourceFrameRate: Double?
    public let sourceVideoCodec: String?
    public let sourceVideoBitRate: Double?
    public let spatialTransform: ClipAlignmentTransform

    public init(
        itemID: UUID,
        assetID: MediaAssetID,
        startTime: TimeInterval,
        duration: TimeInterval,
        sourcePixelWidth: Int,
        sourcePixelHeight: Int,
        sourceFrameRate: Double? = nil,
        sourceVideoCodec: String? = nil,
        sourceVideoBitRate: Double? = nil,
        spatialTransform: ClipAlignmentTransform = .identity
    ) {
        self.itemID = itemID
        self.assetID = assetID
        self.startTime = startTime
        self.duration = duration
        self.sourcePixelWidth = sourcePixelWidth
        self.sourcePixelHeight = sourcePixelHeight
        self.sourceFrameRate = sourceFrameRate
        self.sourceVideoCodec = sourceVideoCodec
        self.sourceVideoBitRate = sourceVideoBitRate
        self.spatialTransform = spatialTransform
    }
}

public struct EditCompositionPlan: Equatable, Sendable {
    public let canvas: EditCanvas
    public let renderWidth: Int
    public let renderHeight: Int
    public let frameRate: Int
    public let videoCodec: String
    public let videoBitRate: Int
    public let segments: [EditCompositionSegment]
    public let totalDuration: TimeInterval
    public let commonCrop: ClipAlignmentNormalizedRect

    public init(
        canvas: EditCanvas,
        renderWidth: Int,
        renderHeight: Int,
        frameRate: Int,
        videoCodec: String = "h264",
        videoBitRate: Int = 0,
        segments: [EditCompositionSegment],
        totalDuration: TimeInterval,
        commonCrop: ClipAlignmentNormalizedRect = .full
    ) {
        self.canvas = canvas
        self.renderWidth = renderWidth
        self.renderHeight = renderHeight
        self.frameRate = frameRate
        self.videoCodec = videoCodec
        self.videoBitRate = videoBitRate
        self.segments = segments
        self.totalDuration = totalDuration
        self.commonCrop = commonCrop
    }
}

public struct EditCompositionPlanner: Sendable {
    public init() {}

    public func makePlan(
        document: EditProjectDocument,
        assets: [MediaAssetID: ResolvedMediaAsset],
        spatialAlignment: EditSpatialAlignmentPlan? = nil
    ) throws -> EditCompositionPlan {
        guard !document.items.isEmpty else { throw EditCompositionError.emptyTimeline }
        if let spatialAlignment {
            guard spatialAlignment.decision == .apply else {
                throw EditCompositionError.spatialAlignmentNotApplicable
            }
            let timelineIDs = Set(document.items.map(\.id))
            guard timelineIDs == Set(spatialAlignment.corrections.keys),
                  timelineIDs.contains(spatialAlignment.referenceItemID) else {
                throw EditCompositionError.spatialAlignmentDoesNotMatchTimeline
            }
        }
        var segments: [EditCompositionSegment] = []
        var cursor: TimeInterval = 0

        for item in document.items {
            guard let asset = assets[item.asset.id], asset.descriptor.isAvailable else {
                throw EditCompositionError.missingMedia(item.asset.id)
            }
            let descriptor = asset.descriptor
            guard descriptor.duration.isFinite, descriptor.duration > 0 else {
                throw EditCompositionError.invalidDuration(item.asset.id)
            }
            guard descriptor.pixelWidth > 0, descriptor.pixelHeight > 0 else {
                throw EditCompositionError.invalidDimensions(item.asset.id)
            }
            segments.append(EditCompositionSegment(
                itemID: item.id,
                assetID: item.asset.id,
                startTime: cursor,
                duration: descriptor.duration,
                sourcePixelWidth: descriptor.pixelWidth,
                sourcePixelHeight: descriptor.pixelHeight,
                sourceFrameRate: descriptor.frameRate,
                sourceVideoCodec: descriptor.videoCodec,
                sourceVideoBitRate: descriptor.videoBitRate,
                spatialTransform: spatialAlignment?.corrections[item.id]?.transform ?? .identity
            ))
            cursor += descriptor.duration
        }

        let size = EditRenderSizePolicy.renderSize(
            canvas: document.canvas,
            sourceSizes: segments.map {
                (width: $0.sourcePixelWidth, height: $0.sourcePixelHeight)
            }
        )
        let frameRate = EditFrameRatePolicy.frameRate(
            sourceFrameRates: segments.compactMap(\.sourceFrameRate)
        )
        let videoCodec = EditVideoCodecPolicy.codec(
            sourceCodecs: segments.compactMap(\.sourceVideoCodec)
        )
        let sourceBitRate = segments
            .compactMap(\.sourceVideoBitRate)
            .filter { $0.isFinite && $0 > 0 }
            .max()
            .map { Int($0.rounded()) } ?? 0
        return EditCompositionPlan(
            canvas: document.canvas,
            renderWidth: size.width,
            renderHeight: size.height,
            frameRate: frameRate,
            videoCodec: videoCodec,
            videoBitRate: sourceBitRate,
            segments: segments,
            totalDuration: cursor,
            commonCrop: spatialAlignment?.commonCrop ?? .full
        )
    }
}

enum EditFrameRatePolicy {
    static func frameRate(sourceFrameRates: [Double]) -> Int {
        let valid = sourceFrameRates.filter { $0.isFinite && $0 > 0 }
        return min(max(Int((valid.min() ?? 30).rounded()), 1), 120)
    }
}

enum EditVideoCodecPolicy {
    static func codec(sourceCodecs: [String]) -> String {
        guard !sourceCodecs.isEmpty,
              sourceCodecs.allSatisfy({ $0.caseInsensitiveCompare("hevc") == .orderedSame }) else {
            return "h264"
        }
        return "hevc"
    }
}

enum EditRenderSizePolicy {
    static func renderSize(
        canvas: EditCanvas,
        sourceSizes: [(width: Int, height: Int)]
    ) -> (width: Int, height: Int) {
        let normalized = sourceSizes.map {
            (short: min($0.width, $0.height), long: max($0.width, $0.height))
        }
        let availableShort = normalized.map(\.short).min() ?? 2
        let availableLong = normalized.map(\.long).min() ?? 2
        let standardPortraitSizes = [
            (width: 2160, height: 3840),
            (width: 1080, height: 1920),
            (width: 720, height: 1280),
            (width: 540, height: 960),
            (width: 360, height: 640)
        ]
        let portrait = standardPortraitSizes.first {
            $0.width <= availableShort && $0.height <= availableLong
        } ?? fittedPortraitSize(availableShort: availableShort, availableLong: availableLong)
        return canvas == .portrait9x16
            ? portrait
            : (width: portrait.height, height: portrait.width)
    }

    private static func fittedPortraitSize(
        availableShort: Int,
        availableLong: Int
    ) -> (width: Int, height: Int) {
        let width = min(availableShort, Int(Double(availableLong) * 9 / 16))
        let height = min(availableLong, Int(Double(width) * 16 / 9))
        return (width: even(width), height: even(height))
    }

    private static func even(_ value: Int) -> Int {
        max(2, value - value % 2)
    }
}

public enum EditCompositionError: Error, Equatable {
    case emptyTimeline
    case missingMedia(MediaAssetID)
    case invalidDuration(MediaAssetID)
    case invalidDimensions(MediaAssetID)
    case spatialAlignmentNotApplicable
    case spatialAlignmentDoesNotMatchTimeline
}

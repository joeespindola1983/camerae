import CameraeCore
import Foundation

public struct EditCompositionSegment: Equatable, Sendable {
    public let itemID: UUID
    public let assetID: MediaAssetID
    public let startTime: TimeInterval
    public let duration: TimeInterval
    public let sourcePixelWidth: Int
    public let sourcePixelHeight: Int
    public let spatialTransform: ClipAlignmentTransform

    public init(
        itemID: UUID,
        assetID: MediaAssetID,
        startTime: TimeInterval,
        duration: TimeInterval,
        sourcePixelWidth: Int,
        sourcePixelHeight: Int,
        spatialTransform: ClipAlignmentTransform = .identity
    ) {
        self.itemID = itemID
        self.assetID = assetID
        self.startTime = startTime
        self.duration = duration
        self.sourcePixelWidth = sourcePixelWidth
        self.sourcePixelHeight = sourcePixelHeight
        self.spatialTransform = spatialTransform
    }
}

public struct EditCompositionPlan: Equatable, Sendable {
    public let canvas: EditCanvas
    public let renderWidth: Int
    public let renderHeight: Int
    public let frameRate: Int
    public let segments: [EditCompositionSegment]
    public let totalDuration: TimeInterval
    public let commonCrop: ClipAlignmentNormalizedRect

    public init(
        canvas: EditCanvas,
        renderWidth: Int,
        renderHeight: Int,
        frameRate: Int,
        segments: [EditCompositionSegment],
        totalDuration: TimeInterval,
        commonCrop: ClipAlignmentNormalizedRect = .full
    ) {
        self.canvas = canvas
        self.renderWidth = renderWidth
        self.renderHeight = renderHeight
        self.frameRate = frameRate
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
                spatialTransform: spatialAlignment?.corrections[item.id]?.transform ?? .identity
            ))
            cursor += descriptor.duration
        }

        let size = document.canvas == .portrait9x16 ? (1080, 1920) : (1920, 1080)
        return EditCompositionPlan(
            canvas: document.canvas,
            renderWidth: size.0,
            renderHeight: size.1,
            frameRate: 30,
            segments: segments,
            totalDuration: cursor,
            commonCrop: spatialAlignment?.commonCrop ?? .full
        )
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

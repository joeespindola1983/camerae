import AVFoundation
import CameraeCore
import CameraeMedia
import CoreVideo
import Foundation

actor AVAssetVideoClipAlignmentFrameExtractor: VideoClipAlignmentFrameExtracting {
    func frames(
        for source: VideoClipAlignmentSource,
        fractions: [Double]
    ) async throws -> [VideoClipAlignmentFrame] {
        let asset = AVURLAsset(url: source.url)
        guard try await !asset.loadTracks(withMediaType: .video).isEmpty else {
            throw VideoClipAlignmentAdapterError.missingVideoTrack(source.itemID)
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)

        var output: [VideoClipAlignmentFrame] = []
        output.reserveCapacity(fractions.count)
        for fraction in fractions {
            try Task.checkCancellation()
            guard fraction.isFinite, (0...1).contains(fraction) else {
                throw VideoClipAlignmentAdapterError.invalidSampleFraction
            }
            let time = CMTime(
                seconds: source.duration * fraction,
                preferredTimescale: 600
            )
            let image = try await generator.image(at: time).image
            let buffer = try CameraeVisionPixelBufferFactory.makeBGRA(from: image)
            output.append(VideoClipAlignmentFrame(pixelBuffer: buffer))
        }
        return output
    }
}

actor OpenCVVideoClipAlignmentPairEvaluator: VideoClipAlignmentPairEvaluating {
    func evaluate(
        reference: VideoClipAlignmentFrame,
        moving: VideoClipAlignmentFrame
    ) async throws -> VideoClipAlignmentMeasurement {
        let result = try CameraeVisionClipAlignmentEstimator.estimate(
            reference: reference.pixelBuffer,
            referenceOrientation: .up,
            moving: moving.pixelBuffer,
            movingOrientation: .up
        )
        guard result.schemaVersion == 1,
              result.transform3x3.count == 9,
              result.validRegion.count == 4 else {
            throw VideoClipAlignmentAdapterError.unsupportedResultSchema
        }

        let matrix = result.transform3x3.map(\.doubleValue)
        guard abs(matrix[6]) < 0.000_001,
              abs(matrix[7]) < 0.000_001,
              abs(matrix[8] - 1) < 0.000_001 else {
            throw VideoClipAlignmentAdapterError.perspectiveTransformNotSupported
        }
        let model: ClipAlignmentMotionModel
        switch result.selectedModel {
        case "translation": model = .translation
        case "similarity": model = .similarity
        case "affine": model = .affine
        case "homography": model = .perspective
        default: throw VideoClipAlignmentAdapterError.unknownMotionModel(result.selectedModel)
        }

        let decision: ClipAlignmentDecision
        switch result.decision {
        case .accept: decision = .apply
        case .review: decision = .review
        case .reject, .unavailable: decision = .reject
        @unknown default: decision = .reject
        }
        return VideoClipAlignmentMeasurement(
            model: model,
            transform: .init(
                a: matrix[0],
                b: matrix[3],
                c: matrix[1],
                d: matrix[4],
                tx: matrix[2],
                ty: matrix[5]
            ),
            validRegion: .init(
                x: result.validRegion[0].doubleValue,
                y: result.validRegion[1].doubleValue,
                width: result.validRegion[2].doubleValue,
                height: result.validRegion[3].doubleValue
            ),
            quality: .init(
                decision: decision,
                score: result.score,
                reasonCodes: result.reasonCodes
            )
        )
    }
}

extension VideoClipAlignmentAnalyzer {
    static func live() -> VideoClipAlignmentAnalyzer {
        VideoClipAlignmentAnalyzer(
            extractor: AVAssetVideoClipAlignmentFrameExtractor(),
            evaluator: OpenCVVideoClipAlignmentPairEvaluator()
        )
    }

    func analyze(
        document: EditProjectDocument,
        assets: [MediaAssetID: ResolvedMediaAsset]
    ) async throws -> EditSpatialAlignmentPlan {
        let sources = try document.items.map { item in
            guard let asset = assets[item.asset.id], asset.descriptor.isAvailable else {
                throw EditCompositionError.missingMedia(item.asset.id)
            }
            return VideoClipAlignmentSource(
                itemID: item.id,
                url: asset.url,
                duration: asset.descriptor.duration,
                fingerprint: assetFingerprint(asset)
            )
        }
        return try await analyze(sources: sources)
    }

    private func assetFingerprint(_ asset: ResolvedMediaAsset) -> String {
        let values = try? asset.url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return [
            asset.url.standardizedFileURL.path,
            String(asset.descriptor.duration),
            String(asset.descriptor.fileSize),
            String(values?.fileSize ?? -1),
            String(values?.contentModificationDate?.timeIntervalSince1970 ?? -1)
        ].joined(separator: "|")
    }
}

enum VideoClipAlignmentAdapterError: Error, Equatable {
    case missingVideoTrack(UUID)
    case invalidSampleFraction
    case unsupportedResultSchema
    case perspectiveTransformNotSupported
    case unknownMotionModel(String)
}

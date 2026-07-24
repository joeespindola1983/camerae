import AVFoundation
import CameraeCore
import CoreGraphics
import Foundation
import OSLog

public protocol EditVideoComposing: Sendable {
    func export(
        project: EditProjectDocument,
        assets: [MediaAssetID: ResolvedMediaAsset],
        outputURL: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL

    func export(
        project: EditProjectDocument,
        assets: [MediaAssetID: ResolvedMediaAsset],
        spatialAlignment: EditSpatialAlignmentPlan?,
        outputURL: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL

    func cancel() async
}

public extension EditVideoComposing {
    func export(
        project: EditProjectDocument,
        assets: [MediaAssetID: ResolvedMediaAsset],
        spatialAlignment: EditSpatialAlignmentPlan?,
        outputURL: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL {
        guard spatialAlignment == nil else {
            throw EditVideoComposerError.spatialAlignmentUnsupported
        }
        return try await export(
            project: project,
            assets: assets,
            outputURL: outputURL,
            progress: progress
        )
    }
}

public actor EditVideoComposer: EditVideoComposing {
    private let planner: EditCompositionPlanner
    private let fileManager: FileManager
    private var exportSession: AVAssetExportSession?

    public init(
        planner: EditCompositionPlanner = EditCompositionPlanner(),
        fileManager: FileManager = .default
    ) {
        self.planner = planner
        self.fileManager = fileManager
    }

    public func export(
        project: EditProjectDocument,
        assets: [MediaAssetID: ResolvedMediaAsset],
        outputURL: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL {
        try await export(
            project: project,
            assets: assets,
            spatialAlignment: nil,
            outputURL: outputURL,
            progress: progress
        )
    }

    public func export(
        project: EditProjectDocument,
        assets: [MediaAssetID: ResolvedMediaAsset],
        spatialAlignment: EditSpatialAlignmentPlan?,
        outputURL: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL {
        guard exportSession == nil else { throw EditVideoComposerError.exportAlreadyRunning }
        EditVideoComposerDiagnostics.event("export.plan.started")
        let plan = try planner.makePlan(
            document: project,
            assets: assets,
            spatialAlignment: spatialAlignment
        )
        EditVideoComposerDiagnostics.event(
            "export.plan.completed",
            "canvas=\(plan.canvas.rawValue) render=\(plan.renderWidth)x\(plan.renderHeight) fps=\(plan.frameRate) segments=\(plan.segments.count) duration=\(plan.totalDuration) crop=\(1 - plan.commonCrop.area)"
        )
        let built = try await buildComposition(plan: plan, assets: assets)
        EditVideoComposerDiagnostics.event("export.composition.completed")
        try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporaryURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).tmp.mp4")
        try? fileManager.removeItem(at: temporaryURL)
        var shouldRemoveTemporary = true
        defer {
            exportSession = nil
            if shouldRemoveTemporary {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        guard let exporter = AVAssetExportSession(
            asset: built.composition,
            presetName: AVAssetExportPreset1920x1080
        ) else {
            EditVideoComposerDiagnostics.event("export.session.unavailable")
            throw EditVideoComposerError.exporterUnavailable
        }
        guard exporter.supportedFileTypes.contains(.mp4) else {
            EditVideoComposerDiagnostics.event(
                "export.mp4.unsupported",
                "supported=\(exporter.supportedFileTypes.map(\.rawValue).joined(separator: ","))"
            )
            throw EditVideoComposerError.mp4Unsupported
        }
        exporter.outputURL = temporaryURL
        exporter.outputFileType = .mp4
        exporter.videoComposition = built.videoComposition
        exporter.shouldOptimizeForNetworkUse = true
        exportSession = exporter

        EditVideoComposerDiagnostics.event(
            "export.session.started",
            "preset=\(AVAssetExportPreset1920x1080) fileType=\(AVFileType.mp4.rawValue)"
        )
        await progress(0)
        let progressTask = Task {
            while !Task.isCancelled {
                await progress(Double(exporter.progress))
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        await withCheckedContinuation { continuation in
            exporter.exportAsynchronously {
                continuation.resume()
            }
        }
        progressTask.cancel()
        EditVideoComposerDiagnostics.event(
            "export.session.finished",
            "status=\(exporter.status.rawValue) \(EditVideoComposerDiagnostics.describe(exporter.error))"
        )

        switch exporter.status {
        case .completed:
            break
        case .cancelled:
            throw EditVideoComposerError.cancelled
        case .failed:
            throw exporter.error ?? EditVideoComposerError.exportFailed
        default:
            throw EditVideoComposerError.exportFailed
        }

        EditVideoComposerDiagnostics.event("export.validation.started")
        try await validateExport(at: temporaryURL)
        EditVideoComposerDiagnostics.event("export.validation.completed")
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: outputURL)
        EditVideoComposerDiagnostics.event("export.publication.completed")
        shouldRemoveTemporary = false
        await progress(1)
        return outputURL
    }

    public func cancel() {
        exportSession?.cancelExport()
    }

    private func buildComposition(
        plan: EditCompositionPlan,
        assets: [MediaAssetID: ResolvedMediaAsset]
    ) async throws -> (composition: AVMutableComposition, videoComposition: AVMutableVideoComposition) {
        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw EditVideoComposerError.compositionTrackUnavailable
        }
        let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        var instructions: [AVMutableVideoCompositionInstruction] = []
        var compositionCursor = CMTime.zero

        for segment in plan.segments {
            try Task.checkCancellation()
            guard let resolved = assets[segment.assetID] else {
                throw EditCompositionError.missingMedia(segment.assetID)
            }
            let sourceAsset = AVURLAsset(url: resolved.url)
            guard let sourceVideoTrack = try await sourceAsset.loadTracks(withMediaType: .video).first else {
                throw EditVideoComposerError.missingVideoTrack(segment.assetID)
            }
            let sourceDuration = try await sourceAsset.load(.duration)
            let plannedDuration = CMTime(seconds: segment.duration, preferredTimescale: 600)
            let duration = CMTimeMinimum(sourceDuration, plannedDuration)
            guard duration.isNumeric, duration > .zero else {
                throw EditCompositionError.invalidDuration(segment.assetID)
            }
            // Use the media track's exact duration as the composition cursor. Probe
            // metadata is expressed as Double and can otherwise introduce tiny gaps
            // that AVAssetExportSession rejects between adjacent instructions.
            let start = compositionCursor
            let range = CMTimeRange(start: .zero, duration: duration)
            try compositionVideoTrack.insertTimeRange(range, of: sourceVideoTrack, at: start)

            if let sourceAudioTrack = try await sourceAsset.loadTracks(withMediaType: .audio).first,
               let compositionAudioTrack {
                try compositionAudioTrack.insertTimeRange(range, of: sourceAudioTrack, at: start)
            }

            let naturalSize = try await sourceVideoTrack.load(.naturalSize)
            let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: start, duration: duration)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
            layer.setTransform(
                EditVideoTransformResolver.layerTransform(
                    naturalSize: naturalSize,
                    preferredTransform: preferredTransform,
                    renderSize: CGSize(width: plan.renderWidth, height: plan.renderHeight),
                    spatialTransform: segment.spatialTransform,
                    commonCrop: plan.commonCrop
                ),
                at: start
            )
            instruction.layerInstructions = [layer]
            instructions.append(instruction)
            compositionCursor = CMTimeAdd(compositionCursor, duration)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: plan.renderWidth, height: plan.renderHeight)
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(plan.frameRate))
        videoComposition.instructions = instructions
        return (composition, videoComposition)
    }

    private func validateExport(at url: URL) async throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) > 0 else { throw EditVideoComposerError.emptyOutput }
        let asset = AVURLAsset(url: url)
        guard try await !asset.loadTracks(withMediaType: .video).isEmpty else {
            throw EditVideoComposerError.emptyOutput
        }
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        guard duration.isFinite, duration > 0 else { throw EditVideoComposerError.emptyOutput }
    }
}

enum EditVideoComposerDiagnostics {
    private static let logger = Logger(
        subsystem: "com.espindola.camerae",
        category: "CameraeAlignment"
    )

    nonisolated static func event(_ stage: String, _ detail: String = "") {
        let suffix = detail.isEmpty ? "" : " | \(detail)"
        logger.notice("[CameraeAlignment] \(stage, privacy: .public)\(suffix, privacy: .public)")
    }

    nonisolated static func describe(_ error: Error?) -> String {
        guard let error else { return "error=none" }
        let nsError = error as NSError
        var parts = [
            "domain=\(nsError.domain)",
            "code=\(nsError.code)",
            "message=\(nsError.localizedDescription)"
        ]
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlyingDomain=\(underlying.domain)")
            parts.append("underlyingCode=\(underlying.code)")
            parts.append("underlyingMessage=\(underlying.localizedDescription)")
        }
        return parts.joined(separator: " ")
    }
}

public enum EditVideoTransformResolver {
    public static func layerTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        renderSize: CGSize,
        spatialTransform: ClipAlignmentTransform,
        commonCrop: ClipAlignmentNormalizedRect
    ) -> CGAffineTransform {
        let baseline = aspectFitTransform(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform,
            renderSize: renderSize
        )
        let correction = CGAffineTransform(
            a: spatialTransform.a,
            b: spatialTransform.b,
            c: spatialTransform.c,
            d: spatialTransform.d,
            tx: spatialTransform.tx * renderSize.width,
            ty: spatialTransform.ty * renderSize.height
        )
        let cropScale = 1 / min(commonCrop.width, commonCrop.height)
        let crop = CGAffineTransform(
            a: cropScale,
            b: 0,
            c: 0,
            d: cropScale,
            tx: -commonCrop.x * renderSize.width * cropScale,
            ty: -commonCrop.y * renderSize.height * cropScale
        )
        return baseline.concatenating(correction).concatenating(crop)
    }

    public static func aspectFitTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let sourceRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let orientedWidth = abs(sourceRect.width)
        let orientedHeight = abs(sourceRect.height)
        guard orientedWidth > 0, orientedHeight > 0 else { return preferredTransform }
        let scale = min(renderSize.width / orientedWidth, renderSize.height / orientedHeight)
        let x = (renderSize.width - orientedWidth * scale) / 2
        let y = (renderSize.height - orientedHeight * scale) / 2

        var transform = preferredTransform
        transform = transform.concatenating(CGAffineTransform(
            translationX: -sourceRect.minX,
            y: -sourceRect.minY
        ))
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        transform = transform.concatenating(CGAffineTransform(translationX: x, y: y))
        return transform
    }
}

public enum EditVideoComposerError: LocalizedError, Equatable {
    case exportAlreadyRunning
    case exporterUnavailable
    case mp4Unsupported
    case compositionTrackUnavailable
    case missingVideoTrack(MediaAssetID)
    case exportFailed
    case cancelled
    case emptyOutput
    case spatialAlignmentUnsupported

    public var errorDescription: String? {
        switch self {
        case .exportAlreadyRunning: return "uma exportação já está em andamento"
        case .exporterUnavailable: return "não foi possível criar o exportador de vídeo"
        case .mp4Unsupported: return "este dispositivo não suporta a exportação MP4 solicitada"
        case .compositionTrackUnavailable: return "não foi possível criar a faixa de vídeo final"
        case .missingVideoTrack: return "uma das mídias não possui uma faixa de vídeo válida"
        case .exportFailed: return "não foi possível concluir a exportação"
        case .cancelled: return "exportação cancelada"
        case .emptyOutput: return "o MP4 exportado está vazio ou inválido"
        case .spatialAlignmentUnsupported: return "este compositor não aceita alinhamento espacial"
        }
    }
}

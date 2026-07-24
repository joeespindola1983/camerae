import CameraeCore
import CameraeMedia
import Foundation
import ImageIO
import OSLog

protocol VideoClipReferenceFrameLoading: Sendable {
    func load(url: URL) async throws -> VideoClipAlignmentFrame
}

struct ImageIOVideoClipReferenceFrameLoader: VideoClipReferenceFrameLoading {
    func load(url: URL) async throws -> VideoClipAlignmentFrame {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw RepeatableSessionVideoAlignmentError.invalidReferenceImage
        }
        return VideoClipAlignmentFrame(
            pixelBuffer: try CameraeVisionPixelBufferFactory.makeBGRA(from: image)
        )
    }
}

protocol RepeatableSessionReferenceAlignmentAnalyzing: Sendable {
    func analyze(
        referenceFrame: VideoClipAlignmentFrame,
        referenceFingerprint: String,
        source: VideoClipAlignmentSource
    ) async throws -> EditSpatialAlignmentPlan
}

extension VideoClipAlignmentAnalyzer: RepeatableSessionReferenceAlignmentAnalyzing {}

struct RepeatableSessionVideoAlignmentProcessor: Sendable {
    private let probe: any MediaAssetProbing
    private let referenceLoader: any VideoClipReferenceFrameLoading
    private let analyzer: any RepeatableSessionReferenceAlignmentAnalyzing
    private let composer: any EditVideoComposing

    init(
        probe: any MediaAssetProbing = MediaAssetProbe(),
        referenceLoader: any VideoClipReferenceFrameLoading = ImageIOVideoClipReferenceFrameLoader(),
        analyzer: any RepeatableSessionReferenceAlignmentAnalyzing = VideoClipAlignmentAnalyzer.live(),
        composer: any EditVideoComposing = EditVideoComposer()
    ) {
        self.probe = probe
        self.referenceLoader = referenceLoader
        self.analyzer = analyzer
        self.composer = composer
    }

    func process(
        summary: TimelapseSessionSummary,
        projectReferenceURL: URL,
        settings: CameraeNextRepeatableAlignmentSettings
    ) async throws -> URL {
        var phase = "validation"
        CameraeAlignmentDiagnostics.event(
            "process.start",
            "model=\(settings.model.rawValue) cropLimit=\(settings.maximumCropFraction)"
        )
        do {
            guard settings.isEnabled else {
                throw RepeatableSessionVideoAlignmentError.alignmentDisabled
            }
            guard summary.captureKind == .video,
                  let sourceURL = summary.videoClipURL ?? summary.videoURL else {
                throw RepeatableSessionVideoAlignmentError.videoUnavailable
            }

            phase = "mediaProbe"
            let metadata = try await probe.probe(url: sourceURL)
            CameraeAlignmentDiagnostics.event(
                "media.probed",
                "duration=\(metadata.duration) dimensions=\(metadata.pixelWidth)x\(metadata.pixelHeight) audio=\(metadata.hasAudio)"
            )

            phase = "referenceLoad"
            let referenceFrame = try await referenceLoader.load(url: projectReferenceURL)
            let referenceValues = try? projectReferenceURL.resourceValues(forKeys: [.fileSizeKey])
            CameraeAlignmentDiagnostics.event(
                "reference.loaded",
                "kind=projectImage extension=\(projectReferenceURL.pathExtension.lowercased()) bytes=\(referenceValues?.fileSize ?? -1)"
            )
            let reference = MediaAssetReference(
                projectID: summary.session.projectID,
                sessionID: summary.session.id,
                kind: .repeatableVideo,
                relativePath: sourceURL.lastPathComponent
            )
            let descriptor = MediaAssetDescriptor(
                reference: reference,
                sourceModule: .repeatable,
                projectName: "",
                sessionName: summary.session.name,
                sourceCreatedAt: summary.session.createdAt,
                duration: metadata.duration,
                pixelWidth: metadata.pixelWidth,
                pixelHeight: metadata.pixelHeight,
                hasAudio: metadata.hasAudio,
                fileSize: metadata.fileSize,
                isAvailable: true
            )
            let item = EditTimelineItem(
                id: summary.session.id,
                asset: reference,
                addedAt: summary.session.createdAt
            )
            let isPortrait = summary.session.referenceOrientation.map { !$0.isLandscape }
                ?? (metadata.pixelHeight > metadata.pixelWidth)
            let document = EditProjectDocument(
                projectID: summary.session.projectID,
                canvas: isPortrait ? .portrait9x16 : .landscape16x9,
                items: [item],
                updatedAt: .now
            )
            let source = VideoClipAlignmentSource(
                itemID: item.id,
                url: sourceURL,
                duration: metadata.duration,
                fingerprint: try fingerprint(for: sourceURL)
            )

            phase = "analysis"
            var plan = try await analyzer.analyze(
                referenceFrame: referenceFrame,
                referenceFingerprint: try fingerprint(for: projectReferenceURL),
                source: source
            )
            if settings.model == .position {
                plan = plan.translationOnly
            }
            CameraeAlignmentDiagnostics.plan(plan)

            phase = "safetyPolicy"
            guard let exportPlan = plan.approvedForVideoExport(
                maximumCropFraction: settings.maximumCropFraction
            ) else {
                CameraeAlignmentDiagnostics.error(
                    "plan.blocked",
                    "decision=\(plan.decision.rawValue) reasons=\(plan.reasonCodes.joined(separator: ","))"
                )
                throw RepeatableSessionVideoAlignmentError.alignmentNotApplicable(plan.decision)
            }
            if plan.decision == .review {
                CameraeAlignmentDiagnostics.event(
                    "plan.reviewAccepted",
                    "crop=\(1 - plan.commonCrop.area) reasons=\(plan.reasonCodes.joined(separator: ","))"
                )
            }

            phase = "export"
            CameraeAlignmentDiagnostics.event("export.started")
            let outputURL = summary.session.directoryURL.appendingPathComponent("aligned.mp4")
            let result = try await composer.export(
                project: document,
                assets: [reference.id: ResolvedMediaAsset(descriptor: descriptor, url: sourceURL)],
                spatialAlignment: exportPlan,
                outputURL: outputURL,
                progress: { _ in }
            )
            CameraeAlignmentDiagnostics.event("export.completed")
            return result
        } catch {
            CameraeAlignmentDiagnostics.failure(phase: phase, error: error)
            throw error
        }
    }

    private func fingerprint(for url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return [
            url.standardizedFileURL.path,
            String(values.fileSize ?? -1),
            String(values.contentModificationDate?.timeIntervalSince1970 ?? -1)
        ].joined(separator: "|")
    }
}

enum RepeatableSessionVideoAlignmentError: Error, Equatable {
    case alignmentDisabled
    case videoUnavailable
    case invalidReferenceImage
    case alignmentNotApplicable(ClipAlignmentDecision)
}

extension RepeatableSessionVideoAlignmentError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .alignmentDisabled:
            "O alinhamento está desativado para esta sessão."
        case .videoUnavailable:
            "O vídeo original desta sessão não está disponível."
        case .invalidReferenceImage:
            "A imagem de referência do projeto não pôde ser lida."
        case .alignmentNotApplicable:
            "A imagem de referência e o vídeo não produziram um alinhamento seguro."
        }
    }
}

private extension EditSpatialAlignmentPlan {
    func approvedForVideoExport(maximumCropFraction: Double) -> EditSpatialAlignmentPlan? {
        guard maximumCropFraction.isFinite,
              maximumCropFraction >= 0,
              decision != .reject,
              corrections.values.allSatisfy({
                  $0.quality.decision != .reject &&
                      [.identity, .translation, .similarity].contains($0.model) &&
                      $0.transform.isFinite
              }),
              1 - commonCrop.area <= maximumCropFraction + 0.000_001 else {
            return nil
        }
        guard decision == .review else { return self }
        return EditSpatialAlignmentPlan(
            referenceItemID: referenceItemID,
            corrections: corrections,
            commonCrop: commonCrop,
            decision: .apply,
            reasonCodes: reasonCodes + ["reviewAcceptedWithinUserLimits"]
        )
    }

    var translationOnly: EditSpatialAlignmentPlan {
        let translated = corrections.mapValues { candidate in
            ClipAlignmentCandidate(
                itemID: candidate.itemID,
                model: candidate.model == .identity ? .identity : .translation,
                transform: candidate.model == .identity
                    ? .identity
                    : ClipAlignmentTransform(
                        a: 1,
                        b: 0,
                        c: 0,
                        d: 1,
                        tx: candidate.transform.tx,
                        ty: candidate.transform.ty
                    ),
                validRegion: candidate.validRegion,
                quality: candidate.quality
            )
        }
        return EditSpatialAlignmentPlan(
            referenceItemID: referenceItemID,
            corrections: translated,
            commonCrop: commonCrop,
            decision: decision,
            reasonCodes: reasonCodes
        )
    }
}

enum CameraeAlignmentDiagnostics {
    private static let logger = Logger(
        subsystem: "com.espindola.camerae",
        category: "CameraeAlignment"
    )

    nonisolated static func event(_ stage: String, _ detail: String = "") {
        let suffix = detail.isEmpty ? "" : " | \(detail)"
        logger.notice("[CameraeAlignment] \(stage, privacy: .public)\(suffix, privacy: .public)")
    }

    nonisolated static func error(_ stage: String, _ detail: String) {
        logger.error("[CameraeAlignment] \(stage, privacy: .public) | \(detail, privacy: .public)")
    }

    nonisolated static func failure(phase: String, error: Error) {
        let nsError = error as NSError
        self.error(
            "process.failed",
            "phase=\(phase) type=\(String(reflecting: type(of: error))) domain=\(nsError.domain) code=\(nsError.code) message=\(nsError.localizedDescription)"
        )
    }

    nonisolated static func plan(_ plan: EditSpatialAlignmentPlan) {
        event(
            "analysis.completed",
            "decision=\(plan.decision.rawValue) crop=\(1 - plan.commonCrop.area) reasons=\(plan.reasonCodes.joined(separator: ","))"
        )
        for candidate in plan.corrections.values {
            event(
                "analysis.candidate",
                "model=\(candidate.model.rawValue) decision=\(candidate.quality.decision.rawValue) score=\(candidate.quality.score) tx=\(candidate.transform.tx) ty=\(candidate.transform.ty) validArea=\(candidate.validRegion.area) reasons=\(candidate.quality.reasonCodes.joined(separator: ","))"
            )
        }
    }
}

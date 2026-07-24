import CameraeCore
import CameraeMedia
import CoreVideo
import Foundation
import Testing
@testable import Camerae

@Suite("Repeatable session video alignment processor")
struct RepeatableSessionVideoAlignmentProcessorTests {
    @Test("a single recorded video is exported against the project reference")
    func processesSingleVideo() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let analyzer = ReferenceAnalyzerStub(plan: fixture.plan)
        let composer = AlignmentComposerStub()
        let processor = RepeatableSessionVideoAlignmentProcessor(
            probe: MediaProbeStub(),
            referenceLoader: ReferenceFrameLoaderStub(frame: fixture.referenceFrame),
            analyzer: analyzer,
            composer: composer
        )

        let output = try await processor.process(
            summary: fixture.summary,
            projectReferenceURL: fixture.referenceURL,
            settings: .videoDefault
        )

        #expect(output == fixture.directory.appendingPathComponent("aligned.mp4"))
        #expect(await analyzer.receivedSource?.url == fixture.videoURL)
        #expect(await analyzer.receivedReferenceFingerprint?.contains("reference.jpg") == true)
        #expect(await composer.receivedAlignment == fixture.plan)
        #expect(await composer.receivedItemCount == 1)
    }

    @Test("position mode removes rotation and scale before export")
    func positionModeUsesTranslationOnly() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let composer = AlignmentComposerStub()
        var settings = CameraeNextRepeatableAlignmentSettings.videoDefault
        settings.model = .position
        let processor = RepeatableSessionVideoAlignmentProcessor(
            probe: MediaProbeStub(),
            referenceLoader: ReferenceFrameLoaderStub(frame: fixture.referenceFrame),
            analyzer: ReferenceAnalyzerStub(plan: fixture.plan),
            composer: composer
        )

        _ = try await processor.process(
            summary: fixture.summary,
            projectReferenceURL: fixture.referenceURL,
            settings: settings
        )

        let transform = try #require(await composer.receivedAlignment?.corrections[fixture.summary.id]?.transform)
        #expect(transform.a == 1)
        #expect(transform.b == 0)
        #expect(transform.c == 0)
        #expect(transform.d == 1)
        #expect(transform.tx == 0.04)
        #expect(transform.ty == -0.02)
    }

    @Test("a review plan with only soft warnings is exported within the selected crop limit")
    func softReviewIsExported() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let composer = AlignmentComposerStub()
        let reviewPlan = fixture.plan.with(
            decision: .review,
            reasonCodes: ["largeCrop", "moderateMatchConsistency"]
        )
        let processor = RepeatableSessionVideoAlignmentProcessor(
            probe: MediaProbeStub(),
            referenceLoader: ReferenceFrameLoaderStub(frame: fixture.referenceFrame),
            analyzer: ReferenceAnalyzerStub(plan: reviewPlan),
            composer: composer
        )

        _ = try await processor.process(
            summary: fixture.summary,
            projectReferenceURL: fixture.referenceURL,
            settings: .videoDefault
        )

        #expect(await composer.receivedAlignment?.decision == .apply)
        #expect(await composer.receivedAlignment?.reasonCodes.contains("reviewAcceptedWithinUserLimits") == true)
    }

    @Test("a hard rejection is never exported")
    func hardRejectionIsBlocked() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let composer = AlignmentComposerStub()
        let rejectedPlan = fixture.plan.with(
            decision: .reject,
            reasonCodes: ["insufficientOverlap"]
        )
        let processor = RepeatableSessionVideoAlignmentProcessor(
            probe: MediaProbeStub(),
            referenceLoader: ReferenceFrameLoaderStub(frame: fixture.referenceFrame),
            analyzer: ReferenceAnalyzerStub(plan: rejectedPlan),
            composer: composer
        )

        await #expect(throws: RepeatableSessionVideoAlignmentError.alignmentNotApplicable(.reject)) {
            _ = try await processor.process(
                summary: fixture.summary,
                projectReferenceURL: fixture.referenceURL,
                settings: .videoDefault
            )
        }
        #expect(await composer.receivedAlignment == nil)
    }

    @Test("parallax warnings are never promoted to an aligned export")
    func parallaxReviewIsBlocked() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let composer = AlignmentComposerStub()
        let unsafePlan = fixture.plan.with(
            decision: .review,
            reasonCodes: ["possibleParallaxOrMotion"]
        )
        let processor = RepeatableSessionVideoAlignmentProcessor(
            probe: MediaProbeStub(),
            referenceLoader: ReferenceFrameLoaderStub(frame: fixture.referenceFrame),
            analyzer: ReferenceAnalyzerStub(plan: unsafePlan),
            composer: composer
        )

        await #expect(throws: RepeatableSessionVideoAlignmentError.alignmentNotApplicable(.review)) {
            _ = try await processor.process(
                summary: fixture.summary,
                projectReferenceURL: fixture.referenceURL,
                settings: .videoDefault
            )
        }
        #expect(await composer.receivedAlignment == nil)
    }
}

private struct Fixture {
    let directory: URL
    let referenceURL: URL
    let videoURL: URL
    let summary: TimelapseSessionSummary
    let referenceFrame: VideoClipAlignmentFrame
    let plan: EditSpatialAlignmentPlan

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        referenceURL = directory.appendingPathComponent("reference.jpg")
        videoURL = directory.appendingPathComponent("video.mov")
        try Data([1]).write(to: referenceURL)
        try Data([2]).write(to: videoURL)

        let session = TimelapseSession(
            id: UUID(),
            projectID: UUID(),
            module: .repeatable,
            captureKind: .video,
            referenceMotion: nil,
            referenceGeoPose: nil,
            referenceOrientation: .landscapeRight,
            cameraLens: .wide,
            name: "Video",
            directoryURL: directory,
            createdAt: .now
        )
        summary = TimelapseSessionSummary(
            session: session,
            captureKind: .video,
            frameCount: 1,
            captureDuration: 5,
            referenceFrameURL: nil,
            videoURL: nil,
            videoClipURL: videoURL,
            alignedVideoURL: nil,
            isAstroProcessed: false,
            hasRenderedOutput: true
        )
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 8, 8, kCVPixelFormatType_32BGRA, nil, &buffer)
        referenceFrame = VideoClipAlignmentFrame(pixelBuffer: try #require(buffer))
        let candidate = ClipAlignmentCandidate(
            itemID: session.id,
            model: .similarity,
            transform: .init(a: 0.98, b: 0.1, c: -0.1, d: 0.98, tx: 0.04, ty: -0.02),
            validRegion: .init(x: 0.04, y: 0.02, width: 0.92, height: 0.96),
            quality: .init(decision: .apply, score: 0.92, reasonCodes: ["stableGeometry"])
        )
        plan = try ClipSpatialAlignmentPlanner().makePlan(
            referenceItemID: session.id,
            candidates: [candidate]
        )
    }
}

private struct MediaProbeStub: MediaAssetProbing {
    func probe(url: URL) async throws -> MediaAssetTechnicalMetadata {
        .init(duration: 5, pixelWidth: 1920, pixelHeight: 1080, hasAudio: true, fileSize: 1)
    }
}

private struct ReferenceFrameLoaderStub: VideoClipReferenceFrameLoading {
    let frame: VideoClipAlignmentFrame
    func load(url: URL) async throws -> VideoClipAlignmentFrame { frame }
}

private actor ReferenceAnalyzerStub: RepeatableSessionReferenceAlignmentAnalyzing {
    let plan: EditSpatialAlignmentPlan
    private(set) var receivedReferenceFingerprint: String?
    private(set) var receivedSource: VideoClipAlignmentSource?

    init(plan: EditSpatialAlignmentPlan) {
        self.plan = plan
    }

    func analyze(
        referenceFrame: VideoClipAlignmentFrame,
        referenceFingerprint: String,
        source: VideoClipAlignmentSource
    ) async throws -> EditSpatialAlignmentPlan {
        receivedReferenceFingerprint = referenceFingerprint
        receivedSource = source
        return plan
    }
}

private actor AlignmentComposerStub: EditVideoComposing {
    private(set) var receivedAlignment: EditSpatialAlignmentPlan?
    private(set) var receivedItemCount = 0

    func export(
        project: EditProjectDocument,
        assets: [MediaAssetID: ResolvedMediaAsset],
        outputURL: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL {
        outputURL
    }

    func export(
        project: EditProjectDocument,
        assets: [MediaAssetID: ResolvedMediaAsset],
        spatialAlignment: EditSpatialAlignmentPlan?,
        outputURL: URL,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL {
        receivedAlignment = spatialAlignment
        receivedItemCount = project.items.count
        return outputURL
    }

    func cancel() async {}
}

private extension EditSpatialAlignmentPlan {
    func with(
        decision: ClipAlignmentDecision,
        reasonCodes: [String]
    ) -> EditSpatialAlignmentPlan {
        EditSpatialAlignmentPlan(
            referenceItemID: referenceItemID,
            corrections: corrections,
            commonCrop: commonCrop,
            decision: decision,
            reasonCodes: reasonCodes
        )
    }
}

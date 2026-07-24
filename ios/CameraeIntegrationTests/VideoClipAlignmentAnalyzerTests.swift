import CoreVideo
import Testing
@testable import Camerae
import CameraeMedia

@Suite("Video clip alignment analyzer")
struct VideoClipAlignmentAnalyzerTests {
    @Test("three deterministic samples produce one fixed correction per clip")
    func consensusProducesFixedTransform() async throws {
        let referenceID = UUID()
        let movingID = UUID()
        let extractor = ClipFrameExtractorStub(framesByURL: [
            URL(fileURLWithPath: "/reference.mp4"): try Self.frames(markers: [1, 2, 3]),
            URL(fileURLWithPath: "/moving.mp4"): try Self.frames(markers: [11, 12, 13])
        ])
        let evaluator = ClipPairEvaluatorStub(measurementsByMarker: [
            11: Self.measurement(tx: -0.041, score: 0.90),
            12: Self.measurement(tx: -0.040, score: 0.94),
            13: Self.measurement(tx: -0.039, score: 0.92)
        ])
        let analyzer = VideoClipAlignmentAnalyzer(extractor: extractor, evaluator: evaluator)

        let plan = try await analyzer.analyze(sources: [
            .init(itemID: referenceID, url: URL(fileURLWithPath: "/reference.mp4"), duration: 10),
            .init(itemID: movingID, url: URL(fileURLWithPath: "/moving.mp4"), duration: 8)
        ])

        #expect(plan.decision == .apply)
        #expect(abs((plan.corrections[movingID]?.transform.tx ?? 0) + 0.04) < 0.000_001)
        #expect(await extractor.requestedFractions == [0.2, 0.5, 0.8, 0.2, 0.5, 0.8])
        #expect(await evaluator.evaluatedPairs == 3)
    }

    @Test("one outlier is ignored but two incompatible samples reject the clip")
    func robustConsensus() async throws {
        let referenceID = UUID()
        let movingID = UUID()
        let extractor = ClipFrameExtractorStub(framesByURL: [
            URL(fileURLWithPath: "/reference.mp4"): try Self.frames(markers: [1, 2, 3]),
            URL(fileURLWithPath: "/moving.mp4"): try Self.frames(markers: [11, 12, 13])
        ])
        let evaluator = ClipPairEvaluatorStub(measurementsByMarker: [
            11: Self.measurement(tx: -0.04, score: 0.9),
            12: Self.measurement(tx: -0.041, score: 0.9),
            13: .rejected(reason: "possibleParallaxOrMotion")
        ])
        let accepted = try await VideoClipAlignmentAnalyzer(
            extractor: extractor,
            evaluator: evaluator
        ).analyze(sources: [
            .init(itemID: referenceID, url: URL(fileURLWithPath: "/reference.mp4"), duration: 5),
            .init(itemID: movingID, url: URL(fileURLWithPath: "/moving.mp4"), duration: 5)
        ])
        #expect(accepted.decision == .apply)

        let rejectingEvaluator = ClipPairEvaluatorStub(measurementsByMarker: [
            11: Self.measurement(tx: -0.04, score: 0.9),
            12: .rejected(reason: "possibleParallaxOrMotion"),
            13: .rejected(reason: "insufficientOverlap")
        ])
        let rejected = try await VideoClipAlignmentAnalyzer(
            extractor: extractor,
            evaluator: rejectingEvaluator
        ).analyze(sources: [
            .init(itemID: referenceID, url: URL(fileURLWithPath: "/reference.mp4"), duration: 5),
            .init(itemID: movingID, url: URL(fileURLWithPath: "/moving.mp4"), duration: 5)
        ])
        #expect(rejected.decision == .reject)
        #expect(rejected.applicableCorrections.isEmpty)
    }

    @Test("analysis cache is reused until an asset fingerprint changes")
    func cacheUsesAssetFingerprint() async throws {
        let referenceID = UUID()
        let movingID = UUID()
        let referenceURL = URL(fileURLWithPath: "/reference.mp4")
        let movingURL = URL(fileURLWithPath: "/moving.mp4")
        let extractor = ClipFrameExtractorStub(framesByURL: [
            referenceURL: try Self.frames(markers: [1, 2, 3]),
            movingURL: try Self.frames(markers: [11, 12, 13])
        ])
        let analyzer = VideoClipAlignmentAnalyzer(
            extractor: extractor,
            evaluator: ClipPairEvaluatorStub(measurementsByMarker: [
                11: Self.measurement(tx: -0.04, score: 0.9),
                12: Self.measurement(tx: -0.04, score: 0.9),
                13: Self.measurement(tx: -0.04, score: 0.9)
            ])
        )
        let initialSources = [
            VideoClipAlignmentSource(
                itemID: referenceID, url: referenceURL, duration: 5, fingerprint: "reference-v1"
            ),
            VideoClipAlignmentSource(
                itemID: movingID, url: movingURL, duration: 5, fingerprint: "moving-v1"
            )
        ]

        _ = try await analyzer.analyze(sources: initialSources)
        _ = try await analyzer.analyze(sources: initialSources)
        #expect(await extractor.requestedFractions.count == 6)
        #expect(await analyzer.lastDiagnostics.cacheHit)

        let changedSources = [
            initialSources[0],
            VideoClipAlignmentSource(
                itemID: movingID, url: movingURL, duration: 5, fingerprint: "moving-v2"
            )
        ]
        _ = try await analyzer.analyze(sources: changedSources)

        #expect(await extractor.requestedFractions.count == 12)
        #expect(await analyzer.lastDiagnostics.evaluatedPairCount == 3)
        #expect(!(await analyzer.lastDiagnostics.cacheHit))
    }

    @Test("one video aligns directly against the project reference image")
    func singleVideoUsesProjectReference() async throws {
        let itemID = UUID()
        let videoURL = URL(fileURLWithPath: "/only-video.mp4")
        let extractor = ClipFrameExtractorStub(framesByURL: [
            videoURL: try Self.frames(markers: [11, 12, 13])
        ])
        let evaluator = ClipPairEvaluatorStub(measurementsByMarker: [
            11: Self.measurement(tx: -0.03, score: 0.91),
            12: Self.measurement(tx: -0.03, score: 0.94),
            13: Self.measurement(tx: -0.03, score: 0.92)
        ])
        let analyzer = VideoClipAlignmentAnalyzer(extractor: extractor, evaluator: evaluator)
        let referenceFrame = try #require(Self.frames(markers: [1]).first)

        let plan = try await analyzer.analyze(
            referenceFrame: referenceFrame,
            referenceFingerprint: "project-reference-v1",
            source: .init(
                itemID: itemID,
                url: videoURL,
                duration: 8,
                fingerprint: "video-v1"
            )
        )

        #expect(plan.referenceItemID == itemID)
        #expect(plan.decision == .apply)
        #expect(abs((plan.corrections[itemID]?.transform.tx ?? 0) + 0.03) < 0.000_001)
        #expect(await extractor.requestedFractions == [0.2, 0.5, 0.8])
        #expect(await evaluator.evaluatedPairs == 3)
    }

    @Test("replacing the project reference invalidates single-video analysis cache")
    func referenceFingerprintInvalidatesSingleVideoCache() async throws {
        let itemID = UUID()
        let videoURL = URL(fileURLWithPath: "/only-video.mp4")
        let extractor = ClipFrameExtractorStub(framesByURL: [
            videoURL: try Self.frames(markers: [11, 12, 13])
        ])
        let analyzer = VideoClipAlignmentAnalyzer(
            extractor: extractor,
            evaluator: ClipPairEvaluatorStub(measurementsByMarker: [
                11: Self.measurement(tx: -0.02, score: 0.9),
                12: Self.measurement(tx: -0.02, score: 0.9),
                13: Self.measurement(tx: -0.02, score: 0.9)
            ])
        )
        let referenceFrame = try #require(Self.frames(markers: [1]).first)
        let source = VideoClipAlignmentSource(
            itemID: itemID,
            url: videoURL,
            duration: 5,
            fingerprint: "video-v1"
        )

        _ = try await analyzer.analyze(
            referenceFrame: referenceFrame,
            referenceFingerprint: "reference-v1",
            source: source
        )
        _ = try await analyzer.analyze(
            referenceFrame: referenceFrame,
            referenceFingerprint: "reference-v1",
            source: source
        )
        #expect(await extractor.requestedFractions.count == 3)
        #expect(await analyzer.lastDiagnostics.cacheHit)

        _ = try await analyzer.analyze(
            referenceFrame: referenceFrame,
            referenceFingerprint: "reference-v2",
            source: source
        )
        #expect(await extractor.requestedFractions.count == 6)
        #expect(!(await analyzer.lastDiagnostics.cacheHit))
    }

    private static func frames(markers: [UInt8]) throws -> [VideoClipAlignmentFrame] {
        try markers.map { marker in
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 8, 8, kCVPixelFormatType_32BGRA, nil, &buffer)
            let result = try #require(buffer)
            CVPixelBufferLockBaseAddress(result, [])
            CVPixelBufferGetBaseAddress(result)!.assumingMemoryBound(to: UInt8.self).pointee = marker
            CVPixelBufferUnlockBaseAddress(result, [])
            return VideoClipAlignmentFrame(pixelBuffer: result)
        }
    }

    private static func measurement(tx: Double, score: Double) -> VideoClipAlignmentMeasurement {
        .init(
            model: .translation,
            transform: .init(a: 1, b: 0, c: 0, d: 1, tx: tx, ty: 0.01),
            validRegion: .init(x: 0, y: 0.01, width: 0.95, height: 0.99),
            quality: .init(decision: .apply, score: score, reasonCodes: ["stableGeometry"])
        )
    }
}

private actor ClipFrameExtractorStub: VideoClipAlignmentFrameExtracting {
    let framesByURL: [URL: [VideoClipAlignmentFrame]]
    private(set) var requestedFractions: [Double] = []

    init(framesByURL: [URL: [VideoClipAlignmentFrame]]) {
        self.framesByURL = framesByURL
    }

    func frames(for source: VideoClipAlignmentSource, fractions: [Double]) async throws -> [VideoClipAlignmentFrame] {
        requestedFractions.append(contentsOf: fractions)
        return framesByURL[source.url] ?? []
    }
}

private actor ClipPairEvaluatorStub: VideoClipAlignmentPairEvaluating {
    let measurementsByMarker: [UInt8: VideoClipAlignmentMeasurement]
    private(set) var evaluatedPairs = 0

    init(measurementsByMarker: [UInt8: VideoClipAlignmentMeasurement]) {
        self.measurementsByMarker = measurementsByMarker
    }

    func evaluate(
        reference: VideoClipAlignmentFrame,
        moving: VideoClipAlignmentFrame
    ) async throws -> VideoClipAlignmentMeasurement {
        evaluatedPairs += 1
        CVPixelBufferLockBaseAddress(moving.pixelBuffer, .readOnly)
        let marker = CVPixelBufferGetBaseAddress(moving.pixelBuffer)!.assumingMemoryBound(to: UInt8.self).pointee
        CVPixelBufferUnlockBaseAddress(moving.pixelBuffer, .readOnly)
        return measurementsByMarker[marker] ?? .rejected(reason: "missingFixture")
    }
}

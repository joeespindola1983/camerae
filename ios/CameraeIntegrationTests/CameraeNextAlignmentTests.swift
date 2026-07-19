import CameraeCore
import CameraeMedia
import Foundation
import Testing
@testable import Camerae

@Suite("Camerae Next alignment presentation")
@MainActor
struct CameraeNextAlignmentTests {
    @Test("analysis lifecycle publishes an applicable automatic plan")
    func automaticAnalysisLifecycle() async throws {
        let fixture = try Self.fixture(decision: .apply, cropArea: 0.94)
        let analyzer = CameraeNextAlignmentAnalyzerStub(result: .success(fixture.plan))
        let model = CameraeNextAlignmentViewModel(analyzer: analyzer)

        model.prepare(document: fixture.document, assets: fixture.assets)
        #expect(model.snapshot.status == .ready)

        await model.analyze()

        #expect(model.snapshot.status == .applied)
        #expect(model.snapshot.cropPercentage == 6)
        #expect(model.exportPlan == fixture.plan)
        #expect(await analyzer.callCount == 1)
    }

    @Test("review and rejection remain explicit instead of becoming export plans")
    func conservativeDecisions() async throws {
        for decision in [ClipAlignmentDecision.review, .reject] {
            let fixture = try Self.fixture(decision: decision, cropArea: 0.82)
            let model = CameraeNextAlignmentViewModel(
                analyzer: CameraeNextAlignmentAnalyzerStub(result: .success(fixture.plan))
            )
            model.prepare(document: fixture.document, assets: fixture.assets)

            await model.analyze()

            #expect(model.snapshot.status == (decision == .review ? .review : .rejected))
            #expect(model.exportPlan == nil)
        }
    }

    @Test("position-only mode removes rotation and scale from the export plan")
    func positionOnlyProjection() async throws {
        let fixture = try Self.fixture(decision: .apply, cropArea: 0.91, similarity: true)
        let model = CameraeNextAlignmentViewModel(
            analyzer: CameraeNextAlignmentAnalyzerStub(result: .success(fixture.plan))
        )
        model.setMode(.position)
        model.prepare(document: fixture.document, assets: fixture.assets)
        await model.analyze()

        let correction = try #require(model.exportPlan?.corrections[fixture.movingItemID])
        #expect(correction.model == .translation)
        #expect(correction.transform.a == 1)
        #expect(correction.transform.b == 0)
        #expect(correction.transform.c == 0)
        #expect(correction.transform.d == 1)
        #expect(correction.transform.tx == fixture.plan.corrections[fixture.movingItemID]?.transform.tx)
    }

    @Test("timeline changes invalidate a completed analysis")
    func timelineInvalidation() async throws {
        let fixture = try Self.fixture(decision: .apply, cropArea: 0.95)
        let model = CameraeNextAlignmentViewModel(
            analyzer: CameraeNextAlignmentAnalyzerStub(result: .success(fixture.plan))
        )
        model.prepare(document: fixture.document, assets: fixture.assets)
        await model.analyze()
        #expect(model.snapshot.status == .applied)

        var changed = fixture.document
        changed.items.swapAt(0, 1)
        model.prepare(document: changed, assets: fixture.assets)

        #expect(model.snapshot.status == .stale)
        #expect(model.exportPlan == nil)
    }

    @Test("disabled mode never exposes a plan")
    func disabledMode() async throws {
        let fixture = try Self.fixture(decision: .apply, cropArea: 0.96)
        let model = CameraeNextAlignmentViewModel(
            analyzer: CameraeNextAlignmentAnalyzerStub(result: .success(fixture.plan))
        )
        model.prepare(document: fixture.document, assets: fixture.assets)
        model.setMode(.off)

        #expect(model.snapshot.status == .off)
        #expect(model.exportPlan == nil)
    }

    private struct Fixture {
        let document: EditProjectDocument
        let assets: [MediaAssetID: ResolvedMediaAsset]
        let plan: EditSpatialAlignmentPlan
        let movingItemID: UUID
    }

    private static func fixture(
        decision: ClipAlignmentDecision,
        cropArea: Double,
        similarity: Bool = false
    ) throws -> Fixture {
        let projectID = UUID()
        let firstAsset = mediaAsset(projectID: projectID, index: 1)
        let secondAsset = mediaAsset(projectID: projectID, index: 2)
        let firstItem = EditTimelineItem(
            id: UUID(),
            asset: firstAsset.reference,
            addedAt: Date(timeIntervalSince1970: 1)
        )
        let secondItem = EditTimelineItem(
            id: UUID(),
            asset: secondAsset.reference,
            addedAt: Date(timeIntervalSince1970: 2)
        )
        let document = EditProjectDocument(
            projectID: projectID,
            canvas: .landscape16x9,
            items: [firstItem, secondItem],
            updatedAt: Date(timeIntervalSince1970: 3)
        )
        let transform = similarity
            ? ClipAlignmentTransform.similarity(
                translationX: 0.03,
                translationY: -0.02,
                rotationRadians: 0.08,
                scale: 1.04
            )
            : ClipAlignmentTransform(a: 1, b: 0, c: 0, d: 1, tx: 0.03, ty: -0.02)
        let cropSide = cropArea.squareRoot()
        let commonCrop = ClipAlignmentNormalizedRect(
            x: (1 - cropSide) / 2,
            y: (1 - cropSide) / 2,
            width: cropSide,
            height: cropSide
        )
        let plan = try ClipSpatialAlignmentPlanner(maximumCropFraction: 0.25).makePlan(
            referenceItemID: firstItem.id,
            candidates: [
                .identity(itemID: firstItem.id),
                ClipAlignmentCandidate(
                    itemID: secondItem.id,
                    model: similarity ? .similarity : .translation,
                    transform: transform,
                    validRegion: commonCrop,
                    quality: .init(decision: decision, score: 0.86, reasonCodes: [])
                )
            ]
        )
        return Fixture(
            document: document,
            assets: [
                firstAsset.reference.id: ResolvedMediaAsset(
                    descriptor: firstAsset,
                    url: URL(fileURLWithPath: "/tmp/first.mp4")
                ),
                secondAsset.reference.id: ResolvedMediaAsset(
                    descriptor: secondAsset,
                    url: URL(fileURLWithPath: "/tmp/second.mp4")
                )
            ],
            plan: plan,
            movingItemID: secondItem.id
        )
    }

    private static func mediaAsset(projectID: UUID, index: Int) -> MediaAssetDescriptor {
        MediaAssetDescriptor(
            reference: MediaAssetReference(
                id: MediaAssetID(rawValue: "asset-\(index)"),
                projectID: projectID,
                sessionID: UUID(),
                kind: .repeatableVideo,
                relativePath: "Sessions/\(index).mp4"
            ),
            sourceModule: .repeatable,
            projectName: "Fixture",
            sessionName: "Session \(index)",
            sourceCreatedAt: Date(timeIntervalSince1970: Double(index)),
            duration: 5,
            pixelWidth: 1920,
            pixelHeight: 1080,
            hasAudio: true,
            fileSize: 1_024,
            isAvailable: true
        )
    }
}

private actor CameraeNextAlignmentAnalyzerStub: CameraeNextAlignmentAnalyzing {
    let result: Result<EditSpatialAlignmentPlan, Error>
    private(set) var callCount = 0

    init(result: Result<EditSpatialAlignmentPlan, Error>) {
        self.result = result
    }

    func analyze(
        document: EditProjectDocument,
        assets: [MediaAssetID: ResolvedMediaAsset]
    ) async throws -> EditSpatialAlignmentPlan {
        callCount += 1
        return try result.get()
    }
}

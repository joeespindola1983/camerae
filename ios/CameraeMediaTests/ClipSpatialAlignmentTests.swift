import Foundation
import Testing
@testable import CameraeMedia

@Suite("Clip spatial alignment plan")
struct ClipSpatialAlignmentTests {
    @Test("Identity reference and translated clip produce one stable common crop")
    func translationCommonCrop() throws {
        let referenceID = UUID(uuidString: "A9000000-0000-0000-0000-000000000001")!
        let movingID = UUID(uuidString: "A9000000-0000-0000-0000-000000000002")!
        let candidates = [
            ClipAlignmentCandidate.identity(itemID: referenceID),
            ClipAlignmentCandidate(
                itemID: movingID,
                model: .translation,
                transform: .init(a: 1, b: 0, c: 0, d: 1, tx: 0.08, ty: -0.04),
                validRegion: .init(x: 0.08, y: 0, width: 0.92, height: 0.96),
                quality: .init(decision: .apply, score: 0.91, reasonCodes: ["stableGeometry"])
            )
        ]

        let plan = try ClipSpatialAlignmentPlanner(maximumCropFraction: 0.20).makePlan(
            referenceItemID: referenceID,
            candidates: candidates
        )

        #expect(plan.decision == .apply)
        #expect(plan.commonCrop == .init(x: 0.08, y: 0, width: 0.92, height: 0.96))
        #expect(plan.corrections[movingID]?.model == .translation)
        #expect(plan.corrections[referenceID]?.transform == .identity)
    }

    @Test("Similarity remains geometry-preserving but affine and perspective require review")
    func supportedModels() throws {
        let itemID = UUID()
        let similarity = ClipAlignmentCandidate(
            itemID: itemID,
            model: .similarity,
            transform: .similarity(
                translationX: 0.02,
                translationY: -0.01,
                rotationRadians: 2 * .pi / 180,
                scale: 1.01
            ),
            validRegion: .full,
            quality: .init(decision: .apply, score: 0.9, reasonCodes: [])
        )
        let affine = ClipAlignmentCandidate(
            itemID: itemID,
            model: .affine,
            transform: .identity,
            validRegion: .full,
            quality: .init(decision: .apply, score: 0.9, reasonCodes: [])
        )

        #expect(try ClipSpatialAlignmentPlanner().makePlan(
            referenceItemID: itemID,
            candidates: [similarity]
        ).decision == .apply)
        #expect(try ClipSpatialAlignmentPlanner().makePlan(
            referenceItemID: itemID,
            candidates: [affine]
        ).decision == .review)
    }

    @Test("Excessive crop rejects the complete sequence instead of partially applying")
    func excessiveCropRejectsAllCorrections() throws {
        let referenceID = UUID()
        let movingID = UUID()
        let plan = try ClipSpatialAlignmentPlanner(maximumCropFraction: 0.20).makePlan(
            referenceItemID: referenceID,
            candidates: [
                .identity(itemID: referenceID),
                ClipAlignmentCandidate(
                    itemID: movingID,
                    model: .translation,
                    transform: .identity,
                    validRegion: .init(x: 0.3, y: 0, width: 0.7, height: 1),
                    quality: .init(decision: .apply, score: 0.8, reasonCodes: [])
                )
            ]
        )

        #expect(plan.decision == .reject)
        #expect(plan.applicableCorrections.isEmpty)
        #expect(plan.reasonCodes.contains("excessiveCommonCrop"))
    }

    @Test("Rejected candidate and invalid numeric transform can never be rendered")
    func unsafeCandidateCannotApply() throws {
        let referenceID = UUID()
        let rejectedID = UUID()
        let rejected = try ClipSpatialAlignmentPlanner().makePlan(
            referenceItemID: referenceID,
            candidates: [
                .identity(itemID: referenceID),
                ClipAlignmentCandidate(
                    itemID: rejectedID,
                    model: .translation,
                    transform: .identity,
                    validRegion: .full,
                    quality: .init(decision: .reject, score: 0.1, reasonCodes: ["possibleParallaxOrMotion"])
                )
            ]
        )
        #expect(rejected.decision == .reject)
        #expect(rejected.applicableCorrections.isEmpty)

        #expect(throws: ClipSpatialAlignmentError.invalidTransform(rejectedID)) {
            try ClipSpatialAlignmentPlanner().makePlan(
                referenceItemID: referenceID,
                candidates: [
                    .identity(itemID: referenceID),
                    ClipAlignmentCandidate(
                        itemID: rejectedID,
                        model: .translation,
                        transform: .init(a: .nan, b: 0, c: 0, d: 1, tx: 0, ty: 0),
                        validRegion: .full,
                        quality: .init(decision: .apply, score: 1, reasonCodes: [])
                    )
                ]
            )
        }
    }
}

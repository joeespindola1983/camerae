import CameraeCore
import Foundation
import Testing
@testable import CameraeMedia

@Suite("Edit composition planner")
struct EditCompositionPlanTests {
    @Test("segments preserve timeline order and accumulate duration without gaps")
    func preservesOrderAndDuration() throws {
        let fixture = CompositionFixture()
        let plan = try EditCompositionPlanner().makePlan(
            document: fixture.document(canvas: .landscape16x9),
            assets: fixture.assets
        )

        #expect(plan.renderWidth == 1920)
        #expect(plan.renderHeight == 1080)
        #expect(plan.frameRate == 30)
        #expect(plan.segments.map { $0.itemID } == fixture.itemIDs)
        #expect(plan.segments.map { $0.startTime } == [0, 1.25])
        #expect(plan.totalDuration == 3.75)
    }

    @Test("portrait canvas uses the fixed vertical render size")
    func portraitCanvas() throws {
        let fixture = CompositionFixture()
        let plan = try EditCompositionPlanner().makePlan(
            document: fixture.document(canvas: .portrait9x16),
            assets: fixture.assets
        )

        #expect(plan.renderWidth == 1080)
        #expect(plan.renderHeight == 1920)
    }

    @Test("empty and missing timelines fail before AVFoundation work")
    func invalidTimelineFails() {
        let fixture = CompositionFixture()
        let empty = EditProjectDocument(
            projectID: fixture.editProjectID,
            canvas: .landscape16x9,
            items: [],
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        #expect(throws: EditCompositionError.emptyTimeline) {
            try EditCompositionPlanner().makePlan(document: empty, assets: fixture.assets)
        }
        #expect(throws: EditCompositionError.missingMedia(fixture.references[1].id)) {
            try EditCompositionPlanner().makePlan(
                document: fixture.document(canvas: .landscape16x9),
                assets: [fixture.references[0].id: fixture.assets[fixture.references[0].id]!]
            )
        }
    }
}

private struct CompositionFixture {
    let editProjectID = UUID(uuidString: "90000000-0000-0000-0000-000000000001")!
    let itemIDs = [
        UUID(uuidString: "90000000-0000-0000-0000-000000000002")!,
        UUID(uuidString: "90000000-0000-0000-0000-000000000003")!
    ]
    let references: [MediaAssetReference]
    let assets: [MediaAssetID: ResolvedMediaAsset]

    init() {
        var references: [MediaAssetReference] = []
        var assets: [MediaAssetID: ResolvedMediaAsset] = [:]
        for index in 0..<2 {
            let reference = MediaAssetReference(
                projectID: UUID(uuidString: String(format: "91000000-0000-0000-0000-%012d", index + 1))!,
                sessionID: UUID(uuidString: String(format: "92000000-0000-0000-0000-%012d", index + 1))!,
                kind: .repeatableTimelapse,
                relativePath: "Sessions/s\(index)/timelapse.mp4"
            )
            let duration = index == 0 ? 1.25 : 2.5
            let descriptor = MediaAssetDescriptor(
                reference: reference,
                sourceModule: .repeatable,
                projectName: "Source",
                sessionName: "Session",
                sourceCreatedAt: Date(timeIntervalSince1970: 0),
                duration: duration,
                pixelWidth: index == 0 ? 1920 : 1080,
                pixelHeight: index == 0 ? 1080 : 1920,
                hasAudio: false,
                fileSize: 10,
                isAvailable: true
            )
            references.append(reference)
            assets[reference.id] = ResolvedMediaAsset(
                descriptor: descriptor,
                url: URL(fileURLWithPath: "/tmp/clip\(index).mp4")
            )
        }
        self.references = references
        self.assets = assets
    }

    func document(canvas: EditCanvas) -> EditProjectDocument {
        EditProjectDocument(
            projectID: editProjectID,
            canvas: canvas,
            items: zip(itemIDs, references).map {
                EditTimelineItem(id: $0.0, asset: $0.1, addedAt: Date(timeIntervalSince1970: 0))
            },
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}

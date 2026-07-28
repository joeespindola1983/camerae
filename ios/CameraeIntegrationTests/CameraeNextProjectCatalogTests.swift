import CameraeCore
import Foundation
import Testing
@testable import Camerae

@Suite("Camerae Next project catalog")
struct CameraeNextProjectCatalogTests {
    @Test("catalog keeps only active projects from the selected workflow")
    func activeWorkflowProjects() {
        let older = makeProject(name: "Older", module: .repeatable, day: 1)
        let latest = makeProject(name: "Latest", module: .repeatable, day: 3)
        let archived = makeProject(name: "Archived", module: .repeatable, day: 4, archived: true)
        let astro = makeProject(name: "Astro", module: .astrophotography, day: 5)

        let catalog = CameraeNextProjectCatalogModel(
            projects: [older, archived, astro, latest],
            module: .repeatable,
            filter: .recent
        )

        #expect(catalog.featuredProject?.name == "Latest")
        #expect(catalog.remainingProjects.map(\.name) == ["Older"])
        #expect(catalog.projectCount == 2)
    }

    @Test("capture and archive filters keep archived projects out of active results")
    func captureAndArchiveFilters() {
        let featured = makeProject(name: "Featured", module: .repeatable, day: 4, mediaCount: 2)
        let empty = makeProject(name: "Empty", module: .repeatable, day: 3)
        let captured = makeProject(name: "Captured", module: .repeatable, day: 2, mediaCount: 40)
        let archived = makeProject(name: "Archived", module: .repeatable, day: 5, archived: true, mediaCount: 12)

        let withCaptures = CameraeNextProjectCatalogModel(
            projects: [featured, empty, captured, archived],
            module: .repeatable,
            filter: .withCaptures
        )
        let archivedProjects = CameraeNextProjectCatalogModel(
            projects: [featured, empty, captured, archived],
            module: .repeatable,
            filter: .archived
        )

        #expect(withCaptures.visibleProjects.map(\.name) == ["Featured", "Captured"])
        #expect(archivedProjects.visibleProjects.map(\.name) == ["Archived"])
    }

    @Test("temporary project policy only removes a project without captures")
    func temporaryProjectPolicy() {
        #expect(CameraeNextTemporaryProjectPolicy.shouldOfferRemoval(hasCapturedMedia: false))
        #expect(!CameraeNextTemporaryProjectPolicy.shouldOfferRemoval(hasCapturedMedia: true))
    }

    @Test("project catalogs keep the design-system screen inset in both workflows")
    func sharedScreenInset() {
        #expect(CameraeNextProjectCatalogLayout(module: .repeatable).horizontalContentInset == 16)
        #expect(CameraeNextProjectCatalogLayout(module: .astrophotography).horizontalContentInset == 16)
        #expect(CameraeNextProjectCatalogLayout(module: .repeatable).contentWidth(containerWidth: 393) == 361)
        #expect(CameraeNextProjectCatalogLayout(module: .astrophotography).contentWidth(containerWidth: 393) == 361)
    }

    @Test("project cards keep one orientation-independent thumbnail above their information")
    func projectRowLayout() {
        let layout = ProjectListRowLayout(containerWidth: 361)

        #expect(layout.thumbnailSize == CGSize(width: 361, height: 160))
        #expect(layout.minimumHeight == 244)
        #expect(layout.thumbnailRange.upperBound <= layout.informationRange.lowerBound)
    }

    @Test("every project card keeps reversible archive and destructive delete capabilities")
    func projectCardCapabilities() {
        let active = makeProject(name: "Active", module: .repeatable, day: 1)
        let archived = makeProject(name: "Archived", module: .repeatable, day: 2, archived: true)

        #expect(ProjectCatalogActionPolicy.actions(for: active) == [.archive, .delete])
        #expect(ProjectCatalogActionPolicy.actions(for: archived) == [.unarchive, .delete])
    }

    private func makeProject(
        name: String,
        module: CameraModule,
        day: Int,
        archived: Bool = false,
        mediaCount: Int = 0
    ) -> CameraProject {
        let date = Date(timeIntervalSince1970: TimeInterval(day * 86_400))
        let record = ProjectRecord(
            id: UUID(),
            module: module.coreValue,
            name: name,
            directoryURL: URL(fileURLWithPath: "/tmp/\(name)"),
            createdAt: date,
            updatedAt: date,
            lastOpenedAt: date,
            isArchived: archived
        )
        let summary = ProjectSummary(
            sessionCount: mediaCount == 0 ? 0 : 1,
            mediaCount: mediaCount,
            referenceThumbnailKey: nil,
            latestSessionAt: mediaCount == 0 ? nil : date,
            totalKnownBytes: 0,
            inventoryState: .clean,
            generation: 0
        )
        return CameraProject(record: record, summary: summary)
    }
}

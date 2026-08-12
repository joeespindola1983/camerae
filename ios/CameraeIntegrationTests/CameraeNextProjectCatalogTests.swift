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

    @Test("creation sorting keeps newest projects first without changing the selected filter")
    func creationDateSorting() {
        let olderRecentlyOpened = makeProject(
            name: "Older but active",
            module: .repeatable,
            day: 1,
            lastOpenedDay: 5
        )
        let newest = makeProject(
            name: "Newest",
            module: .repeatable,
            day: 4,
            lastOpenedDay: 4
        )

        let byActivity = CameraeNextProjectCatalogModel(
            projects: [olderRecentlyOpened, newest],
            module: .repeatable,
            filter: .recent,
            sort: .lastActivity
        )
        let byCreation = CameraeNextProjectCatalogModel(
            projects: [olderRecentlyOpened, newest],
            module: .repeatable,
            filter: .recent,
            sort: .createdNewest
        )

        #expect(byActivity.visibleProjects.map(\.name) == ["Older but active", "Newest"])
        #expect(byCreation.visibleProjects.map(\.name) == ["Newest", "Older but active"])
    }

    @Test("catalog defaults to stable shot order and exposes each memorisable number")
    func stableDefaultShotOrder() {
        let firstRecentlyOpened = makeProject(
            name: "First",
            module: .repeatable,
            day: 1,
            lastOpenedDay: 5,
            sequenceNumber: 1
        )
        let second = makeProject(
            name: "Second",
            module: .repeatable,
            day: 2,
            sequenceNumber: 2
        )

        let catalog = CameraeNextProjectCatalogModel(
            projects: [firstRecentlyOpened, second],
            module: .repeatable,
            filter: .recent
        )

        #expect(catalog.visibleProjects.map(\.name) == ["Second", "First"])
        #expect(catalog.visibleProjects.map(\.shotNumberLabel) == ["#2", "#1"])
    }

    @Test("temporary project policy silently discards only a project without durable content")
    func temporaryProjectPolicy() {
        #expect(CameraeNextTemporaryProjectPolicy.shouldAutomaticallyDiscard(hasDurableContent: false))
        #expect(!CameraeNextTemporaryProjectPolicy.shouldAutomaticallyDiscard(hasDurableContent: true))
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

    @Test("project cards summarize only durable captures by type")
    func projectCardCaptureSummary() {
        let date = Date(timeIntervalSince1970: 1_754_000_000)
        let summaries = [
            makeSessionSummary(kind: .photo, purpose: .projectReference, date: date),
            makeSessionSummary(kind: .photo, date: date.addingTimeInterval(60)),
            makeSessionSummary(kind: .video, date: date.addingTimeInterval(120)),
            makeSessionSummary(kind: .video, date: date.addingTimeInterval(180))
        ]

        let presentation = ProjectListCardPresentation(
            summaries: summaries,
            fallbackHardware: nil,
            locale: Locale(identifier: "pt_BR"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(presentation.captureTypesText == "FOTO (1) · VÍDEO (2)")
        #expect(!presentation.captureTypesText.contains("TIMELAPSE"))
    }

    @Test("project cards give the used camera its own line and show the latest capture date without opened copy")
    func projectCardCameraAndLatestCapture() {
        let earlier = Date(timeIntervalSince1970: 1_754_000_000)
        let latest = earlier.addingTimeInterval(3_600)
        let summaries = [
            makeSessionSummary(kind: .photo, date: earlier, lens: .wide, zoom: 1),
            makeSessionSummary(kind: .video, date: latest, lens: .ultraWide, zoom: 1)
        ]

        let presentation = ProjectListCardPresentation(
            summaries: summaries,
            fallbackHardware: nil,
            locale: Locale(identifier: "pt_BR"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(presentation.cameraText == "CÂMERA · ULTRA-ANGULAR 1×")
        #expect(presentation.lastCaptureText?.contains("ABERTO") == false)
        #expect(presentation.lastCaptureText?.contains(":") == true)
    }

    @Test("project card opening and options stay in distinct semantic regions")
    func projectCardActionRegions() {
        #expect(ProjectListCardCapabilityPolicy.openRegion == .information)
        #expect(ProjectListCardCapabilityPolicy.optionsRegion == .thumbnail)
        #expect(ProjectListCardCapabilityPolicy.openRegion != ProjectListCardCapabilityPolicy.optionsRegion)
    }

    @Test("every Repeatable project card keeps move, reversible archive, and destructive delete capabilities")
    func projectCardCapabilities() {
        let active = makeProject(name: "Active", module: .repeatable, day: 1)
        let archived = makeProject(name: "Archived", module: .repeatable, day: 2, archived: true)

        #expect(ProjectCatalogActionPolicy.actions(for: active) == [.move, .archive, .delete])
        #expect(ProjectCatalogActionPolicy.actions(for: archived) == [.move, .unarchive, .delete])
    }

    @Test("catalog toolbar capabilities remain reachable independent of layout")
    func catalogToolbarCapabilities() {
        #expect(
            CameraeNextProjectCatalogCapabilityPolicy.actions(for: .repeatable) ==
                [.filter, .sort, .createGroup, .createProject]
        )
        #expect(
            CameraeNextProjectCatalogCapabilityPolicy.actions(for: .astrophotography) ==
                [.filter, .sort, .createProject]
        )
    }

    @Test("catalog empty states expose the correct recovery action")
    func catalogEmptyStatePresentation() {
        let projects = CameraeNextCatalogEmptyStatePresentation(
            scope: .projects,
            filter: .recent
        )
        let groups = CameraeNextCatalogEmptyStatePresentation(
            scope: .groups,
            filter: .recent
        )
        let archivedGroups = CameraeNextCatalogEmptyStatePresentation(
            scope: .groups,
            filter: .archived
        )

        #expect(projects.action == .createProject)
        #expect(groups.action == .createGroup)
        #expect(archivedGroups.action == nil)
        #expect(!projects.title.isEmpty)
        #expect(!groups.message.isEmpty)
    }

    @Test("group-only catalogs hide project onboarding and project-only controls")
    func groupOnlyCatalogPresentation() {
        let empty = CameraeNextProjectCatalogContentPolicy(
            hasGroups: false,
            hasUngroupedProjects: false
        )
        let groupsOnly = CameraeNextProjectCatalogContentPolicy(
            hasGroups: true,
            hasUngroupedProjects: false
        )
        let mixed = CameraeNextProjectCatalogContentPolicy(
            hasGroups: true,
            hasUngroupedProjects: true
        )

        #expect(empty.showsFirstProjectOnboarding)
        #expect(empty.showsProjectSection)
        #expect(!empty.showsProjectFilters)

        #expect(!groupsOnly.showsFirstProjectOnboarding)
        #expect(!groupsOnly.showsProjectSection)
        #expect(!groupsOnly.showsProjectFilters)

        #expect(!mixed.showsFirstProjectOnboarding)
        #expect(mixed.showsProjectSection)
        #expect(mixed.showsProjectFilters)
    }

    @Test("organization catalogs present root groups, subgroups, then direct projects")
    func organizationHierarchy() {
        let rootID = UUID()
        let subgroupID = UUID()
        let rootProject = makeProject(name: "Fachada", module: .repeatable, day: 4)
        let subgroupProject = makeProject(name: "Escultura", module: .repeatable, day: 3)
        let ungrouped = makeProject(name: "Praça", module: .repeatable, day: 2)
        let root = makeOrganizationNode(id: rootID, parentID: nil, name: "Catedral", day: 4)
        let subgroup = makeOrganizationNode(
            id: subgroupID,
            parentID: rootID,
            name: "Detalhes",
            day: 3
        )
        let snapshot = ProjectOrganizationSnapshot(
            nodes: [subgroup, root],
            memberships: [
                .init(projectID: rootProject.id, nodeID: rootID),
                .init(projectID: subgroupProject.id, nodeID: subgroupID)
            ]
        )
        let model = CameraeNextProjectOrganizationModel(
            projects: [ungrouped, subgroupProject, rootProject],
            module: .repeatable,
            organization: snapshot,
            filter: .recent,
            sort: .createdNewest
        )

        #expect(model.rootNodes.map(\.name) == ["Catedral"])
        #expect(model.hasGroups)
        #expect(model.hasUngroupedProjects)
        #expect(model.childNodes(of: rootID).map(\.name) == ["Detalhes"])
        #expect(model.directProjects(in: rootID).map(\.name) == ["Fachada"])
        #expect(model.directProjects(in: subgroupID).map(\.name) == ["Escultura"])
        #expect(model.ungroupedProjects.map(\.name) == ["Praça"])
        #expect(model.descendantProjects(in: rootID).map(\.name) == ["Fachada", "Escultura"])
    }

    @Test("group mosaics give every preview equal area and keep all four quadrants")
    func organizationMosaicLayout() {
        let size = CGSize(width: 360, height: 160)
        let three = CameraeNextProjectGroupMosaicLayout.frames(count: 3, size: size)
        let four = CameraeNextProjectGroupMosaicLayout.frames(count: 4, size: size)

        #expect(three.count == 3)
        #expect(Set(three.map { $0.width * $0.height }).count == 1)
        #expect(three.allSatisfy { $0.minX >= 0 && $0.maxX <= size.width })

        #expect(four.count == 4)
        #expect(Set(four.map { $0.width * $0.height }).count == 1)
        #expect(Set(four.map { $0.origin }).count == 4)
        #expect(four.allSatisfy { $0.minX >= 0 && $0.maxX <= size.width })
        #expect(four.allSatisfy { $0.minY >= 0 && $0.maxY <= size.height })
    }

    @Test("group mosaics include projects from nested descendant groups")
    func nestedOrganizationMosaicProjects() {
        let rootID = UUID()
        let childID = UUID()
        let grandchildID = UUID()
        let direct = makeProject(name: "Direto", module: .repeatable, day: 4)
        let nested = makeProject(name: "Aninhado", module: .repeatable, day: 3)
        let model = CameraeNextProjectOrganizationModel(
            projects: [direct, nested],
            module: .repeatable,
            organization: .init(
                nodes: [
                    makeOrganizationNode(id: rootID, parentID: nil, name: "Catedral", day: 4),
                    makeOrganizationNode(id: childID, parentID: rootID, name: "Interior", day: 3),
                    makeOrganizationNode(id: grandchildID, parentID: childID, name: "Capela", day: 2)
                ],
                memberships: [
                    .init(projectID: direct.id, nodeID: childID),
                    .init(projectID: nested.id, nodeID: grandchildID)
                ]
            ),
            filter: .recent
        )

        #expect(model.descendantProjects(in: rootID).map(\.name) == ["Direto", "Aninhado"])
        #expect(model.mosaicProjects(in: rootID).count == 2)
    }

    @Test("group cards expose rename, archive, and delete-with-preservation capabilities")
    func organizationCapabilities() {
        let active = makeOrganizationNode(id: UUID(), parentID: nil, name: "Ativo", day: 1)
        let archived = ProjectOrganizationNode(
            id: UUID(),
            module: .repeatable,
            parentID: nil,
            name: "Arquivado",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            isArchived: true
        )

        #expect(
            ProjectOrganizationActionPolicy.actions(for: active) ==
            [.rename, .archive, .deletePreservingProjects]
        )
        #expect(
            ProjectOrganizationActionPolicy.actions(for: archived) ==
            [.rename, .unarchive, .deletePreservingProjects]
        )
    }

    @Test("archiving a group keeps its active subgroups and projects reachable")
    func archivedGroupKeepsContentsReachable() {
        let rootID = UUID()
        let childID = UUID()
        let project = makeProject(name: "Ativo", module: .repeatable, day: 3)
        let archivedRoot = ProjectOrganizationNode(
            id: rootID,
            module: .repeatable,
            parentID: nil,
            name: "Catedral",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            isArchived: true
        )
        let activeChild = makeOrganizationNode(
            id: childID,
            parentID: rootID,
            name: "Esculturas",
            day: 2
        )
        let model = CameraeNextProjectOrganizationModel(
            projects: [project],
            module: .repeatable,
            organization: .init(
                nodes: [archivedRoot, activeChild],
                memberships: [.init(projectID: project.id, nodeID: childID)]
            ),
            filter: .archived
        )

        #expect(model.rootNodes.map(\.id) == [rootID])
        #expect(model.childNodes(of: rootID).map(\.id) == [childID])
        #expect(model.directProjects(in: childID).map(\.id) == [project.id])
        #expect(model.ungroupedProjects.isEmpty)
    }

    @Test("project navigation identity survives metadata and last-opened updates")
    func stableProjectNavigationIdentity() {
        let projectID = UUID()
        let beforeOpening = makeProject(
            id: projectID,
            name: "Repeatable",
            module: .repeatable,
            day: 1,
            lastOpenedDay: 1,
            mediaCount: 1
        )
        let afterOpening = makeProject(
            id: projectID,
            name: "Repeatable",
            module: .repeatable,
            day: 1,
            lastOpenedDay: 2,
            mediaCount: 2
        )

        #expect(beforeOpening != afterOpening)
        #expect(ProjectNavigationRoute(project: beforeOpening) == ProjectNavigationRoute(project: afterOpening))
    }

    private func makeProject(
        id: UUID = UUID(),
        name: String,
        module: CameraModule,
        day: Int,
        lastOpenedDay: Int? = nil,
        archived: Bool = false,
        mediaCount: Int = 0,
        sequenceNumber: Int? = nil
    ) -> CameraProject {
        let date = Date(timeIntervalSince1970: TimeInterval(day * 86_400))
        let lastOpenedAt = Date(
            timeIntervalSince1970: TimeInterval((lastOpenedDay ?? day) * 86_400)
        )
        let record = ProjectRecord(
            id: id,
            module: module.coreValue,
            name: name,
            directoryURL: URL(fileURLWithPath: "/tmp/\(name)"),
            createdAt: date,
            updatedAt: date,
            lastOpenedAt: lastOpenedAt,
            isArchived: archived,
            sequenceNumber: sequenceNumber
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

    private func makeOrganizationNode(
        id: UUID,
        parentID: UUID?,
        name: String,
        day: Int
    ) -> ProjectOrganizationNode {
        let date = Date(timeIntervalSince1970: TimeInterval(day * 86_400))
        return ProjectOrganizationNode(
            id: id,
            module: .repeatable,
            parentID: parentID,
            name: name,
            createdAt: date,
            updatedAt: date,
            isArchived: false
        )
    }

    private func makeSessionSummary(
        kind: RepeatableCaptureKind,
        purpose: TimelapseSession.Purpose = .capture,
        date: Date,
        lens: RepeatableCameraLens? = nil,
        zoom: Double? = nil
    ) -> TimelapseSessionSummary {
        let id = UUID()
        let session = TimelapseSession(
            id: id,
            projectID: UUID(),
            module: .repeatable,
            captureKind: kind,
            purpose: purpose,
            referenceMotion: nil,
            referenceGeoPose: nil,
            referenceOrientation: nil,
            cameraLens: lens,
            cameraZoomFactor: zoom,
            name: id.uuidString,
            directoryURL: URL(fileURLWithPath: "/tmp/\(id.uuidString)"),
            createdAt: date
        )
        return TimelapseSessionSummary(
            session: session,
            captureKind: kind,
            frameCount: 1,
            captureDuration: nil,
            referenceFrameURL: URL(fileURLWithPath: "/tmp/frame.jpg"),
            videoURL: kind == .video ? URL(fileURLWithPath: "/tmp/video.mov") : nil,
            videoClipURL: nil,
            alignedVideoURL: nil,
            renderedAstroVideoURL: nil,
            isAstroProcessed: false,
            hasRenderedOutput: kind == .video
        )
    }
}

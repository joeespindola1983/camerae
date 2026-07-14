import Foundation
import Testing
@testable import CameraeCore

@Suite("Edit project domain")
struct EditProjectDomainTests {
    @Test("Edit project documents round-trip without absolute source URLs")
    func documentRoundTrip() throws {
        let projectID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let itemID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        let reference = Self.reference()
        let document = EditProjectDocument(
            projectID: projectID,
            canvas: .portrait9x16,
            items: [EditTimelineItem(id: itemID, asset: reference, addedAt: Self.date)],
            updatedAt: Self.date,
            lastExportRelativePath: "Exports/portfolio.mp4"
        )

        let codec = EditProjectCodec()
        let data = try codec.encode(document)
        let decoded = try codec.decode(data)

        #expect(decoded == document)
        #expect(decoded.schemaVersion == 1)
        #expect(String(decoding: data, as: UTF8.self).contains("file://") == false)
    }

    @Test("media identity is deterministic from stable source fields")
    func deterministicMediaIdentity() {
        let first = MediaAssetReference(
            projectID: Self.sourceProjectID,
            sessionID: Self.sourceSessionID,
            kind: .repeatableTimelapse,
            relativePath: "Sessions/session_1/timelapse.mp4"
        )
        let second = MediaAssetReference(
            projectID: Self.sourceProjectID,
            sessionID: Self.sourceSessionID,
            kind: .repeatableTimelapse,
            relativePath: "Sessions/session_1/timelapse.mp4"
        )

        #expect(first.id == second.id)
        #expect(first.id.rawValue.contains(Self.sourceProjectID.uuidString.lowercased()))
    }

    @Test("unsupported edit schemas are rejected")
    func unsupportedSchemaIsRejected() {
        let json = #"{"schemaVersion":99,"projectID":"10000000-0000-0000-0000-000000000001","canvas":"landscape16x9","items":[],"updatedAt":"2026-07-14T12:00:00Z"}"#

        #expect(throws: EditProjectCodecError.unsupportedSchema(99)) {
            try EditProjectCodec().decode(Data(json.utf8))
        }
    }

    @Test("media filters combine origin, kind, and project without IO")
    func mediaFiltersCombine() {
        let repeatableTimelapse = Self.descriptor(
            projectID: Self.sourceProjectID,
            module: .repeatable,
            kind: .repeatableTimelapse,
            path: "Sessions/a/timelapse.mp4"
        )
        let repeatableVideo = Self.descriptor(
            projectID: Self.sourceProjectID,
            module: .repeatable,
            kind: .repeatableVideo,
            path: "Sessions/a/video.mov"
        )
        let astro = Self.descriptor(
            projectID: UUID(uuidString: "20000000-0000-0000-0000-000000000099")!,
            module: .astrophotography,
            kind: .astroTimelapse,
            path: "Sessions/b/Astro Renders/r/astro.mp4"
        )
        let snapshot = MediaLibrarySnapshot(assets: [astro, repeatableVideo, repeatableTimelapse])

        let repeatableTimelapses = snapshot.filtered(by: MediaLibraryFilter(
            origin: .module(.repeatable),
            kind: .timelapse,
            projectID: nil
        ))
        let projectVideos = snapshot.filtered(by: MediaLibraryFilter(
            origin: .all,
            kind: .recordedVideo,
            projectID: Self.sourceProjectID
        ))

        #expect(repeatableTimelapses.map { $0.reference.id } == [repeatableTimelapse.reference.id])
        #expect(projectVideos.map { $0.reference.id } == [repeatableVideo.reference.id])
    }

    private static func reference() -> MediaAssetReference {
        MediaAssetReference(
            projectID: sourceProjectID,
            sessionID: sourceSessionID,
            kind: .repeatableTimelapse,
            relativePath: "Sessions/session_1/timelapse.mp4"
        )
    }

    private static func descriptor(
        projectID: UUID,
        module: ProjectModule,
        kind: MediaSourceKind,
        path: String
    ) -> MediaAssetDescriptor {
        MediaAssetDescriptor(
            reference: MediaAssetReference(
                projectID: projectID,
                sessionID: sourceSessionID,
                kind: kind,
                relativePath: path
            ),
            sourceModule: module,
            projectName: "Project",
            sessionName: "Session",
            sourceCreatedAt: date,
            duration: 2,
            pixelWidth: 1920,
            pixelHeight: 1080,
            hasAudio: kind == .repeatableVideo,
            fileSize: 100,
            isAvailable: true
        )
    }

    fileprivate static let date = Date(timeIntervalSince1970: 1_752_494_400)
    fileprivate static let sourceProjectID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    fileprivate static let sourceSessionID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
}

@Suite("Edit project catalog component")
struct EditProjectCatalogComponentTests {
    @Test("append, repeat, reorder, remove, and reload preserve the timeline")
    func timelinePersists() async throws {
        let library = try EditTemporaryLibrary()
        defer { library.remove() }
        let firstItemID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let secondItemID = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
        let catalog = EditProjectCatalog(
            project: library.project,
            dateProvider: FixedDateProvider(EditProjectDomainTests.date),
            idProvider: FixedIDProvider([firstItemID, secondItemID])
        )
        let reference = MediaAssetReference(
            projectID: EditProjectDomainTests.sourceProjectID,
            sessionID: EditProjectDomainTests.sourceSessionID,
            kind: .repeatableTimelapse,
            relativePath: "Sessions/session_1/timelapse.mp4"
        )

        let empty = try await catalog.loadOrCreate()
        #expect(empty.items.isEmpty)
        let appended = try await catalog.append([reference, reference])
        #expect(appended.items.map(\.id) == [firstItemID, secondItemID])
        #expect(appended.items.map(\.asset.id) == [reference.id, reference.id])

        let moved = try await catalog.moveItem(id: secondItemID, to: 0)
        #expect(moved.items.map(\.id) == [secondItemID, firstItemID])
        let removed = try await catalog.removeItem(id: firstItemID)
        #expect(removed.items.map(\.id) == [secondItemID])

        let reloaded = try await EditProjectCatalog(project: library.project).loadOrCreate()
        #expect(reloaded == removed)
    }

    @Test("invalid JSON is reported and never replaced with an empty project")
    func invalidJSONIsPreserved() async throws {
        let library = try EditTemporaryLibrary()
        defer { library.remove() }
        let manifestURL = library.project.directoryURL.appendingPathComponent("edit.json")
        let invalid = Data("not-json".utf8)
        try invalid.write(to: manifestURL)

        do {
            _ = try await EditProjectCatalog(project: library.project).loadOrCreate()
            Issue.record("Expected invalid JSON to throw")
        } catch {
            #expect((try? Data(contentsOf: manifestURL)) == invalid)
        }
    }

    @Test("catalog rejects a project from another module")
    func rejectsNonEditProject() async throws {
        let library = try EditTemporaryLibrary(module: .repeatable)
        defer { library.remove() }

        await #expect(throws: EditProjectCatalogError.wrongProjectModule) {
            _ = try await EditProjectCatalog(project: library.project).loadOrCreate()
        }
    }
}

private final class EditTemporaryLibrary: @unchecked Sendable {
    let root: URL
    let project: ProjectRecord

    init(module: ProjectModule = .edit) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeEditTests-\(UUID().uuidString)", isDirectory: true)
        let projectURL = root.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        project = ProjectRecord(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            module: module,
            name: "Portfolio",
            directoryURL: projectURL,
            createdAt: EditProjectDomainTests.date,
            updatedAt: EditProjectDomainTests.date,
            lastOpenedAt: nil,
            isArchived: false
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

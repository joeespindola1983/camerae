import CameraeCore
import Foundation
import Testing
@testable import CameraeMedia

@Suite("Produced media library catalog")
struct MediaLibraryCatalogTests {
    @Test("discovers every produced media kind and every Astro render")
    func discoversProducedMedia() async throws {
        let library = try MediaTemporaryLibrary()
        defer { library.remove() }
        let fixture = try await library.makeFixture()
        let probe = ProbeStub()
        let catalog = MediaLibraryCatalog(rootDirectory: library.root, probe: probe)

        let snapshot = try await catalog.load()

        #expect(snapshot.assets.count == 4)
        #expect(snapshot.assets.filter { $0.reference.kind == .repeatableTimelapse }.count == 1)
        #expect(snapshot.assets.filter { $0.reference.kind == .repeatableVideo }.count == 1)
        #expect(snapshot.assets.filter { $0.reference.kind == .astroTimelapse }.count == 2)
        #expect(snapshot.assets.allSatisfy { $0.isAvailable })
        #expect(snapshot.assets.contains { $0.reference.projectID == fixture.archivedProjectID })
        #expect(snapshot.assets.contains { $0.reference.projectID == fixture.editProjectID } == false)
        #expect(await probe.callCount() == 4)
    }

    @Test("zero-byte outputs are ignored before probing")
    func ignoresEmptyOutputs() async throws {
        let library = try MediaTemporaryLibrary()
        defer { library.remove() }
        _ = try await library.makeFixture(includeEmptyOutput: true)
        let probe = ProbeStub()

        let snapshot = try await MediaLibraryCatalog(rootDirectory: library.root, probe: probe).load()

        #expect(snapshot.assets.count == 4)
        #expect(await probe.callCount() == 4)
    }

    @Test("resolution rejects references that escape the source project")
    func rejectsUnsafeReference() async throws {
        let library = try MediaTemporaryLibrary()
        defer { library.remove() }
        let fixture = try await library.makeFixture()
        let catalog = MediaLibraryCatalog(rootDirectory: library.root, probe: ProbeStub())
        _ = try await catalog.load()
        let unsafe = MediaAssetReference(
            projectID: fixture.archivedProjectID,
            sessionID: fixture.repeatableSessionID,
            kind: .repeatableVideo,
            relativePath: "../outside.mov"
        )

        #expect(try await catalog.resolve(unsafe) == nil)
    }
}

private actor ProbeStub: MediaAssetProbing {
    private var calls = 0

    func probe(url: URL) async throws -> MediaAssetTechnicalMetadata {
        calls += 1
        return MediaAssetTechnicalMetadata(
            duration: 2,
            pixelWidth: url.pathExtension == "mov" ? 1080 : 1920,
            pixelHeight: url.pathExtension == "mov" ? 1920 : 1080,
            hasAudio: url.pathExtension == "mov",
            fileSize: 1
        )
    }

    func callCount() -> Int { calls }
}

private final class MediaTemporaryLibrary: @unchecked Sendable {
    struct Fixture {
        let archivedProjectID: UUID
        let editProjectID: UUID
        let repeatableSessionID: UUID
    }

    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeMediaLibraryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func makeFixture(includeEmptyOutput: Bool = false) async throws -> Fixture {
        let projectIDs = FixedIDProvider([
            UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
            UUID(uuidString: "40000000-0000-0000-0000-000000000002")!,
            UUID(uuidString: "40000000-0000-0000-0000-000000000003")!
        ])
        let projects = ProjectCatalog(
            rootDirectory: root,
            dateProvider: FixedDateProvider(Date(timeIntervalSince1970: 1_700_000_000)),
            idProvider: projectIDs
        )
        let repeatable = try await projects.createProject(module: .repeatable, name: "Repeatable")
        let astro = try await projects.createProject(module: .astrophotography, name: "Astro")
        let edit = try await projects.createProject(module: .edit, name: "Edit")
        _ = try await projects.setArchived(repeatable.id, isArchived: true)

        let repeatableSession = try await SessionCatalog(
            project: repeatable,
            idProvider: FixedIDProvider([UUID(uuidString: "50000000-0000-0000-0000-000000000001")!])
        ).createSession(captureKind: .timelapse)
        try Data([1]).write(to: repeatableSession.directoryURL.appendingPathComponent("timelapse.mp4"))
        try Data([2]).write(to: repeatableSession.directoryURL.appendingPathComponent("video.mov"))

        let astroSession = try await SessionCatalog(
            project: astro,
            idProvider: FixedIDProvider([UUID(uuidString: "50000000-0000-0000-0000-000000000002")!])
        ).createSession(captureKind: .timelapse)
        for name in ["render_a", "render_b"] {
            let render = astroSession.directoryURL
                .appendingPathComponent("Astro Renders", isDirectory: true)
                .appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: render, withIntermediateDirectories: true)
            try Data([3]).write(to: render.appendingPathComponent("astro.mp4"))
        }
        if includeEmptyOutput {
            let emptyRender = astroSession.directoryURL
                .appendingPathComponent("Astro Renders", isDirectory: true)
                .appendingPathComponent("empty", isDirectory: true)
            try FileManager.default.createDirectory(at: emptyRender, withIntermediateDirectories: true)
            try Data().write(to: emptyRender.appendingPathComponent("astro.mp4"))
        }

        let fakeSession = edit.directoryURL
            .appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent("session_fake", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeSession, withIntermediateDirectories: true)
        try Data([4]).write(to: fakeSession.appendingPathComponent("video.mov"))

        return Fixture(
            archivedProjectID: repeatable.id,
            editProjectID: edit.id,
            repeatableSessionID: repeatableSession.id
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

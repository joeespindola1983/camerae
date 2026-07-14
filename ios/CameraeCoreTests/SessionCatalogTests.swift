import Foundation
import Testing
@testable import CameraeCore

@Suite("Session manifest compatibility")
struct SessionManifestCompatibilityTests {
    @Test("decodes an unversioned session manifest")
    func decodesLegacySession() throws {
        let directory = URL(fileURLWithPath: "/tmp/session", isDirectory: true)
        let document = try SessionManifestCodec().decode(Data(Self.legacyJSON.utf8), directoryURL: directory)

        #expect(document.schemaVersion == 2)
        #expect(document.session.id == UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        #expect(document.session.projectID == UUID(uuidString: "55555555-5555-5555-5555-555555555555"))
        #expect(document.session.captureKind == .timelapse)
        #expect(document.session.referenceMotion == SessionMotion(x: 1, y: 2, z: 3))
        #expect(document.session.referenceGeoPose?.latitude == -23.5)
        #expect(document.session.referenceOrientation == "landscapeRight")
        #expect(document.session.cameraLens == "wide")
        #expect(document.summary == nil)

        let migrated = try SessionManifestCodec().decode(
            SessionManifestCodec().encode(document),
            directoryURL: directory
        )
        #expect(migrated.session.referenceMotion == document.session.referenceMotion)
        #expect(migrated.session.referenceGeoPose == document.session.referenceGeoPose)
        #expect(migrated.session.referenceOrientation == document.session.referenceOrientation)
        #expect(migrated.session.cameraLens == document.session.cameraLens)
    }

    private static let legacyJSON = #"""
    {
      "id": "44444444-4444-4444-4444-444444444444",
      "projectId": "55555555-5555-5555-5555-555555555555",
      "module": "repeatable",
      "captureKind": "timelapse",
      "name": "session_2025-01-01_12-00-00",
      "createdAt": "2025-01-01T12:00:00Z",
      "referenceMotion": { "x": 1, "y": 2, "z": 3 },
      "referenceGeoPose": {
        "latitude": -23.5,
        "longitude": -46.6,
        "horizontalAccuracy": 4,
        "heading": 90,
        "timestamp": "2025-01-01T12:00:00Z"
      },
      "referenceOrientation": "landscapeRight",
      "cameraLens": "wide"
    }
    """#
}

@Suite("Session catalog component")
struct SessionCatalogComponentTests {
    @Test("capture checkpoints and finalization survive a new catalog instance")
    func checkpointAndFinalize() async throws {
        let library = try SessionTemporaryLibrary()
        defer { library.remove() }
        let project = library.project
        let ids = FixedIDProvider([UUID(uuidString: "66666666-6666-6666-6666-666666666666")!])
        let captureDate = Date(timeIntervalSince1970: 1_700_000_100)
        let catalog = SessionCatalog(
            project: project,
            dateProvider: FixedDateProvider(captureDate),
            idProvider: ids
        )

        let session = try await catalog.createSession(captureKind: .timelapse)
        try await catalog.beginCapture(sessionID: session.id)
        _ = try await catalog.saveFrame(Data([1, 2, 3]), sessionID: session.id, index: 1)
        _ = try await catalog.saveFrame(Data([4, 5]), sessionID: session.id, index: 2)
        try await catalog.checkpoint(sessionID: session.id)
        try await catalog.finishCapture(sessionID: session.id)

        let reloaded = SessionCatalog(project: project)
        let summaries = try await reloaded.loadSummaries()

        #expect(summaries.count == 1)
        #expect(summaries[0].frameSummary.count == 2)
        #expect(summaries[0].frameSummary.firstFileName == "frame_000001.jpg")
        #expect(summaries[0].frameSummary.lastFileName == "frame_000002.jpg")
        #expect(summaries[0].frameSummary.knownBytes == 5)
        #expect(summaries[0].frameSummary.captureDuration == 0)
        #expect(summaries[0].inventoryState == .clean)
    }

    @Test("a dirty session is repaired from its frame directory")
    func dirtySessionRepairs() async throws {
        let library = try SessionTemporaryLibrary()
        defer { library.remove() }
        let catalog = SessionCatalog(project: library.project)
        let session = try await catalog.createSession(captureKind: .photo)
        try await catalog.beginCapture(sessionID: session.id)
        _ = try await catalog.saveFrame(Data([1]), sessionID: session.id, index: 1)
        try await catalog.checkpoint(sessionID: session.id)
        try Data([2, 3]).write(to: session.directoryURL.appendingPathComponent("frame_000002.jpg"))
        try Data([4, 5, 6]).write(to: session.directoryURL.appendingPathComponent("frame_000003.jpg"))

        let reloaded = SessionCatalog(project: library.project)
        let summaries = try await reloaded.loadSummaries()

        #expect(summaries[0].frameSummary.count == 3)
        #expect(summaries[0].frameSummary.knownBytes == 6)
        #expect(summaries[0].frameSummary.nextFrameIndex == 4)
        #expect(summaries[0].inventoryState == .clean)
    }

    @Test("repair characterizes every existing rendered video output")
    func repairFindsExistingVideoOutputs() async throws {
        let library = try SessionTemporaryLibrary()
        defer { library.remove() }
        let catalog = SessionCatalog(project: library.project)
        let session = try await catalog.createSession(captureKind: .timelapse)
        try await catalog.beginCapture(sessionID: session.id)

        try Data([1]).write(to: session.directoryURL.appendingPathComponent("timelapse.mp4"))
        try Data([2]).write(to: session.directoryURL.appendingPathComponent("video.mov"))
        let render = session.directoryURL
            .appendingPathComponent("Astro Renders", isDirectory: true)
            .appendingPathComponent("render_001", isDirectory: true)
        try FileManager.default.createDirectory(at: render, withIntermediateDirectories: true)
        try Data([3]).write(to: render.appendingPathComponent("astro.mp4"))

        let summary = try await SessionCatalog(project: library.project).loadSummaries().first

        #expect(summary?.videoSummary?.videoFileName == "timelapse.mp4")
        #expect(summary?.videoSummary?.clipFileName == "video.mov")
        #expect(summary?.astroSummary?.hasRenderedClip == true)
    }

    @Test("HEIC frames keep their format and survive inventory repair")
    func heicFramesRepair() async throws {
        let library = try SessionTemporaryLibrary()
        defer { library.remove() }
        let catalog = SessionCatalog(project: library.project)
        let session = try await catalog.createSession(captureKind: .timelapse)
        try await catalog.beginCapture(sessionID: session.id)

        let first = try await catalog.saveFrame(
            Data([1, 2]),
            sessionID: session.id,
            index: 1,
            format: .heic
        )
        try await catalog.checkpoint(sessionID: session.id)
        try Data([3, 4, 5]).write(
            to: session.directoryURL.appendingPathComponent("frame_000002.heic")
        )

        let summary = try await SessionCatalog(project: library.project).loadSummaries().first

        #expect(first.pathExtension == "heic")
        #expect(summary?.frameSummary.count == 2)
        #expect(summary?.frameSummary.knownBytes == 5)
        #expect(summary?.frameSummary.nextFrameIndex == 3)
    }
}

private final class SessionTemporaryLibrary: @unchecked Sendable {
    let url: URL
    let project: ProjectRecord

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeSessionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        project = ProjectRecord(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            module: .repeatable,
            name: "Test",
            directoryURL: url.appendingPathComponent("Project", isDirectory: true),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastOpenedAt: nil,
            isArchived: false
        )
        try FileManager.default.createDirectory(at: project.directoryURL, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

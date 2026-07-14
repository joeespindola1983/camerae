import Foundation
import Testing
@testable import CameraeCore

@Suite("Project manifest compatibility")
struct ProjectManifestCompatibilityTests {
    @Test("decodes the current unversioned project manifest as legacy v2")
    func decodesLegacyManifest() throws {
        let data = Data(Self.legacyJSON.utf8)
        let document = try ProjectManifestCodec().decode(data)

        #expect(document.schemaVersion == 2)
        #expect(document.project.id == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        #expect(document.project.module == .repeatable)
        #expect(document.project.name == "Legacy project")
        #expect(document.project.isArchived == false)
        #expect(document.summary == nil)
    }

    @Test("v3 manifest round-trips its summary")
    func v3RoundTrip() throws {
        let project = ProjectRecord(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            module: .astrophotography,
            name: "Orion",
            directoryURL: URL(fileURLWithPath: "/tmp/orion", isDirectory: true),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            lastOpenedAt: nil,
            isArchived: false
        )
        let summary = ProjectSummary(
            sessionCount: 4,
            mediaCount: 120,
            referenceThumbnailKey: "frame-1",
            latestSessionAt: Date(timeIntervalSince1970: 1_700_000_050),
            totalKnownBytes: 42_000,
            inventoryState: .clean,
            generation: 7
        )
        let codec = ProjectManifestCodec()

        let data = try codec.encode(ProjectManifestDocument(project: project, summary: summary))
        let decoded = try codec.decode(data, directoryURL: project.directoryURL)

        #expect(decoded.schemaVersion == 3)
        #expect(decoded.project == project)
        #expect(decoded.summary == summary)
    }

    private static let legacyJSON = #"""
    {
      "id": "11111111-1111-1111-1111-111111111111",
      "module": "repeatable",
      "name": "Legacy project",
      "createdAt": "2025-01-01T12:00:00Z",
      "updatedAt": "2025-01-02T12:00:00Z",
      "lastOpenedAt": "2025-01-03T12:00:00Z",
      "isArchived": false
    }
    """#
}

@Suite("Project catalog component")
struct ProjectCatalogComponentTests {
    @Test("create, persist, and reload uses the real temporary filesystem")
    func createPersistReload() async throws {
        let library = try TemporaryLibrary()
        defer { library.remove() }
        let clock = FixedDateProvider(Date(timeIntervalSince1970: 1_700_000_000))
        let ids = FixedIDProvider([
            UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        ])

        let catalog = ProjectCatalog(rootDirectory: library.url, dateProvider: clock, idProvider: ids)
        let created = try await catalog.createProject(module: .repeatable, name: "Facade")
        let reloaded = ProjectCatalog(rootDirectory: library.url)
        let snapshot = try await reloaded.load()

        #expect(snapshot.projects == [created])
        #expect(snapshot.summary(for: created.id) == .empty)
        #expect(FileManager.default.fileExists(atPath: created.directoryURL.appendingPathComponent("project.json").path))
    }

    @Test("updated summaries survive the derived index and manifest")
    func updateSummaryPersists() async throws {
        let library = try TemporaryLibrary()
        defer { library.remove() }
        let catalog = ProjectCatalog(rootDirectory: library.url)
        let project = try await catalog.createProject(module: .repeatable, name: "Indexed")
        let summary = ProjectSummary(
            sessionCount: 2,
            mediaCount: 30,
            referenceThumbnailKey: "Sessions/session-1/frame_000001.jpg",
            latestSessionAt: Date(timeIntervalSince1970: 1_700_000_000),
            totalKnownBytes: 9_000,
            inventoryState: .clean,
            generation: 1
        )

        try await catalog.updateSummary(summary, projectID: project.id)
        let reloaded = ProjectCatalog(rootDirectory: library.url)
        let snapshot = try await reloaded.load()

        #expect(snapshot.summary(for: project.id) == summary)
    }

    @Test("a corrupt derived index rebuilds from valid manifests")
    func corruptIndexRebuilds() async throws {
        let library = try TemporaryLibrary()
        defer { library.remove() }
        let catalog = ProjectCatalog(rootDirectory: library.url)
        _ = try await catalog.createProject(module: .astrophotography, name: "Recovery")
        try Data("not-json".utf8).write(to: catalog.indexURL, options: .atomic)

        let reloaded = ProjectCatalog(rootDirectory: library.url)
        let snapshot = try await reloaded.load()

        #expect(snapshot.projects.count == 1)
        #expect(snapshot.projects.first?.name == "Recovery")
        #expect(snapshot.source == .rebuilt)
    }

    @Test("a rebuild preserves both existing capture modules")
    func rebuildPreservesExistingModules() async throws {
        let library = try TemporaryLibrary()
        defer { library.remove() }
        let catalog = ProjectCatalog(rootDirectory: library.url)
        let repeatable = try await catalog.createProject(module: .repeatable, name: "Facade")
        let astro = try await catalog.createProject(module: .astrophotography, name: "Orion")
        try Data("invalid-index".utf8).write(to: catalog.indexURL, options: .atomic)

        let rebuilt = try await ProjectCatalog(rootDirectory: library.url).load()

        #expect(Set(rebuilt.projects.map(\.id)) == Set([repeatable.id, astro.id]))
        #expect(Set(rebuilt.projects.map(\.module)) == Set([.repeatable, .astrophotography]))
        #expect(rebuilt.source == .rebuilt)
    }
}

private final class TemporaryLibrary: @unchecked Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

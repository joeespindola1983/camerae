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

    @Test("v3 manifest upgrades to v5 while preserving its summary")
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

        #expect(decoded.schemaVersion == 5)
        #expect(decoded.project == project)
        #expect(decoded.summary == summary)
    }

    @Test("future project schemas are rejected without reinterpretation")
    func rejectsFutureProjectSchema() {
        let json = Self.legacyJSON.replacingOccurrences(
            of: "{",
            with: "{ \"schemaVersion\": 99,",
            options: [],
            range: Self.legacyJSON.range(of: "{")
        )

        #expect(throws: ManifestCompatibilityError.unsupportedProjectSchema(99)) {
            try ProjectManifestCodec().decode(Data(json.utf8))
        }
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

    @Test("deleting a project removes its directory and catalog entry")
    func deleteProject() async throws {
        let library = try TemporaryLibrary()
        defer { library.remove() }
        let catalog = ProjectCatalog(rootDirectory: library.url)
        let project = try await catalog.createProject(module: .astrophotography, name: "Temporary")

        let removed = try await catalog.deleteProject(project.id)
        let reloaded = try await ProjectCatalog(rootDirectory: library.url).load()

        #expect(removed)
        #expect(reloaded.projects.isEmpty)
        #expect(reloaded.summary(for: project.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: project.directoryURL.path))
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

@Suite("Project storage inventory")
struct ProjectStorageInventoryTests {
    @Test("scanner classifies originals, processed files, final artifacts, cache and exports")
    func classifiesProjectStorage() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeStorageTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent("Sessions/session_1", isDirectory: true)
        let astro = session.appendingPathComponent("Astro Frames", isDirectory: true)
        let preview = session.appendingPathComponent("Preview Frames", isDirectory: true)
        let exports = root.appendingPathComponent("Exports", isDirectory: true)
        for directory in [session, astro, preview, exports] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data(repeating: 1, count: 3).write(to: session.appendingPathComponent("frame_000001.heic"))
        try Data(repeating: 1, count: 2).write(to: session.appendingPathComponent("timelapse.mp4"))
        try Data(repeating: 1, count: 4).write(to: astro.appendingPathComponent("astro_frame_000001.jpg"))
        try Data(repeating: 1, count: 5).write(to: preview.appendingPathComponent("preview.jpg"))
        try Data(repeating: 1, count: 6).write(to: exports.appendingPathComponent("originals.zip"))

        let result = try ProjectStorageScanner().scan(projectDirectory: root)

        #expect(result.originalBytes == 3)
        #expect(result.processedBytes == 4)
        #expect(result.finalArtifactBytes == 2)
        #expect(result.cacheBytes == 5)
        #expect(result.exportBytes == 6)
        #expect(result.totalBytes == 20)
    }
}

@Suite("Atomic artifact publication")
struct AtomicArtifactPublicationTests {
    @Test("failed validation preserves the previous final artifact")
    func failedValidationPreservesFinal() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeArtifactTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let final = root.appendingPathComponent("final.mp4")
        let temporary = root.appendingPathComponent("temporary.mp4")
        try Data("previous".utf8).write(to: final)
        try Data("invalid".utf8).write(to: temporary)

        #expect(throws: ArtifactFixtureError.invalid) {
            try AtomicArtifactPublisher().publish(temporaryURL: temporary, destinationURL: final) { _ in
                throw ArtifactFixtureError.invalid
            }
        }

        #expect(try Data(contentsOf: final) == Data("previous".utf8))
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
    }

    @Test("validated artifact atomically replaces the previous final")
    func validArtifactReplacesFinal() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeArtifactSuccess-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let final = root.appendingPathComponent("final.mp4")
        let temporary = root.appendingPathComponent("temporary.mp4")
        try Data("previous".utf8).write(to: final)
        try Data("validated".utf8).write(to: temporary)

        try AtomicArtifactPublisher().publish(temporaryURL: temporary, destinationURL: final) { url in
            #expect((try? Data(contentsOf: url)) == Data("validated".utf8))
        }

        #expect(try Data(contentsOf: final) == Data("validated".utf8))
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
    }
}

private enum ArtifactFixtureError: Error {
    case invalid
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

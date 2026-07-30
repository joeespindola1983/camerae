import Foundation
import Testing
@testable import CameraeCore

@Suite("Project organization document")
struct ProjectOrganizationDocumentTests {
    @Test("current documents round-trip without losing hierarchy or membership")
    func currentRoundTrip() throws {
        let rootID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let childID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        let projectID = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let document = ProjectOrganizationDocument(
            nodes: [
                .init(
                    id: rootID,
                    module: .repeatable,
                    parentID: nil,
                    name: "Catedral TV",
                    createdAt: date,
                    updatedAt: date,
                    isArchived: false
                ),
                .init(
                    id: childID,
                    module: .repeatable,
                    parentID: rootID,
                    name: "Esculturas",
                    createdAt: date,
                    updatedAt: date,
                    isArchived: false
                )
            ],
            memberships: [.init(projectID: projectID, nodeID: childID)]
        )

        let codec = ProjectOrganizationCodec()
        let decoded = try codec.decode(codec.encode(document))

        #expect(decoded == document)
        #expect(decoded.schemaVersion == ProjectOrganizationDocument.currentSchemaVersion)
    }

    @Test("future documents fail closed")
    func futureSchemaFailsClosed() {
        let json = #"{"schemaVersion":99,"nodes":[],"memberships":[]}"#

        #expect(throws: ProjectOrganizationError.unsupportedSchema(99)) {
            try ProjectOrganizationCodec().decode(Data(json.utf8))
        }
    }

    @Test("normalization is idempotent and removes orphaned state")
    func normalizationIsIdempotent() {
        let validProject = Self.project(id: UUID(), module: .repeatable)
        let orphanProjectID = UUID()
        let root = ProjectOrganizationNode(
            id: UUID(),
            module: .repeatable,
            parentID: nil,
            name: "Centro",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            isArchived: false
        )
        let orphanChild = ProjectOrganizationNode(
            id: UUID(),
            module: .repeatable,
            parentID: UUID(),
            name: "Órfão",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            isArchived: false
        )
        let validChild = ProjectOrganizationNode(
            id: UUID(),
            module: .repeatable,
            parentID: root.id,
            name: "Detalhes",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            isArchived: false
        )
        let input = ProjectOrganizationDocument(
            nodes: [validChild, orphanChild, root],
            memberships: [
                .init(projectID: validProject.id, nodeID: validChild.id),
                .init(projectID: orphanProjectID, nodeID: root.id)
            ]
        )

        let once = ProjectOrganizationResolver.normalize(input, projects: [validProject])
        let twice = ProjectOrganizationResolver.normalize(once, projects: [validProject])

        #expect(once == twice)
        #expect(once.nodes == [root, validChild])
        #expect(once.memberships == [.init(projectID: validProject.id, nodeID: validChild.id)])
    }

    private static func project(id: UUID, module: ProjectModule) -> ProjectRecord {
        ProjectRecord(
            id: id,
            module: module,
            name: "Projeto",
            directoryURL: URL(fileURLWithPath: "/tmp/\(id.uuidString)", isDirectory: true),
            createdAt: .distantPast,
            updatedAt: .distantPast,
            lastOpenedAt: nil,
            isArchived: false
        )
    }
}

@Suite("Project organization catalog")
struct ProjectOrganizationCatalogTests {
    @Test("a missing organization file loads as a current empty document")
    func missingFileIsEmpty() async throws {
        let library = try OrganizationTemporaryLibrary()
        defer { library.remove() }

        let snapshot = try await ProjectOrganizationCatalog(rootDirectory: library.url).load(projects: [])

        #expect(snapshot.nodes.isEmpty)
        #expect(snapshot.memberships.isEmpty)
    }

    @Test("groups support exactly one subgroup level")
    func hierarchyStopsAtSubgroups() async throws {
        let library = try OrganizationTemporaryLibrary()
        defer { library.remove() }
        let ids = FixedIDProvider([
            UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
            UUID(uuidString: "20000000-0000-0000-0000-000000000003")!
        ])
        let catalog = ProjectOrganizationCatalog(rootDirectory: library.url, idProvider: ids)
        let root = try await catalog.createNode(module: .repeatable, parentID: nil, name: "Catedral")
        let child = try await catalog.createNode(
            module: .repeatable,
            parentID: root.id,
            name: "Esculturas"
        )

        await #expect(throws: ProjectOrganizationError.hierarchyTooDeep) {
            try await catalog.createNode(
                module: .repeatable,
                parentID: child.id,
                name: "Detalhes"
            )
        }
    }

    @Test("membership persists and deleting organization preserves the project directory")
    func deletionPreservesProject() async throws {
        let library = try OrganizationTemporaryLibrary()
        defer { library.remove() }
        let projectDirectory = library.url.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
        let project = ProjectRecord(
            id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
            module: .repeatable,
            name: "Fachada",
            directoryURL: projectDirectory,
            createdAt: .distantPast,
            updatedAt: .distantPast,
            lastOpenedAt: nil,
            isArchived: false
        )
        let ids = FixedIDProvider([
            UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
            UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
        ])
        let catalog = ProjectOrganizationCatalog(rootDirectory: library.url, idProvider: ids)
        let root = try await catalog.createNode(module: .repeatable, parentID: nil, name: "Catedral")
        let subgroup = try await catalog.createNode(
            module: .repeatable,
            parentID: root.id,
            name: "Vídeos"
        )
        try await catalog.moveProject(project, to: subgroup.id)

        let reloaded = ProjectOrganizationCatalog(rootDirectory: library.url)
        let beforeDelete = try await reloaded.load(projects: [project])
        #expect(beforeDelete.nodeID(for: project.id) == subgroup.id)

        try await reloaded.deleteNode(root.id)
        let afterDelete = try await reloaded.load(projects: [project])

        #expect(afterDelete.nodes.isEmpty)
        #expect(afterDelete.nodeID(for: project.id) == nil)
        #expect(FileManager.default.fileExists(atPath: projectDirectory.path))
    }

    @Test("a project cannot move into an organization from another module")
    func rejectsCrossModuleMembership() async throws {
        let library = try OrganizationTemporaryLibrary()
        defer { library.remove() }
        let project = ProjectRecord(
            id: UUID(),
            module: .repeatable,
            name: "Repeatable",
            directoryURL: library.url.appendingPathComponent("repeatable"),
            createdAt: .distantPast,
            updatedAt: .distantPast,
            lastOpenedAt: nil,
            isArchived: false
        )
        let catalog = ProjectOrganizationCatalog(rootDirectory: library.url)
        let astroGroup = try await catalog.createNode(
            module: .astrophotography,
            parentID: nil,
            name: "Astro"
        )

        await #expect(throws: ProjectOrganizationError.moduleMismatch) {
            try await catalog.moveProject(project, to: astroGroup.id)
        }
    }
}

private final class OrganizationTemporaryLibrary: @unchecked Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeOrganizationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

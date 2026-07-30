import Foundation

public enum ProjectOrganizationError: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
    case nodeNotFound
    case invalidParent
    case hierarchyTooDeep
    case moduleMismatch
}

public struct ProjectOrganizationNode: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let module: ProjectModule
    public let parentID: UUID?
    public let name: String
    public let createdAt: Date
    public let updatedAt: Date
    public let isArchived: Bool

    public init(
        id: UUID,
        module: ProjectModule,
        parentID: UUID?,
        name: String,
        createdAt: Date,
        updatedAt: Date,
        isArchived: Bool
    ) {
        self.id = id
        self.module = module
        self.parentID = parentID
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
    }

    public var isSubgroup: Bool { parentID != nil }
}

public struct ProjectOrganizationMembership: Codable, Equatable, Hashable, Sendable {
    public let projectID: UUID
    public let nodeID: UUID

    public init(projectID: UUID, nodeID: UUID) {
        self.projectID = projectID
        self.nodeID = nodeID
    }
}

public struct ProjectOrganizationDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let nodes: [ProjectOrganizationNode]
    public let memberships: [ProjectOrganizationMembership]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        nodes: [ProjectOrganizationNode],
        memberships: [ProjectOrganizationMembership]
    ) {
        self.schemaVersion = schemaVersion
        self.nodes = nodes
        self.memberships = memberships
    }

    public static let empty = ProjectOrganizationDocument(nodes: [], memberships: [])
}

public struct ProjectOrganizationSnapshot: Equatable, Sendable {
    public let nodes: [ProjectOrganizationNode]
    public let memberships: [ProjectOrganizationMembership]

    public init(
        nodes: [ProjectOrganizationNode],
        memberships: [ProjectOrganizationMembership]
    ) {
        self.nodes = nodes
        self.memberships = memberships
    }

    public static let empty = ProjectOrganizationSnapshot(nodes: [], memberships: [])

    public func nodeID(for projectID: UUID) -> UUID? {
        memberships.first { $0.projectID == projectID }?.nodeID
    }

    public func node(for projectID: UUID) -> ProjectOrganizationNode? {
        guard let nodeID = nodeID(for: projectID) else { return nil }
        return nodes.first { $0.id == nodeID }
    }

    public func children(of parentID: UUID) -> [ProjectOrganizationNode] {
        nodes.filter { $0.parentID == parentID }
    }
}

public struct ProjectOrganizationCodec: Sendable {
    public init() {}

    public func decode(_ data: Data) throws -> ProjectOrganizationDocument {
        let document = try Self.decoder().decode(ProjectOrganizationDocument.self, from: data)
        guard document.schemaVersion == ProjectOrganizationDocument.currentSchemaVersion else {
            throw ProjectOrganizationError.unsupportedSchema(document.schemaVersion)
        }
        return document
    }

    public func encode(_ document: ProjectOrganizationDocument) throws -> Data {
        guard document.schemaVersion == ProjectOrganizationDocument.currentSchemaVersion else {
            throw ProjectOrganizationError.unsupportedSchema(document.schemaVersion)
        }
        return try Self.encoder().encode(document)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum ProjectOrganizationResolver {
    public static func normalize(
        _ document: ProjectOrganizationDocument,
        projects: [ProjectRecord]
    ) -> ProjectOrganizationDocument {
        let projectByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        var uniqueNodes: [ProjectOrganizationNode] = []
        var seenNodeIDs = Set<UUID>()
        for node in document.nodes where seenNodeIDs.insert(node.id).inserted {
            uniqueNodes.append(node)
        }
        let roots = uniqueNodes.filter { $0.parentID == nil }
        let rootByID = Dictionary(uniqueKeysWithValues: roots.map { ($0.id, $0) })
        let children = uniqueNodes.filter { node in
            guard let parentID = node.parentID,
                  let parent = rootByID[parentID] else {
                return false
            }
            return parent.module == node.module
        }
        let accepted = roots + children

        let nodeByID = Dictionary(uniqueKeysWithValues: accepted.map { ($0.id, $0) })
        var assignedProjects = Set<UUID>()
        let memberships = document.memberships.filter { membership in
            guard !assignedProjects.contains(membership.projectID),
                  let project = projectByID[membership.projectID],
                  let node = nodeByID[membership.nodeID],
                  project.module == node.module else {
                return false
            }
            assignedProjects.insert(membership.projectID)
            return true
        }

        return ProjectOrganizationDocument(nodes: accepted, memberships: memberships)
    }
}

public actor ProjectOrganizationCatalog {
    private let fileManager: FileManager
    private let dateProvider: any DateProviding
    private let idProvider: any IDProviding
    private let codec = ProjectOrganizationCodec()
    private var cachedDocument: ProjectOrganizationDocument?

    public nonisolated let organizationURL: URL

    public init(
        rootDirectory: URL,
        fileManager: FileManager = .default,
        dateProvider: any DateProviding = SystemDateProvider(),
        idProvider: any IDProviding = SystemIDProvider()
    ) {
        self.fileManager = fileManager
        self.dateProvider = dateProvider
        self.idProvider = idProvider
        organizationURL = rootDirectory
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Camerae", isDirectory: true)
            .appendingPathComponent("project-organization-v1.json")
    }

    public func load(projects: [ProjectRecord]) throws -> ProjectOrganizationSnapshot {
        let current = try readCurrent()
        let normalized = ProjectOrganizationResolver.normalize(current, projects: projects)
        if normalized != current || !fileManager.fileExists(atPath: organizationURL.path) {
            try persist(normalized)
        }
        cachedDocument = normalized
        return snapshot(normalized)
    }

    public func createNode(
        module: ProjectModule,
        parentID: UUID?,
        name requestedName: String
    ) async throws -> ProjectOrganizationNode {
        var document = try readCurrent()
        if let parentID {
            guard let parent = document.nodes.first(where: { $0.id == parentID }) else {
                throw ProjectOrganizationError.invalidParent
            }
            guard parent.module == module else {
                throw ProjectOrganizationError.moduleMismatch
            }
            guard parent.parentID == nil else {
                throw ProjectOrganizationError.hierarchyTooDeep
            }
        }

        let now = dateProvider.now()
        let trimmed = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let node = ProjectOrganizationNode(
            id: await idProvider.next(),
            module: module,
            parentID: parentID,
            name: trimmed.isEmpty ? (parentID == nil ? "Novo grupo" : "Novo subgrupo") : trimmed,
            createdAt: now,
            updatedAt: now,
            isArchived: false
        )
        document = ProjectOrganizationDocument(
            nodes: document.nodes + [node],
            memberships: document.memberships
        )
        try persist(document)
        return node
    }

    @discardableResult
    public func renameNode(_ nodeID: UUID, name requestedName: String) throws -> ProjectOrganizationNode {
        var document = try readCurrent()
        guard let index = document.nodes.firstIndex(where: { $0.id == nodeID }) else {
            throw ProjectOrganizationError.nodeNotFound
        }
        let current = document.nodes[index]
        let trimmed = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = ProjectOrganizationNode(
            id: current.id,
            module: current.module,
            parentID: current.parentID,
            name: trimmed.isEmpty ? current.name : trimmed,
            createdAt: current.createdAt,
            updatedAt: dateProvider.now(),
            isArchived: current.isArchived
        )
        var nodes = document.nodes
        nodes[index] = updated
        document = ProjectOrganizationDocument(nodes: nodes, memberships: document.memberships)
        try persist(document)
        return updated
    }

    @discardableResult
    public func setArchived(_ nodeID: UUID, isArchived: Bool) throws -> ProjectOrganizationNode {
        var document = try readCurrent()
        guard let index = document.nodes.firstIndex(where: { $0.id == nodeID }) else {
            throw ProjectOrganizationError.nodeNotFound
        }
        let current = document.nodes[index]
        let updated = ProjectOrganizationNode(
            id: current.id,
            module: current.module,
            parentID: current.parentID,
            name: current.name,
            createdAt: current.createdAt,
            updatedAt: dateProvider.now(),
            isArchived: isArchived
        )
        var nodes = document.nodes
        nodes[index] = updated
        document = ProjectOrganizationDocument(nodes: nodes, memberships: document.memberships)
        try persist(document)
        return updated
    }

    public func moveProject(_ project: ProjectRecord, to nodeID: UUID?) throws {
        var document = try readCurrent()
        if let nodeID {
            guard let node = document.nodes.first(where: { $0.id == nodeID }) else {
                throw ProjectOrganizationError.nodeNotFound
            }
            guard node.module == project.module else {
                throw ProjectOrganizationError.moduleMismatch
            }
        }
        let remaining = document.memberships.filter { $0.projectID != project.id }
        let memberships = nodeID.map {
            remaining + [ProjectOrganizationMembership(projectID: project.id, nodeID: $0)]
        } ?? remaining
        document = ProjectOrganizationDocument(nodes: document.nodes, memberships: memberships)
        try persist(document)
    }

    public func deleteNode(_ nodeID: UUID) throws {
        var document = try readCurrent()
        guard document.nodes.contains(where: { $0.id == nodeID }) else {
            throw ProjectOrganizationError.nodeNotFound
        }
        let removedIDs = Set(
            document.nodes
                .filter { $0.id == nodeID || $0.parentID == nodeID }
                .map(\.id)
        )
        document = ProjectOrganizationDocument(
            nodes: document.nodes.filter { !removedIDs.contains($0.id) },
            memberships: document.memberships.filter { !removedIDs.contains($0.nodeID) }
        )
        try persist(document)
    }

    private func readCurrent() throws -> ProjectOrganizationDocument {
        if let cachedDocument { return cachedDocument }
        guard fileManager.fileExists(atPath: organizationURL.path) else {
            return .empty
        }
        return try codec.decode(Data(contentsOf: organizationURL, options: .mappedIfSafe))
    }

    private func persist(_ document: ProjectOrganizationDocument) throws {
        try fileManager.createDirectory(
            at: organizationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try codec.encode(document).write(to: organizationURL, options: .atomic)
        cachedDocument = document
    }

    private func snapshot(_ document: ProjectOrganizationDocument) -> ProjectOrganizationSnapshot {
        ProjectOrganizationSnapshot(
            nodes: document.nodes,
            memberships: document.memberships
        )
    }
}

import Foundation

public enum ProjectModule: String, CaseIterable, Codable, Hashable, Sendable {
    case astrophotography
    case repeatable
    case edit
}

public enum InventoryState: String, Codable, Hashable, Sendable {
    case clean
    case dirty
}

public struct ProjectRecord: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let module: ProjectModule
    public let name: String
    public let directoryURL: URL
    public let createdAt: Date
    public let updatedAt: Date
    public let lastOpenedAt: Date?
    public let isArchived: Bool

    public init(
        id: UUID,
        module: ProjectModule,
        name: String,
        directoryURL: URL,
        createdAt: Date,
        updatedAt: Date,
        lastOpenedAt: Date?,
        isArchived: Bool
    ) {
        self.id = id
        self.module = module
        self.name = name
        self.directoryURL = directoryURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
        self.isArchived = isArchived
    }
}

public struct ProjectSummary: Codable, Equatable, Hashable, Sendable {
    public let sessionCount: Int
    public let mediaCount: Int
    public let referenceThumbnailKey: String?
    public let latestSessionAt: Date?
    public let totalKnownBytes: UInt64?
    public let inventoryState: InventoryState
    public let generation: Int

    public init(
        sessionCount: Int,
        mediaCount: Int,
        referenceThumbnailKey: String?,
        latestSessionAt: Date?,
        totalKnownBytes: UInt64?,
        inventoryState: InventoryState,
        generation: Int
    ) {
        self.sessionCount = sessionCount
        self.mediaCount = mediaCount
        self.referenceThumbnailKey = referenceThumbnailKey
        self.latestSessionAt = latestSessionAt
        self.totalKnownBytes = totalKnownBytes
        self.inventoryState = inventoryState
        self.generation = generation
    }

    public static let empty = ProjectSummary(
        sessionCount: 0,
        mediaCount: 0,
        referenceThumbnailKey: nil,
        latestSessionAt: nil,
        totalKnownBytes: 0,
        inventoryState: .clean,
        generation: 0
    )
}

public struct ProjectManifestDocument: Equatable, Sendable {
    public let schemaVersion: Int
    public let project: ProjectRecord
    public let summary: ProjectSummary?

    public init(project: ProjectRecord, summary: ProjectSummary?, schemaVersion: Int = 3) {
        self.schemaVersion = schemaVersion
        self.project = project
        self.summary = summary
    }
}

public enum CatalogSnapshotSource: String, Equatable, Sendable {
    case memory
    case index
    case rebuilt
}

public struct ProjectCatalogSnapshot: Equatable, Sendable {
    public let projects: [ProjectRecord]
    public let source: CatalogSnapshotSource
    private let summaries: [UUID: ProjectSummary]

    public init(
        projects: [ProjectRecord],
        source: CatalogSnapshotSource,
        summaries: [UUID: ProjectSummary] = [:]
    ) {
        self.projects = projects
        self.source = source
        self.summaries = summaries
    }

    public func summary(for projectID: UUID) -> ProjectSummary? {
        summaries[projectID]
    }
}

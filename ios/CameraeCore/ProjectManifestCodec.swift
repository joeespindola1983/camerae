import Foundation

public struct ProjectManifestCodec: Sendable {
    public init() {}

    public func decode(
        _ data: Data,
        directoryURL: URL = URL(fileURLWithPath: "/", isDirectory: true)
    ) throws -> ProjectManifestDocument {
        let decoder = Self.decoder()
        let payload = try decoder.decode(Payload.self, from: data)
        let schemaVersion = payload.schemaVersion ?? CameraeSchema.legacyUnversioned
        guard (CameraeSchema.legacyUnversioned...CameraeSchema.current).contains(schemaVersion) else {
            throw ManifestCompatibilityError.unsupportedProjectSchema(schemaVersion)
        }
        let project = ProjectRecord(
            id: payload.id,
            module: payload.module,
            name: payload.name,
            directoryURL: directoryURL,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt,
            lastOpenedAt: payload.lastOpenedAt,
            isArchived: payload.isArchived ?? false
        )
        return ProjectManifestDocument(
            project: project,
            summary: payload.summary,
            schemaVersion: schemaVersion
        )
    }

    public func encode(_ document: ProjectManifestDocument) throws -> Data {
        let project = document.project
        let payload = Payload(
            schemaVersion: CameraeSchema.current,
            id: project.id,
            module: project.module,
            name: project.name,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt,
            lastOpenedAt: project.lastOpenedAt,
            isArchived: project.isArchived,
            summary: document.summary
        )
        return try Self.encoder().encode(payload)
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

    private struct Payload: Codable {
        let schemaVersion: Int?
        let id: UUID
        let module: ProjectModule
        let name: String
        let createdAt: Date
        let updatedAt: Date
        let lastOpenedAt: Date?
        let isArchived: Bool?
        let summary: ProjectSummary?
    }
}

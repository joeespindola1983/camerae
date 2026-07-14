import Foundation

public struct SessionManifestCodec: Sendable {
    public init() {}

    public func decode(_ data: Data, directoryURL: URL) throws -> SessionManifestDocument {
        let payload = try Self.decoder().decode(Payload.self, from: data)
        let schemaVersion = payload.schemaVersion ?? CameraeSchema.legacyUnversioned
        guard (CameraeSchema.legacyUnversioned...CameraeSchema.current).contains(schemaVersion) else {
            throw ManifestCompatibilityError.unsupportedSessionSchema(schemaVersion)
        }
        let session = SessionRecord(
            id: payload.id,
            projectID: payload.projectId,
            module: payload.module,
            captureKind: payload.captureKind ?? .timelapse,
            name: payload.name,
            directoryURL: directoryURL,
            createdAt: payload.createdAt,
            referenceMotion: payload.referenceMotion,
            referenceGeoPose: payload.referenceGeoPose,
            referenceOrientation: payload.referenceOrientation,
            cameraLens: payload.cameraLens
        )
        return SessionManifestDocument(
            schemaVersion: schemaVersion,
            session: session,
            frameSummary: payload.frameSummary,
            astroSummary: payload.astroSummary,
            videoSummary: payload.videoSummary,
            thumbnailKey: payload.thumbnailKey,
            inventoryState: payload.inventoryState ?? (payload.frameSummary == nil ? .dirty : .clean),
            generation: payload.generation ?? 0
        )
    }

    public func encode(_ document: SessionManifestDocument) throws -> Data {
        let session = document.session
        let payload = Payload(
            schemaVersion: CameraeSchema.current,
            id: session.id,
            projectId: session.projectID,
            module: session.module,
            captureKind: session.captureKind,
            name: session.name,
            createdAt: session.createdAt,
            referenceMotion: session.referenceMotion,
            referenceGeoPose: session.referenceGeoPose,
            referenceOrientation: session.referenceOrientation,
            cameraLens: session.cameraLens,
            frameSummary: document.frameSummary,
            astroSummary: document.astroSummary,
            videoSummary: document.videoSummary,
            thumbnailKey: document.thumbnailKey,
            inventoryState: document.inventoryState,
            generation: document.generation
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
        let projectId: UUID
        let module: ProjectModule
        let captureKind: SessionCaptureKind?
        let name: String
        let createdAt: Date
        let referenceMotion: SessionMotion?
        let referenceGeoPose: SessionGeoPose?
        let referenceOrientation: String?
        let cameraLens: String?
        let frameSummary: FrameSummary?
        let astroSummary: AstroSessionSummary?
        let videoSummary: VideoSessionSummary?
        let thumbnailKey: String?
        let inventoryState: InventoryState?
        let generation: Int?
    }
}

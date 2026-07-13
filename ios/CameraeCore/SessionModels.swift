import Foundation

public enum SessionCaptureKind: String, Codable, CaseIterable, Hashable, Sendable {
    case timelapse
    case video
    case photo
}

public struct SessionMotion: Codable, Equatable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct SessionGeoPose: Codable, Equatable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let horizontalAccuracy: Double
    public let heading: Double?
    public let timestamp: Date

    public init(latitude: Double, longitude: Double, horizontalAccuracy: Double, heading: Double?, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.heading = heading
        self.timestamp = timestamp
    }
}

public struct SessionRecord: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let projectID: UUID
    public let module: ProjectModule
    public let captureKind: SessionCaptureKind
    public let name: String
    public let directoryURL: URL
    public let createdAt: Date
    public let referenceMotion: SessionMotion?
    public let referenceGeoPose: SessionGeoPose?
    public let referenceOrientation: String?
    public let cameraLens: String?

    public init(
        id: UUID,
        projectID: UUID,
        module: ProjectModule,
        captureKind: SessionCaptureKind,
        name: String,
        directoryURL: URL,
        createdAt: Date,
        referenceMotion: SessionMotion? = nil,
        referenceGeoPose: SessionGeoPose? = nil,
        referenceOrientation: String? = nil,
        cameraLens: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.module = module
        self.captureKind = captureKind
        self.name = name
        self.directoryURL = directoryURL
        self.createdAt = createdAt
        self.referenceMotion = referenceMotion
        self.referenceGeoPose = referenceGeoPose
        self.referenceOrientation = referenceOrientation
        self.cameraLens = cameraLens
    }
}

public struct FrameSummary: Codable, Equatable, Hashable, Sendable {
    public let count: Int
    public let firstFileName: String?
    public let lastFileName: String?
    public let nextFrameIndex: Int
    public let knownBytes: UInt64

    public init(count: Int, firstFileName: String?, lastFileName: String?, nextFrameIndex: Int, knownBytes: UInt64) {
        self.count = count
        self.firstFileName = firstFileName
        self.lastFileName = lastFileName
        self.nextFrameIndex = nextFrameIndex
        self.knownBytes = knownBytes
    }

    public static let empty = FrameSummary(
        count: 0,
        firstFileName: nil,
        lastFileName: nil,
        nextFrameIndex: 1,
        knownBytes: 0
    )
}

public struct AstroSessionSummary: Codable, Equatable, Hashable, Sendable {
    public let frameCount: Int
    public let hasRenderedClip: Bool

    public init(frameCount: Int, hasRenderedClip: Bool) {
        self.frameCount = frameCount
        self.hasRenderedClip = hasRenderedClip
    }
}

public struct VideoSessionSummary: Codable, Equatable, Hashable, Sendable {
    public let videoFileName: String?
    public let clipFileName: String?

    public init(videoFileName: String?, clipFileName: String?) {
        self.videoFileName = videoFileName
        self.clipFileName = clipFileName
    }
}

public struct SessionSummary: Identifiable, Equatable, Hashable, Sendable {
    public let session: SessionRecord
    public let frameSummary: FrameSummary
    public let astroSummary: AstroSessionSummary?
    public let videoSummary: VideoSessionSummary?
    public let thumbnailKey: String?
    public let inventoryState: InventoryState
    public let generation: Int

    public var id: UUID { session.id }

    public init(
        session: SessionRecord,
        frameSummary: FrameSummary,
        astroSummary: AstroSessionSummary?,
        videoSummary: VideoSessionSummary?,
        thumbnailKey: String?,
        inventoryState: InventoryState,
        generation: Int
    ) {
        self.session = session
        self.frameSummary = frameSummary
        self.astroSummary = astroSummary
        self.videoSummary = videoSummary
        self.thumbnailKey = thumbnailKey
        self.inventoryState = inventoryState
        self.generation = generation
    }
}

public struct SessionManifestDocument: Equatable, Sendable {
    public let schemaVersion: Int
    public let session: SessionRecord
    public let frameSummary: FrameSummary?
    public let astroSummary: AstroSessionSummary?
    public let videoSummary: VideoSessionSummary?
    public let thumbnailKey: String?
    public let inventoryState: InventoryState
    public let generation: Int

    public var summary: SessionSummary? {
        guard let frameSummary else { return nil }
        return SessionSummary(
            session: session,
            frameSummary: frameSummary,
            astroSummary: astroSummary,
            videoSummary: videoSummary,
            thumbnailKey: thumbnailKey,
            inventoryState: inventoryState,
            generation: generation
        )
    }

    public init(
        schemaVersion: Int = 3,
        session: SessionRecord,
        frameSummary: FrameSummary?,
        astroSummary: AstroSessionSummary? = nil,
        videoSummary: VideoSessionSummary? = nil,
        thumbnailKey: String? = nil,
        inventoryState: InventoryState = .clean,
        generation: Int = 0
    ) {
        self.schemaVersion = schemaVersion
        self.session = session
        self.frameSummary = frameSummary
        self.astroSummary = astroSummary
        self.videoSummary = videoSummary
        self.thumbnailKey = thumbnailKey
        self.inventoryState = inventoryState
        self.generation = generation
    }
}

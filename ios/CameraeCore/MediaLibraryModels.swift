import Foundation

public struct MediaAssetDescriptor: Equatable, Hashable, Sendable {
    public let reference: MediaAssetReference
    public let sourceModule: ProjectModule
    public let projectName: String
    public let sessionName: String
    public let sourceCreatedAt: Date
    public let duration: TimeInterval
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let hasAudio: Bool
    public let fileSize: UInt64
    public let isAvailable: Bool

    public init(
        reference: MediaAssetReference,
        sourceModule: ProjectModule,
        projectName: String,
        sessionName: String,
        sourceCreatedAt: Date,
        duration: TimeInterval,
        pixelWidth: Int,
        pixelHeight: Int,
        hasAudio: Bool,
        fileSize: UInt64,
        isAvailable: Bool
    ) {
        self.reference = reference
        self.sourceModule = sourceModule
        self.projectName = projectName
        self.sessionName = sessionName
        self.sourceCreatedAt = sourceCreatedAt
        self.duration = duration
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.hasAudio = hasAudio
        self.fileSize = fileSize
        self.isAvailable = isAvailable
    }
}

public enum MediaOriginFilter: Equatable, Hashable, Sendable {
    case all
    case module(ProjectModule)
}

public enum MediaKindFilter: Equatable, Hashable, Sendable {
    case all
    case timelapse
    case recordedVideo
}

public struct MediaLibraryFilter: Equatable, Hashable, Sendable {
    public var origin: MediaOriginFilter
    public var kind: MediaKindFilter
    public var projectID: UUID?

    public init(
        origin: MediaOriginFilter = .all,
        kind: MediaKindFilter = .all,
        projectID: UUID? = nil
    ) {
        self.origin = origin
        self.kind = kind
        self.projectID = projectID
    }
}

public struct MediaLibrarySnapshot: Equatable, Sendable {
    public let assets: [MediaAssetDescriptor]

    public init(assets: [MediaAssetDescriptor]) {
        self.assets = assets.sorted(by: Self.sort)
    }

    public func filtered(by filter: MediaLibraryFilter) -> [MediaAssetDescriptor] {
        assets.filter { asset in
            let matchesOrigin: Bool
            switch filter.origin {
            case .all:
                matchesOrigin = true
            case .module(let module):
                matchesOrigin = asset.sourceModule == module
            }

            let matchesKind: Bool
            switch filter.kind {
            case .all:
                matchesKind = true
            case .timelapse:
                matchesKind = asset.reference.kind == .repeatableTimelapse ||
                    asset.reference.kind == .astroTimelapse
            case .recordedVideo:
                matchesKind = asset.reference.kind == .repeatableVideo
            }

            return matchesOrigin && matchesKind &&
                (filter.projectID == nil || asset.reference.projectID == filter.projectID)
        }
    }

    private static func sort(_ left: MediaAssetDescriptor, _ right: MediaAssetDescriptor) -> Bool {
        if left.sourceCreatedAt != right.sourceCreatedAt {
            return left.sourceCreatedAt > right.sourceCreatedAt
        }
        return left.reference.id.rawValue < right.reference.id.rawValue
    }
}

import Foundation

public struct MediaAssetID: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum MediaSourceKind: String, CaseIterable, Codable, Hashable, Sendable {
    case repeatableTimelapse
    case repeatableVideo
    case astroTimelapse
}

public struct MediaAssetReference: Codable, Equatable, Hashable, Sendable {
    public let id: MediaAssetID
    public let projectID: UUID
    public let sessionID: UUID
    public let kind: MediaSourceKind
    public let relativePath: String

    public init(
        projectID: UUID,
        sessionID: UUID,
        kind: MediaSourceKind,
        relativePath: String
    ) {
        self.projectID = projectID
        self.sessionID = sessionID
        self.kind = kind
        self.relativePath = relativePath
        id = Self.makeID(
            projectID: projectID,
            sessionID: sessionID,
            kind: kind,
            relativePath: relativePath
        )
    }

    public init(
        id: MediaAssetID,
        projectID: UUID,
        sessionID: UUID,
        kind: MediaSourceKind,
        relativePath: String
    ) {
        self.id = id
        self.projectID = projectID
        self.sessionID = sessionID
        self.kind = kind
        self.relativePath = relativePath
    }

    public static func makeID(
        projectID: UUID,
        sessionID: UUID,
        kind: MediaSourceKind,
        relativePath: String
    ) -> MediaAssetID {
        let normalizedPath = relativePath.replacingOccurrences(of: "\\", with: "/")
        return MediaAssetID(rawValue: [
            projectID.uuidString.lowercased(),
            sessionID.uuidString.lowercased(),
            kind.rawValue,
            normalizedPath
        ].joined(separator: ":"))
    }
}

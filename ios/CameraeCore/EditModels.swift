import Foundation

public enum EditCanvas: String, CaseIterable, Codable, Hashable, Sendable {
    case landscape16x9
    case portrait9x16
}

public struct EditTimelineItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let asset: MediaAssetReference
    public let addedAt: Date

    public init(id: UUID, asset: MediaAssetReference, addedAt: Date) {
        self.id = id
        self.asset = asset
        self.addedAt = addedAt
    }
}

public struct EditProjectDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let projectID: UUID
    public var canvas: EditCanvas
    public var items: [EditTimelineItem]
    public var updatedAt: Date
    public var lastExportRelativePath: String?

    public init(
        schemaVersion: Int = 1,
        projectID: UUID,
        canvas: EditCanvas,
        items: [EditTimelineItem],
        updatedAt: Date,
        lastExportRelativePath: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.projectID = projectID
        self.canvas = canvas
        self.items = items
        self.updatedAt = updatedAt
        self.lastExportRelativePath = lastExportRelativePath
    }
}

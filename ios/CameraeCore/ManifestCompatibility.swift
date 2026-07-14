import Foundation

public enum ManifestCompatibilityError: Error, Equatable, Sendable {
    case unsupportedProjectSchema(Int)
    case unsupportedSessionSchema(Int)
}

public enum CameraeSchema {
    public static let legacyUnversioned = 2
    public static let current = 5
}

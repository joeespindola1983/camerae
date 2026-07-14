import Foundation

public struct AtomicArtifactPublisher: Sendable {
    public init() {}

    public func publish(
        temporaryURL: URL,
        destinationURL: URL,
        validate: (URL) throws -> Void
    ) throws {
        var shouldRemoveTemporary = true
        defer {
            if shouldRemoveTemporary {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }

        try validate(temporaryURL)
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            _ = try FileManager.default.replaceItemAt(
                destinationURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        }
        shouldRemoveTemporary = false
    }
}

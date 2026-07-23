import Foundation

enum CameraeOriginalRetentionError: Error, Equatable {
    case missingRenderedOutput
}

struct CameraeOriginalRetentionPolicy: Sendable {
    let preservesOriginals: Bool

    func apply(
        in sessionDirectoryURL: URL,
        renderedOutputURL: URL,
        fileManager: FileManager = .default
    ) throws {
        guard !preservesOriginals else { return }
        guard fileManager.fileExists(atPath: renderedOutputURL.path) else {
            throw CameraeOriginalRetentionError.missingRenderedOutput
        }

        let contents = try fileManager.contentsOfDirectory(
            at: sessionDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        for url in contents where Self.isOriginalFrame(url) {
            try fileManager.removeItem(at: url)
        }
    }

    private static func isOriginalFrame(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let extensions: Set<String> = ["jpg", "jpeg", "heic", "dng"]
        return name.hasPrefix("frame_") && extensions.contains(url.pathExtension.lowercased())
    }
}

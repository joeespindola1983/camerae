import Foundation

public struct ProjectStorageBreakdown: Codable, Equatable, Sendable {
    public var originalBytes: UInt64
    public var processedBytes: UInt64
    public var finalArtifactBytes: UInt64
    public var cacheBytes: UInt64
    public var exportBytes: UInt64
    public var metadataBytes: UInt64

    public init(
        originalBytes: UInt64 = 0,
        processedBytes: UInt64 = 0,
        finalArtifactBytes: UInt64 = 0,
        cacheBytes: UInt64 = 0,
        exportBytes: UInt64 = 0,
        metadataBytes: UInt64 = 0
    ) {
        self.originalBytes = originalBytes
        self.processedBytes = processedBytes
        self.finalArtifactBytes = finalArtifactBytes
        self.cacheBytes = cacheBytes
        self.exportBytes = exportBytes
        self.metadataBytes = metadataBytes
    }

    public var totalBytes: UInt64 {
        [originalBytes, processedBytes, finalArtifactBytes, cacheBytes, exportBytes, metadataBytes]
            .reduce(0, Self.saturatingAdd)
    }

    private static func saturatingAdd(_ left: UInt64, _ right: UInt64) -> UInt64 {
        let result = left.addingReportingOverflow(right)
        return result.overflow ? .max : result.partialValue
    }
}

public struct ProjectStorageScanner: Sendable {
    public init() {}

    public func scan(projectDirectory: URL) throws -> ProjectStorageBreakdown {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: projectDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return ProjectStorageBreakdown()
        }

        var result = ProjectStorageBreakdown()
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let bytes = UInt64(max(values.fileSize ?? 0, 0))
            let relative = relativeComponents(of: url, under: projectDirectory)
            classify(url: url, relativeComponents: relative, bytes: bytes, into: &result)
        }
        return result
    }

    private func classify(
        url: URL,
        relativeComponents: [String],
        bytes: UInt64,
        into result: inout ProjectStorageBreakdown
    ) {
        let components = Set(relativeComponents.map { $0.lowercased() })
        let name = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()

        if components.contains("exports") {
            result.exportBytes = add(result.exportBytes, bytes)
        } else if components.contains("preview frames") || components.contains("cache") || components.contains("caches") {
            result.cacheBytes = add(result.cacheBytes, bytes)
        } else if ["mp4", "mov", "m4v"].contains(ext) {
            result.finalArtifactBytes = add(result.finalArtifactBytes, bytes)
        } else if name.hasPrefix("frame_") && ["jpg", "jpeg", "heic", "dng"].contains(ext) {
            result.originalBytes = add(result.originalBytes, bytes)
        } else if components.contains("astro frames") || components.contains("astro renders") {
            result.processedBytes = add(result.processedBytes, bytes)
        } else {
            result.metadataBytes = add(result.metadataBytes, bytes)
        }
    }

    private func relativeComponents(of url: URL, under root: URL) -> [String] {
        let rootComponents = root.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents
        guard components.starts(with: rootComponents) else { return components }
        return Array(components.dropFirst(rootComponents.count))
    }

    private func add(_ left: UInt64, _ right: UInt64) -> UInt64 {
        let result = left.addingReportingOverflow(right)
        return result.overflow ? .max : result.partialValue
    }
}

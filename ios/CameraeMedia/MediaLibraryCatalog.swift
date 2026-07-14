import CameraeCore
import Foundation

public struct ResolvedMediaAsset: Equatable, Sendable {
    public let descriptor: MediaAssetDescriptor
    public let url: URL

    public init(descriptor: MediaAssetDescriptor, url: URL) {
        self.descriptor = descriptor
        self.url = url
    }
}

public protocol MediaLibraryProviding: Sendable {
    func load() async throws -> MediaLibrarySnapshot
    func resolve(_ reference: MediaAssetReference) async throws -> ResolvedMediaAsset?
    func invalidate() async
}

public actor MediaLibraryCatalog: MediaLibraryProviding {
    private struct Candidate {
        let project: ProjectRecord
        let session: SessionRecord
        let kind: MediaSourceKind
        let url: URL
        let relativePath: String
    }

    private let projectCatalog: ProjectCatalog
    private let probe: any MediaAssetProbing
    private let fileManager: FileManager
    private var cachedSnapshot: MediaLibrarySnapshot?
    private var resolved: [MediaAssetID: ResolvedMediaAsset] = [:]

    public init(
        rootDirectory: URL,
        probe: any MediaAssetProbing = MediaAssetProbe(),
        fileManager: FileManager = .default
    ) {
        projectCatalog = ProjectCatalog(rootDirectory: rootDirectory, fileManager: fileManager)
        self.probe = probe
        self.fileManager = fileManager
    }

    public func load() async throws -> MediaLibrarySnapshot {
        if let cachedSnapshot { return cachedSnapshot }

        let projects = try await projectCatalog.load().projects.filter { $0.module != .edit }
        var discoveredCandidates: [Candidate] = []
        for project in projects {
            try Task.checkCancellation()
            let sessions = try await SessionCatalog(project: project, fileManager: fileManager).loadSummaries()
            for summary in sessions {
                try Task.checkCancellation()
                discoveredCandidates.append(contentsOf: try candidates(for: summary.session, project: project))
            }
        }

        var assets: [MediaAssetDescriptor] = []
        var nextResolved: [MediaAssetID: ResolvedMediaAsset] = [:]
        for candidate in discoveredCandidates {
            try Task.checkCancellation()
            guard regularNonEmptyFile(candidate.url) else { continue }
            guard let metadata = try? await probe.probe(url: candidate.url) else { continue }
            let reference = MediaAssetReference(
                projectID: candidate.project.id,
                sessionID: candidate.session.id,
                kind: candidate.kind,
                relativePath: candidate.relativePath
            )
            let descriptor = MediaAssetDescriptor(
                reference: reference,
                sourceModule: candidate.project.module,
                projectName: candidate.project.name,
                sessionName: candidate.session.name,
                sourceCreatedAt: candidate.session.createdAt,
                duration: metadata.duration,
                pixelWidth: metadata.pixelWidth,
                pixelHeight: metadata.pixelHeight,
                hasAudio: metadata.hasAudio,
                fileSize: metadata.fileSize,
                isAvailable: true
            )
            assets.append(descriptor)
            nextResolved[reference.id] = ResolvedMediaAsset(descriptor: descriptor, url: candidate.url)
        }

        let snapshot = MediaLibrarySnapshot(assets: assets)
        resolved = nextResolved
        cachedSnapshot = snapshot
        return snapshot
    }

    public func resolve(_ reference: MediaAssetReference) async throws -> ResolvedMediaAsset? {
        let projects = try await projectCatalog.load().projects
        guard let project = projects.first(where: { $0.id == reference.projectID && $0.module != .edit }),
              let url = safeURL(for: reference.relativePath, in: project.directoryURL) else {
            return nil
        }
        _ = try await load()
        guard let cached = resolved[reference.id],
              cached.url.standardizedFileURL == url.standardizedFileURL,
              regularNonEmptyFile(url) else {
            return nil
        }
        return cached
    }

    public func invalidate() {
        cachedSnapshot = nil
        resolved = [:]
    }

    private func candidates(for session: SessionRecord, project: ProjectRecord) throws -> [Candidate] {
        var result: [Candidate] = []
        if project.module == .repeatable {
            let timelapse = session.directoryURL.appendingPathComponent("timelapse.mp4")
            if let relativePath = relativePath(for: timelapse, in: project.directoryURL) {
                result.append(Candidate(
                    project: project,
                    session: session,
                    kind: .repeatableTimelapse,
                    url: timelapse,
                    relativePath: relativePath
                ))
            }
            let video = session.directoryURL.appendingPathComponent("video.mov")
            if let relativePath = relativePath(for: video, in: project.directoryURL) {
                result.append(Candidate(
                    project: project,
                    session: session,
                    kind: .repeatableVideo,
                    url: video,
                    relativePath: relativePath
                ))
            }
        }

        guard project.module == .astrophotography else { return result }
        let rendersDirectory = session.directoryURL.appendingPathComponent("Astro Renders", isDirectory: true)
        let renderDirectories = (try? fileManager.contentsOfDirectory(
            at: rendersDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for renderDirectory in renderDirectories.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? renderDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let astro = renderDirectory.appendingPathComponent("astro.mp4")
            guard let relativePath = relativePath(for: astro, in: project.directoryURL) else { continue }
            result.append(Candidate(
                project: project,
                session: session,
                kind: .astroTimelapse,
                url: astro,
                relativePath: relativePath
            ))
        }
        return result
    }

    private func regularNonEmptyFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else { return false }
        return values.isRegularFile == true && (values.fileSize ?? 0) > 0
    }

    private func relativePath(for url: URL, in projectDirectory: URL) -> String? {
        let root = projectDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
    }

    private func safeURL(for relativePath: String, in projectDirectory: URL) -> URL? {
        guard !relativePath.hasPrefix("/"), !relativePath.isEmpty else { return nil }
        let candidate = projectDirectory.appendingPathComponent(relativePath).standardizedFileURL
        let root = projectDirectory.standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard candidate.path.hasPrefix(prefix) else { return nil }
        return candidate
    }
}

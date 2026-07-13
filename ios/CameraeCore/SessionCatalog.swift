import Foundation
import os

public actor SessionCatalog {
    private static let logger = Logger(subsystem: "com.espindola.camerae", category: "SessionCatalog")

    private let project: ProjectRecord
    private let sessionsDirectory: URL
    private let fileManager: FileManager
    private let dateProvider: any DateProviding
    private let idProvider: any IDProviding
    private let codec = SessionManifestCodec()
    private var captures: [UUID: SessionManifestDocument] = [:]

    public init(
        project: ProjectRecord,
        fileManager: FileManager = .default,
        dateProvider: any DateProviding = SystemDateProvider(),
        idProvider: any IDProviding = SystemIDProvider()
    ) {
        self.project = project
        self.fileManager = fileManager
        self.dateProvider = dateProvider
        self.idProvider = idProvider
        sessionsDirectory = project.directoryURL.appendingPathComponent("Sessions", isDirectory: true)
    }

    public func createSession(captureKind: SessionCaptureKind) async throws -> SessionRecord {
        try fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        let now = dateProvider.now()
        let id = await idProvider.next()
        let baseName = "session_\(Self.dateFormatter.string(from: now))"
        let directory = uniqueDirectory(baseName: baseName)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = SessionRecord(
            id: id,
            projectID: project.id,
            module: project.module,
            captureKind: captureKind,
            name: directory.lastPathComponent,
            directoryURL: directory,
            createdAt: now
        )
        let document = SessionManifestDocument(session: session, frameSummary: .empty)
        do {
            try write(document)
            return session
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    public func beginCapture(sessionID: UUID) throws {
        var document = try document(for: sessionID)
        document = replacing(document, inventoryState: .dirty, generation: document.generation + 1)
        try write(document)
        captures[sessionID] = document
    }

    @discardableResult
    public func saveFrame(_ data: Data, sessionID: UUID, index: Int) throws -> URL {
        var document = try captures[sessionID] ?? document(for: sessionID)
        guard document.inventoryState == .dirty else { throw SessionCatalogError.captureNotStarted }
        let fileName = String(format: "frame_%06d.jpg", index)
        let url = document.session.directoryURL.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)

        let previous = document.frameSummary ?? .empty
        let summary = FrameSummary(
            count: previous.count + 1,
            firstFileName: previous.firstFileName ?? fileName,
            lastFileName: fileName,
            nextFrameIndex: max(previous.nextFrameIndex, index + 1),
            knownBytes: previous.knownBytes + UInt64(data.count)
        )
        document = replacing(document, frameSummary: summary)
        captures[sessionID] = document
        return url
    }

    public func checkpoint(sessionID: UUID) throws {
        guard let document = captures[sessionID] else { throw SessionCatalogError.captureNotStarted }
        try write(document)
    }

    public func finishCapture(sessionID: UUID) throws {
        var document = try captures[sessionID] ?? document(for: sessionID)
        document = replacing(document, inventoryState: .clean)
        try write(document)
        captures[sessionID] = nil
    }

    public func loadSummaries() throws -> [SessionSummary] {
        guard fileManager.fileExists(atPath: sessionsDirectory.path) else { return [] }
        let directories = try fileManager.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var summaries: [SessionSummary] = []
        for directory in directories {
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            do {
                var document = try read(directory: directory)
                if document.frameSummary == nil || document.inventoryState == .dirty {
                    document = try repair(document)
                    try write(document)
                }
                if let summary = document.summary {
                    summaries.append(summary)
                }
            } catch {
                Self.logger.error("Skipping invalid session at \(directory.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return summaries.sorted { $0.session.createdAt > $1.session.createdAt }
    }

    public func repair(sessionID: UUID) throws -> SessionSummary {
        let document = try repair(document(for: sessionID))
        try write(document)
        guard let summary = document.summary else { throw SessionCatalogError.invalidManifest }
        return summary
    }

    private func repair(_ document: SessionManifestDocument) throws -> SessionManifestDocument {
        let urls = try fileManager.contentsOfDirectory(
            at: document.session.directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        let frames = urls.filter { url in
            url.lastPathComponent.hasPrefix("frame_") &&
            url.pathExtension.lowercased() == "jpg" &&
            ((try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true)
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let bytes = frames.reduce(into: UInt64(0)) { result, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            result += UInt64(max(size, 0))
        }
        let lastIndex = frames.last.flatMap { frameIndex(fileName: $0.lastPathComponent) } ?? 0
        let frameSummary = FrameSummary(
            count: frames.count,
            firstFileName: frames.first?.lastPathComponent,
            lastFileName: frames.last?.lastPathComponent,
            nextFrameIndex: lastIndex + 1,
            knownBytes: bytes
        )
        let astroDirectory = document.session.directoryURL.appendingPathComponent("Astro Frames", isDirectory: true)
        let astroFrameCount = ((try? fileManager.contentsOfDirectory(
            at: astroDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []).filter { url in
            url.lastPathComponent.hasPrefix("astro_frame_") &&
            url.pathExtension.lowercased() == "jpg" &&
            ((try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true)
        }.count
        let rendersDirectory = document.session.directoryURL.appendingPathComponent("Astro Renders", isDirectory: true)
        let hasRenderedClip = ((try? fileManager.contentsOfDirectory(
            at: rendersDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []).contains { directory in
            ((try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true) &&
            fileManager.fileExists(atPath: directory.appendingPathComponent("astro.mp4").path)
        }
        let videoFileName = fileManager.fileExists(
            atPath: document.session.directoryURL.appendingPathComponent("timelapse.mp4").path
        ) ? "timelapse.mp4" : nil
        let clipFileName = fileManager.fileExists(
            atPath: document.session.directoryURL.appendingPathComponent("video.mov").path
        ) ? "video.mov" : nil
        return replacing(
            document,
            frameSummary: frameSummary,
            astroSummary: AstroSessionSummary(frameCount: astroFrameCount, hasRenderedClip: hasRenderedClip),
            videoSummary: VideoSessionSummary(videoFileName: videoFileName, clipFileName: clipFileName),
            inventoryState: .clean,
            generation: document.generation + 1
        )
    }

    private func document(for sessionID: UUID) throws -> SessionManifestDocument {
        if let captured = captures[sessionID] { return captured }
        guard fileManager.fileExists(atPath: sessionsDirectory.path) else { throw SessionCatalogError.sessionNotFound }
        let directories = try fileManager.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil)
        for directory in directories {
            guard let document = try? read(directory: directory), document.session.id == sessionID else { continue }
            return document
        }
        throw SessionCatalogError.sessionNotFound
    }

    private func read(directory: URL) throws -> SessionManifestDocument {
        let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"), options: .mappedIfSafe)
        return try codec.decode(data, directoryURL: directory)
    }

    private func write(_ document: SessionManifestDocument) throws {
        let data = try codec.encode(document)
        try data.write(to: document.session.directoryURL.appendingPathComponent("manifest.json"), options: .atomic)
    }

    private func replacing(
        _ document: SessionManifestDocument,
        frameSummary: FrameSummary? = nil,
        astroSummary: AstroSessionSummary? = nil,
        videoSummary: VideoSessionSummary? = nil,
        inventoryState: InventoryState? = nil,
        generation: Int? = nil
    ) -> SessionManifestDocument {
        SessionManifestDocument(
            session: document.session,
            frameSummary: frameSummary ?? document.frameSummary,
            astroSummary: astroSummary ?? document.astroSummary,
            videoSummary: videoSummary ?? document.videoSummary,
            thumbnailKey: document.thumbnailKey,
            inventoryState: inventoryState ?? document.inventoryState,
            generation: generation ?? document.generation
        )
    }

    private func frameIndex(fileName: String) -> Int? {
        Int(fileName.dropFirst("frame_".count).dropLast(".jpg".count))
    }

    private func uniqueDirectory(baseName: String) -> URL {
        var candidate = sessionsDirectory.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = sessionsDirectory.appendingPathComponent("\(baseName)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}

public enum SessionCatalogError: Error, Equatable {
    case sessionNotFound
    case captureNotStarted
    case invalidManifest
}

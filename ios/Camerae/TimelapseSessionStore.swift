import CoreGraphics
import CameraeCore
import Foundation
import UIKit

struct TimelapseSession: Identifiable, Equatable, Hashable {
    let id: UUID
    let projectID: UUID
    let module: CameraModule
    let captureKind: RepeatableCaptureKind
    let referenceMotion: MotionAttitude?
    let referenceGeoPose: GeoPose?
    let referenceOrientation: CaptureDisplayOrientation?
    let cameraLens: RepeatableCameraLens?
    let name: String
    let directoryURL: URL
    let createdAt: Date
}

struct TimelapseSessionSummary: Identifiable, Equatable, Hashable {
    let session: TimelapseSession
    let captureKind: RepeatableCaptureKind
    let frameCount: Int
    let referenceFrameURL: URL?
    let videoURL: URL?
    let videoClipURL: URL?
    let isAstroProcessed: Bool

    var id: UUID { session.id }
}

struct OriginalFrameExportProgress: Equatable, Sendable {
    let processedFrames: Int
    let totalFrames: Int
    let completedBatches: Int
    let totalBatches: Int
    let currentBatch: Int
    let currentBatchFrames: Int
    let currentBatchProcessedFrames: Int

    var detailText: String {
        let batch = min(max(currentBatch, 1), max(totalBatches, 1))
        let remainingBatches = max(totalBatches - completedBatches, 0)
        return "\(processedFrames)/\(totalFrames) imagens • lote \(batch)/\(totalBatches) • faltam \(remainingBatches)"
    }
}

private struct OriginalFrameExportPlan {
    let totalFrames: Int
    let batches: [OriginalFrameArchiveBatch]
}

private struct OriginalFrameArchiveBatch {
    let index: Int
    let frames: [URL]
    let url: URL
}

final class TimelapseSessionStore {
    private static let maxOriginalFramesPerArchive = 1_000
    private static let maxOriginalFrameArchiveBytes: UInt64 = 2 * 1024 * 1024 * 1024

    private let fileManager = FileManager.default
    private let project: CameraProject
    private let sessionsDirectory: URL
    private let exportsDirectory: URL
    private let dateFormatter: DateFormatter

    init(project: CameraProject) {
        self.project = project
        sessionsDirectory = project.directoryURL.appendingPathComponent("Sessions", isDirectory: true)
        exportsDirectory = project.directoryURL.appendingPathComponent("Exports", isDirectory: true)

        dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    }

    func createSession(
        captureKind: RepeatableCaptureKind = .timelapse,
        cameraLens: RepeatableCameraLens? = nil
    ) throws -> TimelapseSession {
        try fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)

        let createdAt = Date()
        let id = UUID()
        let name = "session_\(dateFormatter.string(from: createdAt))"
        let directoryURL = sessionsDirectory.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let session = TimelapseSession(
            id: id,
            projectID: project.id,
            module: project.module,
            captureKind: captureKind,
            referenceMotion: nil,
            referenceGeoPose: nil,
            referenceOrientation: nil,
            cameraLens: cameraLens,
            name: name,
            directoryURL: directoryURL,
            createdAt: createdAt
        )
        try writeManifest(for: session)
        return session
    }

    func saveFrame(_ data: Data, in session: TimelapseSession, index: Int) throws -> URL {
        let fileName = String(format: "frame_%06d.jpg", index)
        let fileURL = session.directoryURL.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    func importReferenceImage(_ image: UIImage) throws -> TimelapseSession {
        let normalizedImage = image.normalizedForStorage()
        guard let data = normalizedImage.jpegData(compressionQuality: 0.95) else {
            throw TimelapseStoreError.referenceImageEncodingFailed
        }

        let session = try createSession(captureKind: .photo)
        do {
            let orientation: CaptureDisplayOrientation = normalizedImage.size.width > normalizedImage.size.height
                ? .landscapeRight
                : .portrait
            let orientedSession = try updateReferenceOrientation(
                orientation,
                for: session
            )
            _ = try saveFrame(data, in: orientedSession, index: 1)
            return orientedSession
        } catch {
            try? deleteSession(session)
            throw error
        }
    }

    func saveAstroStackFrame(_ data: Data, in session: TimelapseSession, index: Int) throws -> URL {
        let directoryURL = session.directoryURL.appendingPathComponent("Astro Frames", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileName = String(format: "astro_frame_%06d.jpg", index)
        let fileURL = directoryURL.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    func saveAstroStackingStartFrame(_ frameIndex: Int, in session: TimelapseSession) throws {
        let metadata: [String: Any] = [
            "stackingStartFrame": max(frameIndex, 1),
            "updatedAt": ISO8601DateFormatter().string(from: Date())
        ]
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: astroCaptureMetadataURL(for: session), options: [.atomic])
    }

    func astroStackingStartFrame(in session: TimelapseSession) -> Int? {
        guard
            let data = try? Data(contentsOf: astroCaptureMetadataURL(for: session)),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return object["stackingStartFrame"] as? Int
    }

    func updateReferenceMotion(_ motion: MotionAttitude, for session: TimelapseSession) throws -> TimelapseSession {
        let updatedSession = TimelapseSession(
            id: session.id,
            projectID: session.projectID,
            module: session.module,
            captureKind: session.captureKind,
            referenceMotion: motion,
            referenceGeoPose: session.referenceGeoPose,
            referenceOrientation: session.referenceOrientation,
            cameraLens: session.cameraLens,
            name: session.name,
            directoryURL: session.directoryURL,
            createdAt: session.createdAt
        )
        try writeManifest(for: updatedSession)
        return updatedSession
    }

    func updateReferenceGeoPose(_ geoPose: GeoPose, for session: TimelapseSession) throws -> TimelapseSession {
        let updatedSession = TimelapseSession(
            id: session.id,
            projectID: session.projectID,
            module: session.module,
            captureKind: session.captureKind,
            referenceMotion: session.referenceMotion,
            referenceGeoPose: geoPose,
            referenceOrientation: session.referenceOrientation,
            cameraLens: session.cameraLens,
            name: session.name,
            directoryURL: session.directoryURL,
            createdAt: session.createdAt
        )
        try writeManifest(for: updatedSession)
        return updatedSession
    }

    func updateReferenceOrientation(
        _ orientation: CaptureDisplayOrientation,
        for session: TimelapseSession
    ) throws -> TimelapseSession {
        let updatedSession = TimelapseSession(
            id: session.id,
            projectID: session.projectID,
            module: session.module,
            captureKind: session.captureKind,
            referenceMotion: session.referenceMotion,
            referenceGeoPose: session.referenceGeoPose,
            referenceOrientation: orientation,
            cameraLens: session.cameraLens,
            name: session.name,
            directoryURL: session.directoryURL,
            createdAt: session.createdAt
        )
        try writeManifest(for: updatedSession)
        return updatedSession
    }

    func latestSessionWithFrames() -> TimelapseSession? {
        guard let sessions = try? loadSessions() else {
            return nil
        }

        return sessions
            .filter { frameCount(in: $0) > 0 }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    func latestSessionSummaryWithFrames() -> TimelapseSessionSummary? {
        guard let session = latestSessionWithFrames() else {
            return nil
        }

        return summary(for: session)
    }

    func sessionSummaries() -> [TimelapseSessionSummary] {
        guard let sessions = try? loadSessions() else {
            return []
        }

        return sessions
            .sorted { $0.createdAt > $1.createdAt }
            .map(summary)
    }

    func sessionSummariesFromCatalog() async throws -> [TimelapseSessionSummary] {
        let summaries = try await SessionCatalog(project: project.coreRecord).loadSummaries()
        return summaries.map { summary in
            let record = summary.session
            let session = TimelapseSession(
                id: record.id,
                projectID: record.projectID,
                module: CameraModule(rawValue: record.module.rawValue) ?? project.module,
                captureKind: RepeatableCaptureKind(rawValue: record.captureKind.rawValue) ?? .timelapse,
                referenceMotion: record.referenceMotion.map { MotionAttitude(x: $0.x, y: $0.y, z: $0.z) },
                referenceGeoPose: record.referenceGeoPose.map {
                    GeoPose(
                        latitude: $0.latitude,
                        longitude: $0.longitude,
                        horizontalAccuracy: $0.horizontalAccuracy,
                        heading: $0.heading,
                        timestamp: $0.timestamp
                    )
                },
                referenceOrientation: record.referenceOrientation.flatMap(CaptureDisplayOrientation.init(rawValue:)),
                cameraLens: record.cameraLens.flatMap(RepeatableCameraLens.init(rawValue:)),
                name: record.name,
                directoryURL: record.directoryURL,
                createdAt: record.createdAt
            )
            let referenceURL = summary.frameSummary.firstFileName.map {
                record.directoryURL.appendingPathComponent($0)
            }
            let videoURL = summary.videoSummary?.videoFileName.map {
                record.directoryURL.appendingPathComponent($0)
            }
            let clipURL = summary.videoSummary?.clipFileName.map {
                record.directoryURL.appendingPathComponent($0)
            }
            return TimelapseSessionSummary(
                session: session,
                captureKind: session.captureKind,
                frameCount: summary.frameSummary.count,
                referenceFrameURL: referenceURL,
                videoURL: videoURL,
                videoClipURL: clipURL,
                isAstroProcessed: (summary.astroSummary?.frameCount ?? 0) > 0 ||
                    (summary.astroSummary?.hasRenderedClip ?? false)
            )
        }
    }

    private func summary(for session: TimelapseSession) -> TimelapseSessionSummary {
        TimelapseSessionSummary(
            session: session,
            captureKind: session.captureKind,
            frameCount: frameCount(in: session),
            referenceFrameURL: firstFrameURL(in: session),
            videoURL: existingVideoURL(for: session),
            videoClipURL: existingVideoClipURL(for: session),
            isAstroProcessed: isAstroProcessed(session)
        )
    }

    func firstReferenceFrameURL() -> URL? {
        guard let sessions = try? loadSessions() else {
            return nil
        }

        return sessions
            .filter { frameCount(in: $0) > 0 }
            .sorted { $0.createdAt < $1.createdAt }
            .compactMap { firstFrameURL(in: $0) }
            .first
    }

    func referenceMotion(forFrameURL referenceURL: URL?) -> MotionAttitude? {
        guard let referenceURL,
              let sessions = try? loadSessions() else {
            return nil
        }

        let referencePath = referenceURL.standardizedFileURL.path
        return sessions.first { session in
            firstFrameURL(in: session)?.standardizedFileURL.path == referencePath
        }?.referenceMotion
    }

    func referenceGeoPose(forFrameURL referenceURL: URL?) -> GeoPose? {
        guard let referenceURL,
              let sessions = try? loadSessions() else {
            return nil
        }

        let referencePath = referenceURL.standardizedFileURL.path
        return sessions.first { session in
            firstFrameURL(in: session)?.standardizedFileURL.path == referencePath
        }?.referenceGeoPose
    }

    func referenceOrientation(forFrameURL referenceURL: URL?) -> CaptureDisplayOrientation? {
        guard let referenceURL,
              let sessions = try? loadSessions() else {
            return nil
        }

        let referencePath = referenceURL.standardizedFileURL.path
        return sessions.first { session in
            firstFrameURL(in: session)?.standardizedFileURL.path == referencePath
        }?.referenceOrientation
    }

    func cameraLens(forFrameURL referenceURL: URL?) -> RepeatableCameraLens? {
        guard let referenceURL,
              let sessions = try? loadSessions() else {
            return nil
        }

        let referencePath = referenceURL.standardizedFileURL.path
        return sessions.first { session in
            firstFrameURL(in: session)?.standardizedFileURL.path == referencePath
        }?.cameraLens
    }

    func firstFrameURL(in session: TimelapseSession) -> URL? {
        frameURLs(in: session).first
    }

    func frameCount(in session: TimelapseSession) -> Int {
        frameURLs(in: session).count
    }

    func astroStackFrameCount(in session: TimelapseSession) -> Int {
        astroStackFrameURLs(in: session).count
    }

    func frameURLs(in session: TimelapseSession) -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: session.directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return []
        }

        return files.filter { url in
            url.lastPathComponent.hasPrefix("frame_") &&
            url.pathExtension.lowercased() == "jpg" &&
            ((try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true)
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func astroStackFrameURLs(in session: TimelapseSession) -> [URL] {
        let directoryURL = session.directoryURL.appendingPathComponent("Astro Frames", isDirectory: true)
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return []
        }

        return files.filter { url in
            url.lastPathComponent.hasPrefix("astro_frame_") &&
            url.pathExtension.lowercased() == "jpg" &&
            ((try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true)
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func isAstroProcessed(_ session: TimelapseSession) -> Bool {
        astroStackFrameCount(in: session) > 0 || hasAstroRenderedClip(in: session)
    }

    private func hasAstroRenderedClip(in session: TimelapseSession) -> Bool {
        let rendersURL = session.directoryURL.appendingPathComponent("Astro Renders", isDirectory: true)
        guard let renderDirectories = try? fileManager.contentsOfDirectory(
            at: rendersURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return false
        }

        return renderDirectories.contains { renderURL in
            let isDirectory = (try? renderURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            guard isDirectory else { return false }
            return fileManager.fileExists(atPath: renderURL.appendingPathComponent("astro.mp4").path)
        }
    }

    func exportZip(for session: TimelapseSession) throws -> URL {
        try fileManager.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
        let zipURL = exportsDirectory.appendingPathComponent("\(session.name).zip")

        if fileManager.fileExists(atPath: zipURL.path) {
            try fileManager.removeItem(at: zipURL)
        }

        let files = try fileManager
            .contentsOfDirectory(at: session.directoryURL, includingPropertiesForKeys: [.isRegularFileKey])
            .filter { url in
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        try ZipWriter.write(files: files, baseURL: session.directoryURL, to: zipURL)
        return zipURL
    }

    func exportOriginalFramesZip(for session: TimelapseSession) throws -> URL {
        try Self.exportOriginalFramesZip(for: session)
    }

    func exportOriginalFramesArchivesInBackground(for session: TimelapseSession) async throws -> [URL] {
        try await Self.exportOriginalFramesArchivesInBackground(for: session)
    }

    func exportOriginalFramesArchivesInBackground(
        for session: TimelapseSession,
        progress: @escaping @Sendable (OriginalFrameExportProgress) async -> Void
    ) async throws -> [URL] {
        try await Self.exportOriginalFramesArchivesInBackground(for: session, progress: progress)
    }

    static func exportOriginalFramesArchivesInBackground(for session: TimelapseSession) async throws -> [URL] {
        try await exportOriginalFramesArchivesInBackground(for: session) { _ in }
    }

    static func exportOriginalFramesArchivesInBackground(
        for session: TimelapseSession,
        progress: @escaping @Sendable (OriginalFrameExportProgress) async -> Void
    ) async throws -> [URL] {
        try await Task.detached(priority: .utility) {
            try await exportOriginalFramesArchives(for: session, progress: progress)
        }.value
    }

    func exportOriginalFramesZipInBackground(for session: TimelapseSession) async throws -> URL {
        try await Self.exportOriginalFramesZipInBackground(for: session)
    }

    static func exportOriginalFramesZipInBackground(for session: TimelapseSession) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(returning: try exportOriginalFramesZip(for: session))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func exportOriginalFramesZip(for session: TimelapseSession) throws -> URL {
        try exportOriginalFramesArchives(
            for: session,
            maxFramesPerArchive: Int.max,
            maxArchiveBytes: UInt64.max
        )[0]
    }

    static func exportOriginalFramesArchives(
        for session: TimelapseSession,
        maxFramesPerArchive: Int = maxOriginalFramesPerArchive,
        maxArchiveBytes: UInt64 = maxOriginalFrameArchiveBytes
    ) throws -> [URL] {
        try exportOriginalFramesArchivePlan(
            for: session,
            maxFramesPerArchive: maxFramesPerArchive,
            maxArchiveBytes: maxArchiveBytes
        ).batches.map { batch in
            if !FileManager.default.fileExists(atPath: batch.url.path) {
                try ZipWriter.write(files: batch.frames, baseURL: session.directoryURL, to: batch.url)
            }
            return batch.url
        }
    }

    static func exportOriginalFramesArchives(
        for session: TimelapseSession,
        maxFramesPerArchive: Int = maxOriginalFramesPerArchive,
        maxArchiveBytes: UInt64 = maxOriginalFrameArchiveBytes,
        progress: @escaping @Sendable (OriginalFrameExportProgress) async -> Void
    ) async throws -> [URL] {
        let plan = try exportOriginalFramesArchivePlan(
            for: session,
            maxFramesPerArchive: maxFramesPerArchive,
            maxArchiveBytes: maxArchiveBytes
        )
        var processedFrames = 0
        var completedBatches = 0
        var outputURLs: [URL] = []

        await progress(OriginalFrameExportProgress(
            processedFrames: 0,
            totalFrames: plan.totalFrames,
            completedBatches: 0,
            totalBatches: plan.batches.count,
            currentBatch: 1,
            currentBatchFrames: plan.batches.first?.frames.count ?? 0,
            currentBatchProcessedFrames: 0
        ))

        for batch in plan.batches {
            try Task.checkCancellation()

            if completedArchiveExists(at: batch.url) {
                processedFrames += batch.frames.count
                completedBatches += 1
                outputURLs.append(batch.url)
                await progress(OriginalFrameExportProgress(
                    processedFrames: processedFrames,
                    totalFrames: plan.totalFrames,
                    completedBatches: completedBatches,
                    totalBatches: plan.batches.count,
                    currentBatch: batch.index,
                    currentBatchFrames: batch.frames.count,
                    currentBatchProcessedFrames: batch.frames.count
                ))
                continue
            }

            let baseProcessedFrames = processedFrames
            let baseCompletedBatches = completedBatches
            try await ZipWriter.write(
                files: batch.frames,
                baseURL: session.directoryURL,
                to: batch.url
            ) { batchProcessedFrames in
                await progress(OriginalFrameExportProgress(
                    processedFrames: baseProcessedFrames + batchProcessedFrames,
                    totalFrames: plan.totalFrames,
                    completedBatches: baseCompletedBatches,
                    totalBatches: plan.batches.count,
                    currentBatch: batch.index,
                    currentBatchFrames: batch.frames.count,
                    currentBatchProcessedFrames: batchProcessedFrames
                ))
            }

            processedFrames += batch.frames.count
            completedBatches += 1
            outputURLs.append(batch.url)
        }

        return outputURLs
    }

    static func existingOriginalFrameArchives(for session: TimelapseSession) -> [URL] {
        let projectDirectory = session.directoryURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let exportsDirectory = projectDirectory.appendingPathComponent("Exports", isDirectory: true)
        let baseName = "\(session.name)_original_frames"
        let exports = (try? FileManager.default.contentsOfDirectory(
            at: exportsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        )) ?? []

        return exports.filter { url in
            url.lastPathComponent.hasPrefix(baseName) &&
                url.pathExtension.lowercased() == "zip" &&
                completedArchiveExists(at: url)
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func exportOriginalFramesArchivePlan(
        for session: TimelapseSession,
        maxFramesPerArchive: Int,
        maxArchiveBytes: UInt64
    ) throws -> OriginalFrameExportPlan {
        let fileManager = FileManager.default
        let projectDirectory = session.directoryURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let exportsDirectory = projectDirectory.appendingPathComponent("Exports", isDirectory: true)
        try fileManager.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)

        let frames = originalFrameURLs(in: session)
        guard !frames.isEmpty else {
            throw TimelapseStoreError.noOriginalFrames
        }

        try ensureEnoughSpaceForOriginalFrameExport(frames, exportsDirectory: exportsDirectory)

        let baseName = "\(session.name)_original_frames"
        let previousExports = (try? fileManager.contentsOfDirectory(
            at: exportsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey]
        )) ?? []
        for url in previousExports where url.lastPathComponent.hasPrefix(baseName) && url.pathExtension == "zip" {
            try? fileManager.removeItem(at: url)
        }

        let chunks = originalFrameArchiveChunks(
            frames,
            maxFramesPerArchive: maxFramesPerArchive,
            maxArchiveBytes: maxArchiveBytes
        )
        guard !chunks.isEmpty else {
            throw TimelapseStoreError.noOriginalFrames
        }

        let digits = max(3, String(chunks.count).count)
        let batches = chunks.enumerated().map { index, chunk in
            let fileName: String
            if chunks.count == 1 {
                fileName = "\(baseName).zip"
            } else {
                fileName = "\(baseName)_part_\(String(format: "%0*d", digits, index + 1))_of_\(String(format: "%0*d", digits, chunks.count)).zip"
            }

            let zipURL = exportsDirectory.appendingPathComponent(fileName)
            return OriginalFrameArchiveBatch(index: index + 1, frames: chunk, url: zipURL)
        }

        return OriginalFrameExportPlan(totalFrames: frames.count, batches: batches)
    }

    private static func completedArchiveExists(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return false
        }

        return size > 0
    }

    private static func originalFrameURLs(in session: TimelapseSession) -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: session.directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return []
        }

        return files.filter { url in
            url.lastPathComponent.hasPrefix("frame_") &&
            url.pathExtension.lowercased() == "jpg" &&
            ((try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true)
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func originalFrameArchiveChunks(
        _ frames: [URL],
        maxFramesPerArchive: Int,
        maxArchiveBytes: UInt64
    ) -> [[URL]] {
        let maxFrames = max(maxFramesPerArchive, 1)
        let maxBytes = max(maxArchiveBytes, 1)
        var chunks: [[URL]] = []
        var current: [URL] = []
        var currentBytes: UInt64 = 0

        for frame in frames {
            let frameSize = UInt64((try? frame.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            let wouldExceedByteLimit = frameSize >= maxBytes || currentBytes > maxBytes - frameSize
            let shouldStartNextArchive = !current.isEmpty &&
                (current.count >= maxFrames || wouldExceedByteLimit)

            if shouldStartNextArchive {
                chunks.append(current)
                current = []
                currentBytes = 0
            }

            current.append(frame)
            currentBytes += frameSize
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }

    private static func ensureEnoughSpaceForOriginalFrameExport(
        _ frames: [URL],
        exportsDirectory: URL
    ) throws {
        let requiredBytes = frames.reduce(UInt64(0)) { total, frame in
            total + UInt64((try? frame.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        } + (128 * 1024 * 1024)

        let values = try? exportsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values?.volumeAvailableCapacityForImportantUsage else {
            return
        }

        if UInt64(max(available, 0)) < requiredBytes {
            throw TimelapseStoreError.notEnoughStorageForExport
        }
    }

    func deleteSession(_ session: TimelapseSession) throws {
        guard session.projectID == project.id else {
            throw TimelapseStoreError.sessionDoesNotBelongToProject
        }

        guard isSafeSessionDirectory(session.directoryURL) else {
            throw TimelapseStoreError.unsafeSessionPath
        }

        if fileManager.fileExists(atPath: session.directoryURL.path) {
            try fileManager.removeItem(at: session.directoryURL)
        }

        let zipURL = exportsDirectory.appendingPathComponent("\(session.name).zip")
        if fileManager.fileExists(atPath: zipURL.path) {
            try fileManager.removeItem(at: zipURL)
        }
    }

    func renderVideo(
        for session: TimelapseSession,
        settings: WorkflowVideoSettings = .repeatableDefault
    ) async throws -> URL {
        let frames = frameURLs(in: session)
        let outputURL = videoURL(for: session)
        try await TimelapseVideoRenderer().render(frames: frames, outputURL: outputURL, settings: settings)
        return outputURL
    }

    func videoURL(for session: TimelapseSession) -> URL {
        session.directoryURL.appendingPathComponent("timelapse.mp4")
    }

    func videoClipURL(for session: TimelapseSession) -> URL {
        session.directoryURL.appendingPathComponent("video.mov")
    }

    private func astroCaptureMetadataURL(for session: TimelapseSession) -> URL {
        session.directoryURL.appendingPathComponent("astro_capture.json")
    }

    private func existingVideoURL(for session: TimelapseSession) -> URL? {
        let url = videoURL(for: session)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    private func existingVideoClipURL(for session: TimelapseSession) -> URL? {
        let url = videoClipURL(for: session)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func deleteProject() throws {
        if fileManager.fileExists(atPath: project.directoryURL.path) {
            try fileManager.removeItem(at: project.directoryURL)
        }
    }

    private func writeManifest(for session: TimelapseSession) throws {
        let manifestURL = session.directoryURL.appendingPathComponent("manifest.json")
        var manifest = ((try? Data(contentsOf: manifestURL))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
        manifest["schemaVersion"] = 3
        manifest["id"] = session.id.uuidString
        manifest["projectId"] = session.projectID.uuidString
        manifest["projectName"] = project.name
        manifest["module"] = session.module.rawValue
        manifest["captureKind"] = session.captureKind.rawValue
        manifest["name"] = session.name
        manifest["createdAt"] = ISO8601DateFormatter().string(from: session.createdAt)
        manifest["format"] = "original_jpeg_sequence"
        if manifest["frameSummary"] == nil {
            manifest["frameSummary"] = [
                "count": 0,
                "nextFrameIndex": 1,
                "knownBytes": 0
            ]
            manifest["inventoryState"] = "dirty"
            manifest["generation"] = 0
        }

        if let referenceMotion = session.referenceMotion {
            manifest["referenceMotion"] = [
                "x": referenceMotion.x,
                "y": referenceMotion.y,
                "z": referenceMotion.z
            ]
        }

        if let referenceGeoPose = session.referenceGeoPose {
            var geoPose: [String: Any] = [
                "latitude": referenceGeoPose.latitude,
                "longitude": referenceGeoPose.longitude,
                "horizontalAccuracy": referenceGeoPose.horizontalAccuracy,
                "timestamp": ISO8601DateFormatter().string(from: referenceGeoPose.timestamp)
            ]
            if let heading = referenceGeoPose.heading {
                geoPose["heading"] = heading
            }
            manifest["referenceGeoPose"] = geoPose
        }

        if let referenceOrientation = session.referenceOrientation {
            manifest["referenceOrientation"] = referenceOrientation.rawValue
        }

        if let cameraLens = session.cameraLens {
            manifest["cameraLens"] = cameraLens.rawValue
        }

        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: manifestURL, options: [.atomic])
    }

    private func isSafeSessionDirectory(_ url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        let standardizedSessionsDirectory = sessionsDirectory.standardizedFileURL

        return standardizedURL.deletingLastPathComponent().path == standardizedSessionsDirectory.path &&
            standardizedURL.lastPathComponent.hasPrefix("session_")
    }

    private func loadSessions() throws -> [TimelapseSession] {
        guard fileManager.fileExists(atPath: sessionsDirectory.path) else {
            return []
        }

        let directories = try fileManager.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        )

        return directories.compactMap { directory in
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }

            let manifestURL = directory.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(SessionManifest.self, from: data),
                  let id = UUID(uuidString: manifest.id),
                  let projectID = UUID(uuidString: manifest.projectId),
                  let createdAt = ISO8601DateFormatter().date(from: manifest.createdAt) else {
                return nil
            }

            return TimelapseSession(
                id: id,
                projectID: projectID,
                module: CameraModule(rawValue: manifest.module) ?? project.module,
                captureKind: RepeatableCaptureKind(rawValue: manifest.captureKind ?? "") ?? .timelapse,
                referenceMotion: manifest.referenceMotion,
                referenceGeoPose: manifest.referenceGeoPose,
                referenceOrientation: CaptureDisplayOrientation(rawValue: manifest.referenceOrientation ?? ""),
                cameraLens: RepeatableCameraLens(rawValue: manifest.cameraLens ?? ""),
                name: manifest.name,
                directoryURL: directory,
                createdAt: createdAt
            )
        }
    }
}

struct MotionAttitude: Codable, Equatable, Hashable {
    let x: Double
    let y: Double
    let z: Double

    func delta(from reference: MotionAttitude) -> MotionAttitude {
        MotionAttitude(
            x: Self.normalizedDegrees(x - reference.x),
            y: Self.normalizedDegrees(y - reference.y),
            z: Self.normalizedDegrees(z - reference.z)
        )
    }

    private static func normalizedDegrees(_ degrees: Double) -> Double {
        var value = degrees
        while value > 180 { value -= 360 }
        while value < -180 { value += 360 }
        return value
    }
}

struct GeoPose: Codable, Equatable, Hashable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let heading: Double?
    let timestamp: Date

    init(
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double,
        heading: Double?,
        timestamp: Date
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.heading = heading
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        horizontalAccuracy = try container.decode(Double.self, forKey: .horizontalAccuracy)
        heading = try container.decodeIfPresent(Double.self, forKey: .heading)

        let timestampString = try container.decode(String.self, forKey: .timestamp)
        timestamp = ISO8601DateFormatter().date(from: timestampString) ?? Date.distantPast
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(horizontalAccuracy, forKey: .horizontalAccuracy)
        try container.encodeIfPresent(heading, forKey: .heading)
        try container.encode(ISO8601DateFormatter().string(from: timestamp), forKey: .timestamp)
    }

    func offsetMeters(from reference: GeoPose) -> CGSize {
        let metersPerDegreeLatitude = 111_132.0
        let latitudeRadians = reference.latitude * .pi / 180
        let metersPerDegreeLongitude = 111_320.0 * cos(latitudeRadians)
        let east = (longitude - reference.longitude) * metersPerDegreeLongitude
        let north = (latitude - reference.latitude) * metersPerDegreeLatitude
        return CGSize(width: east, height: north)
    }

    func distanceMeters(from reference: GeoPose) -> Double {
        let offset = offsetMeters(from: reference)
        let east = Double(offset.width)
        let north = Double(offset.height)
        return sqrt(east * east + north * north)
    }

    private enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case horizontalAccuracy
        case heading
        case timestamp
    }
}

enum CaptureDisplayOrientation: String, Codable, Equatable, Hashable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight

    var isLandscape: Bool {
        self == .landscapeLeft || self == .landscapeRight
    }

    var videoRotationAngle: CGFloat {
        switch self {
        case .portrait:
            return 90
        case .portraitUpsideDown:
            return 270
        case .landscapeLeft:
            return 180
        case .landscapeRight:
            return 0
        }
    }
}

enum RepeatableCaptureKind: String, Identifiable, Codable, Hashable {
    case timelapse
    case video
    case photo

    var id: String { rawValue }

    static let captureOptions: [RepeatableCaptureKind] = [.video, .timelapse]

    var title: String {
        switch self {
        case .timelapse:
            return "Timelapse"
        case .video:
            return "Video"
        case .photo:
            return "Foto"
        }
    }

    var systemImage: String {
        switch self {
        case .timelapse:
            return "timer"
        case .video:
            return "video"
        case .photo:
            return "camera"
        }
    }
}

private enum TimelapseStoreError: LocalizedError {
    case sessionDoesNotBelongToProject
    case unsafeSessionPath
    case noOriginalFrames
    case notEnoughStorageForExport
    case referenceImageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .sessionDoesNotBelongToProject:
            return "este timelapse nao pertence ao projeto atual"
        case .unsafeSessionPath:
            return "o caminho deste timelapse nao parece seguro para exclusao"
        case .noOriginalFrames:
            return "nenhum frame original encontrado para exportar"
        case .notEnoughStorageForExport:
            return "espaco insuficiente para exportar os frames originais"
        case .referenceImageEncodingFailed:
            return "Nao foi possivel preparar a imagem de referencia."
        }
    }
}

private struct SessionManifest: Decodable {
    let id: String
    let projectId: String
    let module: String
    let captureKind: String?
    let referenceMotion: MotionAttitude?
    let referenceGeoPose: GeoPose?
    let referenceOrientation: String?
    let cameraLens: String?
    let name: String
    let createdAt: String
}

private extension UIImage {
    func normalizedForStorage() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

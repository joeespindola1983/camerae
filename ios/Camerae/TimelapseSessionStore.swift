import CoreGraphics
import Foundation

struct TimelapseSession: Identifiable, Equatable, Hashable {
    let id: UUID
    let projectID: UUID
    let module: CameraModule
    let captureKind: RepeatableCaptureKind
    let referenceMotion: MotionAttitude?
    let referenceGeoPose: GeoPose?
    let referenceOrientation: CaptureDisplayOrientation?
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

    var id: UUID { session.id }
}

final class TimelapseSessionStore {
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

    func createSession(captureKind: RepeatableCaptureKind = .timelapse) throws -> TimelapseSession {
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

    func sessionSummaries() -> [TimelapseSessionSummary] {
        guard let sessions = try? loadSessions() else {
            return []
        }

        return sessions
            .sorted { $0.createdAt > $1.createdAt }
            .map { session in
                TimelapseSessionSummary(
                    session: session,
                    captureKind: session.captureKind,
                    frameCount: frameCount(in: session),
                    referenceFrameURL: firstFrameURL(in: session),
                    videoURL: existingVideoURL(for: session),
                    videoClipURL: existingVideoClipURL(for: session)
                )
            }
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

    func renderVideo(for session: TimelapseSession, fps: Int = 24) async throws -> URL {
        let frames = frameURLs(in: session)
        let outputURL = videoURL(for: session)
        try await TimelapseVideoRenderer().render(frames: frames, outputURL: outputURL, fps: fps)
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
        var manifest: [String: Any] = [
            "id": session.id.uuidString,
            "projectId": session.projectID.uuidString,
            "projectName": project.name,
            "module": session.module.rawValue,
            "captureKind": session.captureKind.rawValue,
            "name": session.name,
            "createdAt": ISO8601DateFormatter().string(from: session.createdAt),
            "format": "original_jpeg_sequence"
        ]

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

        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: session.directoryURL.appendingPathComponent("manifest.json"), options: [.atomic])
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

    static let captureOptions: [RepeatableCaptureKind] = [.timelapse, .video]

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

    var errorDescription: String? {
        switch self {
        case .sessionDoesNotBelongToProject:
            return "este timelapse nao pertence ao projeto atual"
        case .unsafeSessionPath:
            return "o caminho deste timelapse nao parece seguro para exclusao"
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
    let name: String
    let createdAt: String
}

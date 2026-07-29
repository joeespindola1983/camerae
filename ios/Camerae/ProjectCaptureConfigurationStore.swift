import CameraeCore
import Foundation

struct ProjectCaptureConfigurationStore {
    private static let schemaVersion = 2
    private let fileManager: FileManager
    private let fileURL: URL

    init(
        projectDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        fileURL = projectDirectory.appendingPathComponent(
            "capture_configuration.json",
            isDirectory: false
        )
    }

    func load() throws -> CameraeNextCaptureConfiguration? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let document = try Self.decoder.decode(
            ProjectCaptureConfigurationDocument.self,
            from: Data(contentsOf: fileURL)
        )
        guard (1...Self.schemaVersion).contains(document.schemaVersion) else {
            throw ProjectCaptureConfigurationError.unsupportedSchema(document.schemaVersion)
        }
        return document.configuration
    }

    @discardableResult
    func saveInitial(
        _ configuration: CameraeNextCaptureConfiguration
    ) throws -> CameraeNextCaptureConfiguration {
        if let existing = try load() {
            return existing
        }
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try save(configuration, origin: .initialCapture)
        return configuration
    }

    @discardableResult
    func loadOrMigrate(
        module: CameraModule,
        summaries: [TimelapseSessionSummary]
    ) throws -> CameraeNextCaptureConfiguration? {
        if let existing = try load(), existing.module == module {
            return existing
        }
        guard let migrated = LegacyProjectCaptureConfigurationMigration.infer(
            module: module,
            summaries: summaries
        ) else {
            return nil
        }
        try save(migrated, origin: .migratedLegacy)
        return migrated
    }

    private func save(
        _ configuration: CameraeNextCaptureConfiguration,
        origin: ProjectCaptureConfigurationOrigin
    ) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let document = ProjectCaptureConfigurationDocument(
            schemaVersion: Self.schemaVersion,
            origin: origin,
            configuration: configuration
        )
        try Self.encoder.encode(document).write(to: fileURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()
}

private struct ProjectCaptureConfigurationDocument: Codable {
    let schemaVersion: Int
    let origin: ProjectCaptureConfigurationOrigin?
    let configuration: CameraeNextCaptureConfiguration
}

enum ProjectCaptureConfigurationOrigin: String, Codable, Equatable {
    case initialCapture
    case migratedLegacy
}

enum LegacyProjectCaptureConfigurationMigration {
    static func infer(
        module: CameraModule,
        summaries: [TimelapseSessionSummary]
    ) -> CameraeNextCaptureConfiguration? {
        guard let firstCapture = summaries
            .filter({ $0.session.purpose == .capture && $0.containsCapturedMediaForMigration })
            .min(by: { $0.session.createdAt < $1.session.createdAt }) else {
            return nil
        }

        var configuration = module == .astrophotography
            ? CameraeNextCaptureConfiguration.astroDefault
            : CameraeNextCaptureConfiguration.repeatableDefault
        configuration.repeatableKind = firstCapture.captureKind
        configuration.cameraLens = firstCapture.session.cameraLens ?? .wide
        configuration.cameraZoomFactor = max(firstCapture.session.cameraZoomFactor ?? 1, 1)

        if let sourceFormat = firstCapture.inferredSourceFormat {
            configuration.sourceFormat = sourceFormat
        }
        if let duration = firstCapture.captureDuration, duration > 0 {
            switch firstCapture.captureKind {
            case .video:
                configuration.videoDurationSeconds = max(1, Int(duration.rounded()))
            case .timelapse:
                configuration.durationMinutes = max(1, Int((duration / 60).rounded(.up)))
                if firstCapture.frameCount > 1 {
                    configuration.intervalSeconds = max(
                        0.1,
                        duration / Double(firstCapture.frameCount - 1)
                    )
                }
            case .photo:
                break
            }
        }
        if module == .astrophotography, firstCapture.captureKind == .photo {
            configuration.astroPhotoStackCount = .nearest(to: firstCapture.frameCount)
        }
        return configuration
    }
}

private extension TimelapseSessionSummary {
    var containsCapturedMediaForMigration: Bool {
        frameCount > 0 || videoURL != nil || videoClipURL != nil || isAstroProcessed
    }

    var inferredSourceFormat: CaptureSourceFormat? {
        guard let ext = referenceFrameURL?.pathExtension.lowercased() else { return nil }
        switch ext {
        case "dng": return .dng
        case "heic", "heif": return .heic
        case "jpg", "jpeg": return .jpeg
        default: return nil
        }
    }
}

enum ProjectCaptureConfigurationError: LocalizedError, Equatable {
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema:
            "A configuração deste projeto foi criada por uma versão mais recente do Camerae."
        }
    }
}

extension CameraeNextCaptureConfiguration {
    var projectSummary: String {
        let kind = switch repeatableKind {
        case .photo: module == .astrophotography ? "FOTO ASTRO" : "FOTO"
        case .timelapse: "TIMELAPSE"
        case .video: "VÍDEO"
        }
        let detail = switch repeatableKind {
        case .video:
            "\(videoSettings.resolution.label.uppercased()) · \(videoSettings.fps) FPS"
        case .timelapse:
            "\(Int(intervalSeconds)) S · \(sourceFormat.displayName.uppercased())"
        case .photo:
            module == .astrophotography
                ? "\(astroPhotoStackCount.rawValue) \(sourceFormat.displayName.uppercased())"
                : sourceFormat.displayName.uppercased()
        }
        return "\(kind) · \(detail)"
    }
}

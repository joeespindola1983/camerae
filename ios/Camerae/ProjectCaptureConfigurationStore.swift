import CameraeCore
import Foundation

struct ProjectCaptureConfigurationStore {
    private static let schemaVersion = 3
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

    func loadProfile() throws -> ProjectCaptureProfile? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let envelope = try Self.decoder.decode(ProjectCaptureConfigurationEnvelope.self, from: data)
        guard (1...Self.schemaVersion).contains(envelope.schemaVersion) else {
            throw ProjectCaptureConfigurationError.unsupportedSchema(envelope.schemaVersion)
        }
        if envelope.schemaVersion == Self.schemaVersion {
            return try Self.decoder.decode(
                ProjectCaptureConfigurationDocument.self,
                from: data
            ).profile
        }
        let legacy = try Self.decoder.decode(
            LegacyProjectCaptureConfigurationDocument.self,
            from: data
        )
        return ProjectCaptureProfile(initialConfiguration: legacy.configuration)
    }

    func load() throws -> CameraeNextCaptureConfiguration? {
        try loadProfile()?.selectedConfiguration
    }

    @discardableResult
    func saveDefaults(
        _ configuration: CameraeNextCaptureConfiguration
    ) throws -> CameraeNextCaptureConfiguration {
        var profile: ProjectCaptureProfile
        let origin: ProjectCaptureConfigurationOrigin
        if let existing = try loadProfile(), existing.module == configuration.module {
            profile = existing
            origin = .updatedDefaults
        } else {
            profile = ProjectCaptureProfile(initialConfiguration: configuration)
            origin = .initialCapture
        }
        let normalized = profile.updateDefaults(configuration)
        try save(profile, origin: origin)
        return normalized
    }

    @discardableResult
    func saveInitial(
        _ configuration: CameraeNextCaptureConfiguration
    ) throws -> CameraeNextCaptureConfiguration {
        try saveDefaults(configuration)
    }

    @discardableResult
    func loadProfileOrMigrate(
        module: CameraModule,
        summaries: [TimelapseSessionSummary]
    ) throws -> ProjectCaptureProfile? {
        if let existing = try loadProfile(), existing.module == module {
            if try storedSchemaVersion() < Self.schemaVersion {
                try save(existing, origin: .migratedConfiguration)
            }
            return existing
        }
        guard let migrated = LegacyProjectCaptureConfigurationMigration.infer(
            module: module,
            summaries: summaries
        ) else {
            return nil
        }
        let profile = ProjectCaptureProfile(initialConfiguration: migrated)
        try save(profile, origin: .migratedLegacy)
        return profile
    }

    @discardableResult
    func loadOrMigrate(
        module: CameraModule,
        summaries: [TimelapseSessionSummary]
    ) throws -> CameraeNextCaptureConfiguration? {
        try loadProfileOrMigrate(module: module, summaries: summaries)?.selectedConfiguration
    }

    private func save(
        _ profile: ProjectCaptureProfile,
        origin: ProjectCaptureConfigurationOrigin
    ) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let document = ProjectCaptureConfigurationDocument(
            schemaVersion: Self.schemaVersion,
            origin: origin,
            profile: profile
        )
        try Self.encoder.encode(document).write(to: fileURL, options: .atomic)
    }

    private func storedSchemaVersion() throws -> Int {
        let data = try Data(contentsOf: fileURL)
        return try Self.decoder.decode(
            ProjectCaptureConfigurationEnvelope.self,
            from: data
        ).schemaVersion
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()
}

struct ProjectCaptureHardware: Codable, Equatable, Hashable, Sendable {
    var cameraLens: RepeatableCameraLens
    var cameraZoomFactor: Double

    init(cameraLens: RepeatableCameraLens, cameraZoomFactor: Double) {
        self.cameraLens = cameraLens
        self.cameraZoomFactor = max(cameraZoomFactor, 1)
    }

    func applying(to configuration: CameraeNextCaptureConfiguration) -> CameraeNextCaptureConfiguration {
        var normalized = configuration
        normalized.cameraLens = cameraLens
        normalized.cameraZoomFactor = cameraZoomFactor
        return normalized
    }
}

struct ProjectCapturePresets: Codable, Equatable, Hashable, Sendable {
    var photo: CameraeNextCaptureConfiguration
    var timelapse: CameraeNextCaptureConfiguration
    var video: CameraeNextCaptureConfiguration

    subscript(kind: RepeatableCaptureKind) -> CameraeNextCaptureConfiguration {
        get {
            switch kind {
            case .photo: photo
            case .timelapse: timelapse
            case .video: video
            }
        }
        set {
            switch kind {
            case .photo: photo = newValue
            case .timelapse: timelapse = newValue
            case .video: video = newValue
            }
        }
    }
}

struct ProjectCaptureProfile: Codable, Equatable, Hashable, Sendable {
    var module: CameraModule
    var hardware: ProjectCaptureHardware
    var selectedKind: RepeatableCaptureKind
    var presets: ProjectCapturePresets

    init(initialConfiguration: CameraeNextCaptureConfiguration) {
        module = initialConfiguration.module
        hardware = ProjectCaptureHardware(
            cameraLens: initialConfiguration.cameraLens,
            cameraZoomFactor: initialConfiguration.cameraZoomFactor
        )
        selectedKind = initialConfiguration.repeatableKind
        let photo = Self.defaultConfiguration(
            module: module,
            kind: .photo,
            hardware: hardware
        )
        let timelapse = Self.defaultConfiguration(
            module: module,
            kind: .timelapse,
            hardware: hardware
        )
        let video = Self.defaultConfiguration(
            module: module,
            kind: .video,
            hardware: hardware
        )
        presets = ProjectCapturePresets(photo: photo, timelapse: timelapse, video: video)
        presets[selectedKind] = normalized(initialConfiguration, for: selectedKind)
    }

    var selectedConfiguration: CameraeNextCaptureConfiguration {
        configuration(for: selectedKind)
    }

    func configuration(for kind: RepeatableCaptureKind) -> CameraeNextCaptureConfiguration {
        normalized(presets[kind], for: kind)
    }

    @discardableResult
    mutating func updateDefaults(
        _ configuration: CameraeNextCaptureConfiguration
    ) -> CameraeNextCaptureConfiguration {
        let kind = configuration.repeatableKind
        let value = normalized(configuration, for: kind)
        presets[kind] = value
        selectedKind = kind
        return value
    }

    private func normalized(
        _ configuration: CameraeNextCaptureConfiguration,
        for kind: RepeatableCaptureKind
    ) -> CameraeNextCaptureConfiguration {
        var result = hardware.applying(to: configuration)
        result.module = module
        result.repeatableKind = kind
        return result
    }

    private static func defaultConfiguration(
        module: CameraModule,
        kind: RepeatableCaptureKind,
        hardware: ProjectCaptureHardware
    ) -> CameraeNextCaptureConfiguration {
        var configuration = module == .astrophotography
            ? CameraeNextCaptureConfiguration.astroDefault
            : CameraeNextCaptureConfiguration.repeatableDefault
        configuration.repeatableKind = kind
        return hardware.applying(to: configuration)
    }
}

private struct ProjectCaptureConfigurationEnvelope: Decodable {
    let schemaVersion: Int
}

private struct ProjectCaptureConfigurationDocument: Codable {
    let schemaVersion: Int
    let origin: ProjectCaptureConfigurationOrigin?
    let profile: ProjectCaptureProfile
}

private struct LegacyProjectCaptureConfigurationDocument: Codable {
    let schemaVersion: Int
    let origin: ProjectCaptureConfigurationOrigin?
    let configuration: CameraeNextCaptureConfiguration
}

enum ProjectCaptureConfigurationOrigin: String, Codable, Equatable {
    case initialCapture
    case migratedLegacy
    case migratedConfiguration
    case updatedDefaults
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

extension ProjectCaptureProfile {
    var projectSummary: String {
        let zoom = hardware.cameraZoomFactor.formatted(
            .number.locale(.current).precision(.fractionLength(0...1))
        )
        return "\(CameraeL10n.photo.uppercased()) · \(CameraeL10n.video.uppercased()) · \(CameraeL10n.timelapse.uppercased()) · \(hardware.cameraLens.title.uppercased()) \(zoom)×"
    }
}

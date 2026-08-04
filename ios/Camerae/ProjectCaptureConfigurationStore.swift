import CameraeCore
import Foundation

struct ProjectCaptureConfigurationStore {
    private static let schemaVersion = 4
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
        if envelope.schemaVersion >= 3 {
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
        if var existing = try loadProfile(), existing.module == module {
            let storedVersion = try storedSchemaVersion()
            let original = existing
            existing.confirmHardwareIfNeeded(from: summaries)
            existing.refreshVideoDefault(from: summaries)
            if storedVersion < Self.schemaVersion || existing != original {
                try save(
                    existing,
                    origin: storedVersion < Self.schemaVersion
                        ? .migratedConfiguration
                        : .updatedDefaults
                )
            }
            return existing
        }
        guard let migrated = LegacyProjectCaptureConfigurationMigration.infer(
            module: module,
            summaries: summaries
        ) else {
            return nil
        }
        let profile = ProjectCaptureProfile(
            initialConfiguration: migrated,
            isHardwareLocked: true
        )
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
    private(set) var isHardwareLocked: Bool
    var selectedKind: RepeatableCaptureKind
    var presets: ProjectCapturePresets

    init(
        initialConfiguration: CameraeNextCaptureConfiguration,
        isHardwareLocked: Bool = false
    ) {
        module = initialConfiguration.module
        hardware = ProjectCaptureHardware(
            cameraLens: initialConfiguration.cameraLens,
            cameraZoomFactor: initialConfiguration.cameraZoomFactor
        )
        self.isHardwareLocked = isHardwareLocked
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
        if !isHardwareLocked {
            applyHardware(ProjectCaptureHardware(
                cameraLens: configuration.cameraLens,
                cameraZoomFactor: configuration.cameraZoomFactor
            ))
        }
        let kind = configuration.repeatableKind
        let value = normalized(configuration, for: kind)
        presets[kind] = value
        selectedKind = kind
        return value
    }

    mutating func confirmHardwareIfNeeded(from summaries: [TimelapseSessionSummary]) {
        guard !isHardwareLocked,
              let firstCapture = summaries
                .filter({
                    ($0.session.purpose == .capture || $0.session.cameraLens != nil) &&
                        $0.containsCapturedMediaForMigration
                })
                .min(by: { $0.session.createdAt < $1.session.createdAt }) else {
            return
        }
        applyHardware(ProjectCaptureHardware(
            cameraLens: firstCapture.session.cameraLens ?? .wide,
            cameraZoomFactor: firstCapture.session.cameraZoomFactor ?? 1
        ))
        isHardwareLocked = true
    }

    mutating func refreshVideoDefault(from summaries: [TimelapseSessionSummary]) {
        guard let latestVideo = summaries
            .filter({
                $0.captureKind == .video
                    && ($0.videoURL != nil || $0.videoClipURL != nil || $0.alignedVideoURL != nil)
                    && ($0.captureDuration ?? 0) > 0
            })
            .max(by: { $0.session.createdAt < $1.session.createdAt }),
              let duration = latestVideo.captureDuration else {
            return
        }
        var video = configuration(for: .video)
        video.videoDurationSeconds = CameraeNextVideoDurationPolicy.normalized(duration)
        presets[.video] = normalized(video, for: .video)
    }

    private func normalized(
        _ configuration: CameraeNextCaptureConfiguration,
        for kind: RepeatableCaptureKind
    ) -> CameraeNextCaptureConfiguration {
        var result = hardware.applying(to: configuration)
        result.module = module
        result.repeatableKind = kind
        if kind == .video {
            result.videoDurationSeconds = CameraeNextVideoDurationPolicy.normalized(
                result.videoDurationSeconds
            )
        }
        return result
    }

    private mutating func applyHardware(_ hardware: ProjectCaptureHardware) {
        self.hardware = hardware
        presets.photo = hardware.applying(to: presets.photo)
        presets.timelapse = hardware.applying(to: presets.timelapse)
        presets.video = hardware.applying(to: presets.video)
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

    private enum CodingKeys: String, CodingKey {
        case module
        case hardware
        case isHardwareLocked
        case selectedKind
        case presets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        module = try container.decode(CameraModule.self, forKey: .module)
        hardware = try container.decode(ProjectCaptureHardware.self, forKey: .hardware)
        isHardwareLocked = try container.decodeIfPresent(Bool.self, forKey: .isHardwareLocked) ?? false
        selectedKind = try container.decode(RepeatableCaptureKind.self, forKey: .selectedKind)
        presets = try container.decode(ProjectCapturePresets.self, forKey: .presets)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(module, forKey: .module)
        try container.encode(hardware, forKey: .hardware)
        try container.encode(isHardwareLocked, forKey: .isHardwareLocked)
        try container.encode(selectedKind, forKey: .selectedKind)
        try container.encode(presets, forKey: .presets)
    }
}

enum CameraeNextVideoDurationPolicy {
    static let presetSeconds = [30, 60, 120]
    private static let presetToleranceSeconds = 2

    static func normalized(_ seconds: Int) -> Int {
        let positiveSeconds = max(1, seconds)
        return presetSeconds.first(where: {
            abs($0 - positiveSeconds) <= presetToleranceSeconds
        }) ?? positiveSeconds
    }

    static func normalized(_ duration: TimeInterval) -> Int {
        normalized(max(1, Int(duration.rounded())))
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
                configuration.videoDurationSeconds = CameraeNextVideoDurationPolicy.normalized(duration)
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

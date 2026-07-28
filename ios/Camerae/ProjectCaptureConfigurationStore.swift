import Foundation

struct ProjectCaptureConfigurationStore {
    private static let schemaVersion = 1
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
        guard document.schemaVersion == Self.schemaVersion else {
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
        let document = ProjectCaptureConfigurationDocument(
            schemaVersion: Self.schemaVersion,
            configuration: configuration
        )
        try Self.encoder.encode(document).write(to: fileURL, options: .atomic)
        return configuration
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
    let configuration: CameraeNextCaptureConfiguration
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

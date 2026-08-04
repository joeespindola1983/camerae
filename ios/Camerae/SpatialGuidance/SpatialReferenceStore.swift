import Foundation

struct SpatialReferenceBundle: Equatable, Sendable {
    let manifest: SpatialReferenceManifest
    let worldMapData: Data
    let keyframes: [Data]
}

struct SpatialReferenceReuseCandidate: Equatable {
    let sourceProject: CameraProject
    let bundle: SpatialReferenceBundle
}

enum SpatialReferenceReuseResolver {
    static func latest(
        projects: [CameraProject],
        excluding projectID: UUID,
        deviceModelIdentifier: String
    ) -> SpatialReferenceReuseCandidate? {
        let compatible = projects
            .filter { $0.id != projectID && $0.module == .repeatable }
            .compactMap { project -> (CameraProject, SpatialReferenceManifest)? in
                guard let manifest = try? SpatialReferenceStore(
                    projectDirectory: project.directoryURL
                ).loadManifest(),
                manifest.deviceModelIdentifier == deviceModelIdentifier else {
                    return nil
                }
                return (project, manifest)
            }
            .sorted { $0.1.createdAt > $1.1.createdAt }
        for candidate in compatible {
            if let bundle = try? SpatialReferenceStore(
                projectDirectory: candidate.0.directoryURL
            ).load() {
                return .init(sourceProject: candidate.0, bundle: bundle)
            }
        }
        return nil
    }
}

enum SpatialReferenceStoreError: Error, Equatable {
    case unsupportedSchema(Int)
    case missingWorldMap
    case missingKeyframe(String)
    case invalidManifest
}

struct SpatialReferenceStore {
    private let fileManager: FileManager
    private let projectDirectory: URL

    init(
        projectDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.projectDirectory = projectDirectory
        self.fileManager = fileManager
    }

    var hasReference: Bool {
        fileManager.fileExists(atPath: referenceDirectory.path)
    }

    func load() throws -> SpatialReferenceBundle? {
        try loadBundle(at: referenceDirectory)
    }

    func loadManifest() throws -> SpatialReferenceManifest? {
        try loadManifest(at: referenceDirectory)
    }

    func loadPrevious() throws -> SpatialReferenceBundle? {
        try loadBundle(at: previousDirectory)
    }

    func updateAppearance(_ appearance: SpatialGuidanceAppearance) throws {
        guard let current = try load() else {
            throw SpatialReferenceStoreError.invalidManifest
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(
            current.manifest.replacingAppearance(appearance)
        ).write(
            to: referenceDirectory.appendingPathComponent("manifest.json"),
            options: .atomic
        )
    }

    func save(
        manifest: SpatialReferenceManifest,
        worldMapData: Data,
        keyframes: [Data]
    ) throws {
        try fileManager.createDirectory(
            at: projectDirectory,
            withIntermediateDirectories: true
        )
        let staging = projectDirectory.appendingPathComponent(
            ".spatial-reference-staging-\(UUID().uuidString)",
            isDirectory: true
        )
        let backup = projectDirectory.appendingPathComponent(
            ".spatial-reference-backup-\(UUID().uuidString)",
            isDirectory: true
        )
        defer {
            try? fileManager.removeItem(at: staging)
            try? fileManager.removeItem(at: backup)
        }

        try write(
            manifest: manifest,
            worldMapData: worldMapData,
            keyframes: keyframes,
            to: staging
        )
        _ = try loadBundle(at: staging)

        if fileManager.fileExists(atPath: referenceDirectory.path) {
            let previous = staging.appendingPathComponent("previous", isDirectory: true)
            try fileManager.copyItem(at: referenceDirectory, to: previous)
            let nestedPrevious = previous.appendingPathComponent("previous", isDirectory: true)
            if fileManager.fileExists(atPath: nestedPrevious.path) {
                try fileManager.removeItem(at: nestedPrevious)
            }
            try fileManager.moveItem(at: referenceDirectory, to: backup)
        }

        do {
            try fileManager.moveItem(at: staging, to: referenceDirectory)
        } catch {
            if fileManager.fileExists(atPath: backup.path),
               !fileManager.fileExists(atPath: referenceDirectory.path) {
                try? fileManager.moveItem(at: backup, to: referenceDirectory)
            }
            throw error
        }
    }

    @discardableResult
    func importReference(
        _ bundle: SpatialReferenceBundle,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        cameraLens: RepeatableCameraLens? = nil,
        cameraZoomFactor: Double? = nil
    ) throws -> SpatialReferenceBundle {
        let imported = SpatialReferenceBundle(
            manifest: bundle.manifest.reusedCopy(
                id: id,
                createdAt: createdAt,
                cameraLens: cameraLens,
                cameraZoomFactor: cameraZoomFactor
            ),
            worldMapData: bundle.worldMapData,
            keyframes: bundle.keyframes
        )
        try save(
            manifest: imported.manifest,
            worldMapData: imported.worldMapData,
            keyframes: imported.keyframes
        )
        return imported
    }

    func removeCurrentReference() throws {
        guard fileManager.fileExists(atPath: referenceDirectory.path) else { return }
        try fileManager.removeItem(at: referenceDirectory)
    }

    private var referenceDirectory: URL {
        projectDirectory.appendingPathComponent("spatial_reference", isDirectory: true)
    }

    private var previousDirectory: URL {
        referenceDirectory.appendingPathComponent("previous", isDirectory: true)
    }

    private func write(
        manifest: SpatialReferenceManifest,
        worldMapData: Data,
        keyframes: [Data],
        to directory: URL
    ) throws {
        guard manifest.schemaVersion == SpatialReferenceManifest.currentSchemaVersion else {
            throw SpatialReferenceStoreError.unsupportedSchema(manifest.schemaVersion)
        }
        guard manifest.keyframeFileNames.count == keyframes.count else {
            throw SpatialReferenceStoreError.invalidManifest
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let keyframesDirectory = directory.appendingPathComponent("keyframes", isDirectory: true)
        try fileManager.createDirectory(at: keyframesDirectory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(
            to: directory.appendingPathComponent("manifest.json"),
            options: .atomic
        )
        try worldMapData.write(
            to: directory.appendingPathComponent(manifest.worldMapFileName),
            options: .atomic
        )
        for (name, data) in zip(manifest.keyframeFileNames, keyframes) {
            try data.write(
                to: keyframesDirectory.appendingPathComponent(name),
                options: .atomic
            )
        }
    }

    private func loadBundle(at directory: URL) throws -> SpatialReferenceBundle? {
        guard let manifest = try loadManifest(at: directory) else { return nil }
        let worldMapURL = directory.appendingPathComponent(manifest.worldMapFileName)
        guard fileManager.fileExists(atPath: worldMapURL.path) else {
            throw SpatialReferenceStoreError.missingWorldMap
        }
        let keyframesDirectory = directory.appendingPathComponent("keyframes", isDirectory: true)
        let keyframes = try manifest.keyframeFileNames.map { name -> Data in
            let url = keyframesDirectory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path) else {
                throw SpatialReferenceStoreError.missingKeyframe(name)
            }
            return try Data(contentsOf: url)
        }
        return SpatialReferenceBundle(
            manifest: manifest,
            worldMapData: try Data(contentsOf: worldMapURL),
            keyframes: keyframes
        )
    }

    private func loadManifest(at directory: URL) throws -> SpatialReferenceManifest? {
        guard fileManager.fileExists(atPath: directory.path) else { return nil }
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw SpatialReferenceStoreError.invalidManifest
        }
        let manifestData = try Data(contentsOf: manifestURL)
        let envelope: SpatialReferenceEnvelope
        do {
            envelope = try JSONDecoder().decode(SpatialReferenceEnvelope.self, from: manifestData)
        } catch {
            throw SpatialReferenceStoreError.invalidManifest
        }
        guard envelope.schemaVersion <= SpatialReferenceManifest.currentSchemaVersion else {
            throw SpatialReferenceStoreError.unsupportedSchema(envelope.schemaVersion)
        }
        guard envelope.schemaVersion == SpatialReferenceManifest.currentSchemaVersion else {
            throw SpatialReferenceStoreError.unsupportedSchema(envelope.schemaVersion)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(SpatialReferenceManifest.self, from: manifestData)
        } catch {
            throw SpatialReferenceStoreError.invalidManifest
        }
    }
}

private struct SpatialReferenceEnvelope: Decodable {
    let schemaVersion: Int
}

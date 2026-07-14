import Foundation
import os

public actor ProjectCatalog {
    private static let schemaVersion = 3
    private static let logger = Logger(subsystem: "com.espindola.camerae", category: "ProjectCatalog")

    private let fileManager: FileManager
    private let rootDirectory: URL
    private let projectsDirectory: URL
    private let dateProvider: any DateProviding
    private let idProvider: any IDProviding
    private let codec: ProjectManifestCodec
    private var cachedProjects: [ProjectRecord]?
    private var cachedSummaries: [UUID: ProjectSummary] = [:]

    public nonisolated let indexURL: URL

    public init(
        rootDirectory: URL,
        fileManager: FileManager = .default,
        dateProvider: any DateProviding = SystemDateProvider(),
        idProvider: any IDProviding = SystemIDProvider()
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        self.dateProvider = dateProvider
        self.idProvider = idProvider
        codec = ProjectManifestCodec()
        projectsDirectory = rootDirectory.appendingPathComponent("Camerae Projects", isDirectory: true)
        indexURL = rootDirectory
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Camerae", isDirectory: true)
            .appendingPathComponent("catalog-v3.json")
    }

    public func load() throws -> ProjectCatalogSnapshot {
        if let cachedProjects {
            return ProjectCatalogSnapshot(projects: cachedProjects, source: .memory, summaries: cachedSummaries)
        }

        if let indexed = try? readIndex() {
            cachedProjects = indexed.projects
            cachedSummaries = indexed.summaries
            return ProjectCatalogSnapshot(projects: indexed.projects, source: .index, summaries: indexed.summaries)
        }

        let rebuilt = try rebuildFromManifests()
        cachedProjects = rebuilt.projects
        cachedSummaries = rebuilt.summaries
        try writeIndex(rebuilt.projects, summaries: rebuilt.summaries)
        return ProjectCatalogSnapshot(projects: rebuilt.projects, source: .rebuilt, summaries: rebuilt.summaries)
    }

    public func createProject(module: ProjectModule, name requestedName: String) async throws -> ProjectRecord {
        let existing = try load().projects
        let now = dateProvider.now()
        let id = await idProvider.next()
        let name = normalizedName(requestedName, module: module, date: now)
        let moduleDirectory = projectsDirectory.appendingPathComponent(module.rawValue, isDirectory: true)
        try fileManager.createDirectory(at: moduleDirectory, withIntermediateDirectories: true)

        let stamp = Self.directoryFormatter.string(from: now)
        let directory = uniqueDirectoryURL(baseName: "\(stamp)_\(safeDirectoryComponent(name))", parent: moduleDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let project = ProjectRecord(
            id: id,
            module: module,
            name: name,
            directoryURL: directory,
            createdAt: now,
            updatedAt: now,
            lastOpenedAt: now,
            isArchived: false
        )

        do {
            try writeManifest(project, summary: .empty)
            let updated = sorted(existing + [project])
            var summaries = cachedSummaries
            summaries[project.id] = .empty
            try writeIndex(updated, summaries: summaries)
            cachedProjects = updated
            cachedSummaries = summaries
            return project
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    public func setArchived(_ projectID: UUID, isArchived: Bool) throws -> ProjectRecord? {
        var projects = try load().projects
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return nil }
        let current = projects[index]
        let updated = ProjectRecord(
            id: current.id,
            module: current.module,
            name: current.name,
            directoryURL: current.directoryURL,
            createdAt: current.createdAt,
            updatedAt: dateProvider.now(),
            lastOpenedAt: current.lastOpenedAt,
            isArchived: isArchived
        )
        let summary = cachedSummaries[current.id] ?? (try? readManifest(at: current.directoryURL).summary) ?? nil
        try writeManifest(updated, summary: summary)
        projects[index] = updated
        projects = sorted(projects)
        try writeIndex(projects, summaries: cachedSummaries)
        cachedProjects = projects
        return updated
    }

    public func markOpened(_ projectID: UUID) throws -> ProjectRecord? {
        var projects = try load().projects
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return nil }
        let current = projects[index]
        let now = dateProvider.now()
        let updated = ProjectRecord(
            id: current.id,
            module: current.module,
            name: current.name,
            directoryURL: current.directoryURL,
            createdAt: current.createdAt,
            updatedAt: now,
            lastOpenedAt: now,
            isArchived: current.isArchived
        )
        let summary = cachedSummaries[current.id] ?? (try? readManifest(at: current.directoryURL).summary) ?? nil
        try writeManifest(updated, summary: summary)
        projects[index] = updated
        projects = sorted(projects)
        try writeIndex(projects, summaries: cachedSummaries)
        cachedProjects = projects
        return updated
    }

    public func updateSummary(_ summary: ProjectSummary, projectID: UUID) throws {
        let projects = try load().projects
        guard let project = projects.first(where: { $0.id == projectID }) else { return }
        try writeManifest(project, summary: summary)
        cachedSummaries[projectID] = summary
        try writeIndex(projects, summaries: cachedSummaries)
    }

    public func rebuild() throws -> ProjectCatalogSnapshot {
        let projects = try rebuildFromManifests()
        try writeIndex(projects.projects, summaries: projects.summaries)
        cachedProjects = projects.projects
        cachedSummaries = projects.summaries
        return ProjectCatalogSnapshot(projects: projects.projects, source: .rebuilt, summaries: projects.summaries)
    }

    private func rebuildFromManifests() throws -> (projects: [ProjectRecord], summaries: [UUID: ProjectSummary]) {
        guard fileManager.fileExists(atPath: projectsDirectory.path) else { return ([], [:]) }
        var projects: [ProjectRecord] = []
        var summaries: [UUID: ProjectSummary] = [:]

        for module in ProjectModule.allCases {
            let moduleDirectory = projectsDirectory.appendingPathComponent(module.rawValue, isDirectory: true)
            guard fileManager.fileExists(atPath: moduleDirectory.path) else { continue }
            let directories = try fileManager.contentsOfDirectory(
                at: moduleDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for directory in directories {
                guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                do {
                    let document = try readManifest(at: directory)
                    projects.append(document.project)
                    if let summary = document.summary {
                        summaries[document.project.id] = summary
                    }
                } catch {
                    Self.logger.error("Skipping invalid project manifest at \(directory.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        return (sorted(projects), summaries)
    }

    private func readManifest(at directory: URL) throws -> ProjectManifestDocument {
        let data = try Data(contentsOf: directory.appendingPathComponent("project.json"), options: .mappedIfSafe)
        return try codec.decode(data, directoryURL: directory)
    }

    private func writeManifest(_ project: ProjectRecord, summary: ProjectSummary?) throws {
        let data = try codec.encode(ProjectManifestDocument(project: project, summary: summary))
        try data.write(to: project.directoryURL.appendingPathComponent("project.json"), options: .atomic)
    }

    private func readIndex() throws -> (projects: [ProjectRecord], summaries: [UUID: ProjectSummary]) {
        let data = try Data(contentsOf: indexURL, options: .mappedIfSafe)
        let document = try Self.decoder().decode(CatalogDocument.self, from: data)
        guard document.schemaVersion == Self.schemaVersion else { throw CatalogError.unsupportedIndex }
        let projects = sorted(document.entries.map { entry in
            ProjectRecord(
                id: entry.id,
                module: entry.module,
                name: entry.name,
                directoryURL: projectsDirectory.appendingPathComponent(entry.relativeDirectory, isDirectory: true),
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt,
                lastOpenedAt: entry.lastOpenedAt,
                isArchived: entry.isArchived
            )
        })
        let summaries = Dictionary(uniqueKeysWithValues: document.entries.compactMap { entry in
            entry.summary.map { (entry.id, $0) }
        })
        return (projects, summaries)
    }

    private func writeIndex(_ projects: [ProjectRecord], summaries: [UUID: ProjectSummary]) throws {
        let entries = projects.map { project in
            CatalogEntry(
                id: project.id,
                module: project.module,
                name: project.name,
                relativeDirectory: relativeDirectory(for: project),
                createdAt: project.createdAt,
                updatedAt: project.updatedAt,
                lastOpenedAt: project.lastOpenedAt,
                isArchived: project.isArchived,
                summary: summaries[project.id]
            )
        }
        let data = try Self.encoder().encode(CatalogDocument(schemaVersion: Self.schemaVersion, entries: entries))
        try fileManager.createDirectory(at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: indexURL, options: .atomic)
    }

    private func relativeDirectory(for project: ProjectRecord) -> String {
        "\(project.module.rawValue)/\(project.directoryURL.lastPathComponent)"
    }

    private func normalizedName(_ requested: String, module: ProjectModule, date: Date) -> String {
        let trimmed = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else { return trimmed }
        let prefix: String
        switch module {
        case .astrophotography:
            prefix = "Astro"
        case .repeatable:
            prefix = "Repeatable"
        case .edit:
            prefix = "Edit"
        }
        return "\(prefix) \(Self.displayFormatter.string(from: date))"
    }

    private func safeDirectoryComponent(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        let parts = folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return parts.isEmpty ? "project" : parts.joined(separator: "-")
    }

    private func uniqueDirectoryURL(baseName: String, parent: URL) -> URL {
        var candidate = parent.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(baseName)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }

    private func sorted(_ projects: [ProjectRecord]) -> [ProjectRecord] {
        projects.sorted { left, right in
            let leftDate = left.lastOpenedAt ?? left.updatedAt
            let rightDate = right.lastOpenedAt ?? right.updatedAt
            return leftDate == rightDate ? left.createdAt > right.createdAt : leftDate > rightDate
        }
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static let directoryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

private struct CatalogDocument: Codable {
    let schemaVersion: Int
    let entries: [CatalogEntry]
}

private struct CatalogEntry: Codable {
    let id: UUID
    let module: ProjectModule
    let name: String
    let relativeDirectory: String
    let createdAt: Date
    let updatedAt: Date
    let lastOpenedAt: Date?
    let isArchived: Bool
    let summary: ProjectSummary?
}

private enum CatalogError: Error {
    case unsupportedIndex
}

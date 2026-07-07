import Foundation

enum CameraModule: String, CaseIterable, Identifiable, Codable, Hashable {
    case astrophotography
    case repeatable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .astrophotography:
            return "Astrophotography"
        case .repeatable:
            return "Repeatable"
        }
    }

    var subtitle: String {
        switch self {
        case .astrophotography:
            return "Stack automatico para ceu noturno"
        case .repeatable:
            return "Referencia e enquadramento repetivel"
        }
    }

    var defaultProjectPrefix: String {
        switch self {
        case .astrophotography:
            return "Astro"
        case .repeatable:
            return "Repeatable"
        }
    }

    var systemImage: String {
        switch self {
        case .astrophotography:
            return "sparkles"
        case .repeatable:
            return "rectangle.on.rectangle.angled"
        }
    }
}

struct CameraProject: Identifiable, Equatable, Hashable {
    let id: UUID
    let module: CameraModule
    let name: String
    let directoryURL: URL
    let createdAt: Date
    let updatedAt: Date
    let lastOpenedAt: Date?
    let isArchived: Bool
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [CameraProject] = []

    private let fileManager = FileManager.default
    private let projectsDirectory: URL
    private let displayDateFormatter: DateFormatter
    private let directoryDateFormatter: DateFormatter
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        projectsDirectory = documents.appendingPathComponent("Camerae Projects", isDirectory: true)

        displayDateFormatter = DateFormatter()
        displayDateFormatter.calendar = Calendar(identifier: .gregorian)
        displayDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        displayDateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        directoryDateFormatter = DateFormatter()
        directoryDateFormatter.calendar = Calendar(identifier: .gregorian)
        directoryDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        directoryDateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        reload()
    }

    func reload() {
        projects = (try? loadProjects()) ?? []
    }

    func projects(for module: CameraModule) -> [CameraProject] {
        projects
            .filter { $0.module == module }
            .sorted(by: projectSort)
    }

    func activeProjects(for module: CameraModule) -> [CameraProject] {
        projects(for: module).filter { !$0.isArchived }
    }

    func archivedProjects(for module: CameraModule) -> [CameraProject] {
        projects(for: module).filter(\.isArchived)
    }

    func defaultProjectName(for module: CameraModule, date: Date = Date()) -> String {
        "\(module.defaultProjectPrefix) \(displayDateFormatter.string(from: date))"
    }

    func createProject(module: CameraModule, name requestedName: String) throws -> CameraProject {
        try fileManager.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)

        let now = Date()
        let trimmedName = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty ? defaultProjectName(for: module, date: now) : trimmedName
        let moduleDirectory = projectsDirectory.appendingPathComponent(module.rawValue, isDirectory: true)
        try fileManager.createDirectory(at: moduleDirectory, withIntermediateDirectories: true)

        let baseDirectoryName = "\(directoryDateFormatter.string(from: now))_\(safeDirectoryComponent(from: name))"
        let directoryURL = uniqueDirectoryURL(baseName: baseDirectoryName, in: moduleDirectory)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let project = CameraProject(
            id: UUID(),
            module: module,
            name: name,
            directoryURL: directoryURL,
            createdAt: now,
            updatedAt: now,
            lastOpenedAt: now,
            isArchived: false
        )

        try writeManifest(for: project)
        projects.insert(project, at: 0)
        projects.sort { $0.createdAt > $1.createdAt }
        return project
    }

    func markOpened(_ project: CameraProject, at date: Date = Date()) {
        guard let current = projects.first(where: { $0.id == project.id }) else { return }

        let updated = CameraProject(
            id: current.id,
            module: current.module,
            name: current.name,
            directoryURL: current.directoryURL,
            createdAt: current.createdAt,
            updatedAt: date,
            lastOpenedAt: date,
            isArchived: current.isArchived
        )
        updateProject(updated)
    }

    func setArchived(_ project: CameraProject, isArchived: Bool) throws {
        guard let current = projects.first(where: { $0.id == project.id }) else { return }
        let now = Date()
        let updated = CameraProject(
            id: current.id,
            module: current.module,
            name: current.name,
            directoryURL: current.directoryURL,
            createdAt: current.createdAt,
            updatedAt: now,
            lastOpenedAt: current.lastOpenedAt,
            isArchived: isArchived
        )
        try writeManifest(for: updated)
        replaceProject(updated)
    }

    private func loadProjects() throws -> [CameraProject] {
        guard fileManager.fileExists(atPath: projectsDirectory.path) else {
            return []
        }

        var loadedProjects: [CameraProject] = []

        for module in CameraModule.allCases {
            let moduleDirectory = projectsDirectory.appendingPathComponent(module.rawValue, isDirectory: true)
            guard fileManager.fileExists(atPath: moduleDirectory.path) else {
                continue
            }

            let projectDirectories = try fileManager.contentsOfDirectory(
                at: moduleDirectory,
                includingPropertiesForKeys: [.isDirectoryKey]
            )

            for directory in projectDirectories {
                let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
                guard values.isDirectory == true else { continue }

                let manifestURL = directory.appendingPathComponent("project.json")
                guard fileManager.fileExists(atPath: manifestURL.path) else { continue }

                let data = try Data(contentsOf: manifestURL)
                let manifest = try decoder.decode(ProjectManifest.self, from: data)
                loadedProjects.append(CameraProject(
                    id: manifest.id,
                    module: manifest.module,
                    name: manifest.name,
                    directoryURL: directory,
                    createdAt: manifest.createdAt,
                    updatedAt: manifest.updatedAt,
                    lastOpenedAt: manifest.lastOpenedAt,
                    isArchived: manifest.isArchived ?? false
                ))
            }
        }

        return loadedProjects.sorted(by: projectSort)
    }

    private func writeManifest(for project: CameraProject) throws {
        let manifest = ProjectManifest(
            id: project.id,
            module: project.module,
            name: project.name,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt,
            lastOpenedAt: project.lastOpenedAt,
            isArchived: project.isArchived
        )

        let data = try encoder.encode(manifest)
        try data.write(to: project.directoryURL.appendingPathComponent("project.json"), options: [.atomic])
    }

    private func updateProject(_ project: CameraProject) {
        do {
            try writeManifest(for: project)
            replaceProject(project)
        } catch {
            reload()
        }
    }

    private func replaceProject(_ project: CameraProject) {
        projects.removeAll { $0.id == project.id }
        projects.append(project)
        projects.sort(by: projectSort)
    }

    private func projectSort(_ left: CameraProject, _ right: CameraProject) -> Bool {
        let leftDate = left.lastOpenedAt ?? left.updatedAt
        let rightDate = right.lastOpenedAt ?? right.updatedAt
        if leftDate == rightDate {
            return left.createdAt > right.createdAt
        }
        return leftDate > rightDate
    }

    private func uniqueDirectoryURL(baseName: String, in parentURL: URL) -> URL {
        var candidate = parentURL.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = parentURL.appendingPathComponent("\(baseName)-\(suffix)", isDirectory: true)
            suffix += 1
        }

        return candidate
    }

    private func safeDirectoryComponent(from name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        let parts = folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        return parts.joined(separator: "-").isEmpty ? "project" : parts.joined(separator: "-")
    }
}

private struct ProjectManifest: Codable {
    let id: UUID
    let module: CameraModule
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let lastOpenedAt: Date?
    let isArchived: Bool?
}

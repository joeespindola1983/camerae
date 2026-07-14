import CameraeCore
import Foundation

enum CameraModule: String, CaseIterable, Identifiable, Codable, Hashable {
    case astrophotography
    case repeatable
    case edit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .astrophotography: return "Astrophotography"
        case .repeatable: return "Repeatable"
        case .edit: return "Edit"
        }
    }

    var subtitle: String {
        switch self {
        case .astrophotography: return "Stack automatico para ceu noturno"
        case .repeatable: return "Referencia e enquadramento repetivel"
        case .edit: return "Monte seu portfolio em video"
        }
    }

    var defaultProjectPrefix: String {
        switch self {
        case .astrophotography: return "Astro"
        case .repeatable: return "Repeatable"
        case .edit: return "Edit"
        }
    }

    var systemImage: String {
        switch self {
        case .astrophotography: return "sparkles"
        case .repeatable: return "rectangle.on.rectangle.angled"
        case .edit: return "movieclapper"
        }
    }

    var coreValue: ProjectModule {
        ProjectModule(rawValue: rawValue)!
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
    let summary: ProjectSummary?

    var referenceFrameURL: URL? {
        guard let key = summary?.referenceThumbnailKey else { return nil }
        return directoryURL.appendingPathComponent(key)
    }

    var libraryRootURL: URL {
        directoryURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    init(record: ProjectRecord, summary: ProjectSummary?) {
        id = record.id
        module = CameraModule(rawValue: record.module.rawValue) ?? .repeatable
        name = record.name
        directoryURL = record.directoryURL
        createdAt = record.createdAt
        updatedAt = record.updatedAt
        lastOpenedAt = record.lastOpenedAt
        isArchived = record.isArchived
        self.summary = summary
    }

    var coreRecord: ProjectRecord {
        ProjectRecord(
            id: id,
            module: module.coreValue,
            name: name,
            directoryURL: directoryURL,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastOpenedAt: lastOpenedAt,
            isArchived: isArchived
        )
    }
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [CameraProject] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: Error?

    private let catalog: ProjectCatalog
    private var reloadTask: Task<Void, Never>?

    init(rootDirectory: URL? = nil) {
        let root = rootDirectory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        catalog = ProjectCatalog(rootDirectory: root)
        reload()
    }

    deinit {
        reloadTask?.cancel()
    }

    func reload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            await self?.reloadNow()
        }
    }

    func reloadNow() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let snapshot = try await catalog.load()
            guard !Task.isCancelled else { return }
            apply(snapshot)
            loadError = nil
            await enrichLegacySummaries(in: snapshot)
        } catch {
            guard !Task.isCancelled else { return }
            loadError = error
        }
    }

    func projects(for module: CameraModule) -> [CameraProject] {
        projects.filter { $0.module == module }.sorted(by: projectSort)
    }

    func activeProjects(for module: CameraModule) -> [CameraProject] {
        projects(for: module).filter { !$0.isArchived }
    }

    func archivedProjects(for module: CameraModule) -> [CameraProject] {
        projects(for: module).filter(\.isArchived)
    }

    func defaultProjectName(for module: CameraModule, date: Date = Date()) -> String {
        "\(module.defaultProjectPrefix) \(Self.displayDateFormatter.string(from: date))"
    }

    func createProject(module: CameraModule, name: String) async throws -> CameraProject {
        let record = try await catalog.createProject(module: module.coreValue, name: name)
        if module == .edit {
            _ = try await EditProjectCatalog(project: record).loadOrCreate()
        }
        let snapshot = try await catalog.load()
        apply(snapshot)
        return CameraProject(record: record, summary: snapshot.summary(for: record.id))
    }

    func markOpened(_ project: CameraProject) async {
        do {
            _ = try await catalog.markOpened(project.id)
            apply(try await catalog.load())
        } catch {
            loadError = error
        }
    }

    func setArchived(_ project: CameraProject, isArchived: Bool) async throws {
        _ = try await catalog.setArchived(project.id, isArchived: isArchived)
        apply(try await catalog.load())
    }

    private func apply(_ snapshot: ProjectCatalogSnapshot) {
        projects = snapshot.projects.map { record in
            CameraProject(record: record, summary: snapshot.summary(for: record.id))
        }
    }

    private func enrichLegacySummaries(in snapshot: ProjectCatalogSnapshot) async {
        let candidates = snapshot.projects
        guard !candidates.isEmpty else { return }

        await withTaskGroup(of: (UUID, ProjectSummary?).self) { group in
            for record in candidates {
                group.addTask {
                    do {
                        let storage = try ProjectStorageScanner().scan(
                            projectDirectory: record.directoryURL
                        )
                        if record.module == .edit {
                            let document = try await EditProjectCatalog(project: record).loadOrCreate()
                            let current = snapshot.summary(for: record.id)
                            let summary = ProjectSummary(
                                sessionCount: 0,
                                mediaCount: document.items.count,
                                referenceThumbnailKey: nil,
                                latestSessionAt: nil,
                                totalKnownBytes: storage.totalBytes,
                                inventoryState: .clean,
                                generation: current?.generation ?? 0
                            )
                            guard summary != current else { return (record.id, nil) }
                            return (
                                record.id,
                                ProjectSummary(
                                    sessionCount: 0,
                                    mediaCount: document.items.count,
                                    referenceThumbnailKey: nil,
                                    latestSessionAt: nil,
                                    totalKnownBytes: storage.totalBytes,
                                    inventoryState: .clean,
                                    generation: (current?.generation ?? 0) + 1
                                )
                            )
                        }
                        let sessions = try await SessionCatalog(project: record).loadSummaries()
                        let firstReference = sessions
                            .sorted { $0.session.createdAt < $1.session.createdAt }
                            .compactMap { summary -> String? in
                                guard let file = summary.frameSummary.firstFileName else { return nil }
                                return "Sessions/\(summary.session.name)/\(file)"
                            }
                            .first
                        let current = snapshot.summary(for: record.id)
                        let stableSummary = ProjectSummary(
                            sessionCount: sessions.count,
                            mediaCount: sessions.reduce(0) { $0 + $1.frameSummary.count },
                            referenceThumbnailKey: firstReference,
                            latestSessionAt: sessions.map(\.session.createdAt).max(),
                            totalKnownBytes: storage.totalBytes,
                            inventoryState: .clean,
                            generation: current?.generation ?? 0
                        )
                        guard stableSummary != current else { return (record.id, nil) }
                        return (
                            record.id,
                            ProjectSummary(
                                sessionCount: stableSummary.sessionCount,
                                mediaCount: stableSummary.mediaCount,
                                referenceThumbnailKey: stableSummary.referenceThumbnailKey,
                                latestSessionAt: stableSummary.latestSessionAt,
                                totalKnownBytes: stableSummary.totalKnownBytes,
                                inventoryState: .clean,
                                generation: (current?.generation ?? 0) + 1
                            )
                        )
                    } catch {
                        return (record.id, nil)
                    }
                }
            }

            for await (projectID, summary) in group {
                guard !Task.isCancelled, let summary else { continue }
                try? await catalog.updateSummary(summary, projectID: projectID)
            }
        }

        guard !Task.isCancelled, let refreshed = try? await catalog.load() else { return }
        apply(refreshed)
    }

    private func projectSort(_ left: CameraProject, _ right: CameraProject) -> Bool {
        let leftDate = left.lastOpenedAt ?? left.updatedAt
        let rightDate = right.lastOpenedAt ?? right.updatedAt
        return leftDate == rightDate ? left.createdAt > right.createdAt : leftDate > rightDate
    }

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

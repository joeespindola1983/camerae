import CameraeCore
import Foundation

enum CameraModule: String, CaseIterable, Identifiable, Codable, Hashable {
    case astrophotography
    case repeatable
    case edit

    var id: String { rawValue }

    var title: String {
        CameraeL10n.moduleTitle(self)
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
    let sequenceNumber: Int?
    let summary: ProjectSummary?

    var shotNumberLabel: String {
        sequenceNumber.map { "#\($0)" } ?? "#—"
    }

    var referenceFrameURL: URL? {
        guard let key = summary?.referenceThumbnailKey else { return nil }
        return directoryURL.appendingPathComponent(key)
    }

    var captureConfiguration: CameraeNextCaptureConfiguration? {
        captureProfile?.selectedConfiguration
    }

    var captureProfile: ProjectCaptureProfile? {
        let store = ProjectCaptureConfigurationStore(projectDirectory: directoryURL)
        let summaries = TimelapseSessionStore(project: self).sessionSummaries()
        return try? store.loadProfileOrMigrate(module: module, summaries: summaries)
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
        sequenceNumber = record.sequenceNumber
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
            isArchived: isArchived,
            sequenceNumber: sequenceNumber
        )
    }
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [CameraProject] = []
    @Published private(set) var organization: ProjectOrganizationSnapshot = .empty
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: Error?

    private let catalog: ProjectCatalog
    private let organizationCatalog: ProjectOrganizationCatalog
    private var reloadTask: Task<Void, Never>?

    init(rootDirectory: URL? = nil) {
        let root = rootDirectory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        catalog = ProjectCatalog(rootDirectory: root)
        organizationCatalog = ProjectOrganizationCatalog(rootDirectory: root)
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
            let organization = try await organizationCatalog.load(projects: snapshot.projects)
            guard !Task.isCancelled else { return }
            apply(snapshot)
            self.organization = organization
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

    func createOrganizationNode(
        module: CameraModule,
        parentID: UUID?,
        name: String
    ) async throws -> ProjectOrganizationNode {
        let node = try await organizationCatalog.createNode(
            module: module.coreValue,
            parentID: parentID,
            name: name
        )
        try await reloadOrganization()
        return node
    }

    func renameOrganizationNode(_ node: ProjectOrganizationNode, name: String) async throws {
        _ = try await organizationCatalog.renameNode(node.id, name: name)
        try await reloadOrganization()
    }

    func setOrganizationNodeArchived(
        _ node: ProjectOrganizationNode,
        isArchived: Bool
    ) async throws {
        _ = try await organizationCatalog.setArchived(node.id, isArchived: isArchived)
        try await reloadOrganization()
    }

    func moveProject(_ project: CameraProject, toOrganizationNode nodeID: UUID?) async throws {
        try await organizationCatalog.moveProject(project.coreRecord, to: nodeID)
        try await reloadOrganization()
    }

    func deleteOrganizationNode(_ node: ProjectOrganizationNode) async throws {
        try await organizationCatalog.deleteNode(node.id)
        try await reloadOrganization()
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

    func deleteProject(_ project: CameraProject) async throws {
        _ = try await catalog.deleteProject(project.id)
        let snapshot = try await catalog.load()
        apply(snapshot)
        organization = try await organizationCatalog.load(projects: snapshot.projects)
    }

    private func apply(_ snapshot: ProjectCatalogSnapshot) {
        projects = snapshot.projects.map { record in
            CameraProject(record: record, summary: snapshot.summary(for: record.id))
        }
    }

    private func reloadOrganization() async throws {
        organization = try await organizationCatalog.load(projects: projects.map(\.coreRecord))
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
                        let orderedSessions = sessions.sorted {
                            $0.session.createdAt < $1.session.createdAt
                        }
                        let referenceSession = orderedSessions.first {
                            $0.session.purpose == .projectReference &&
                            $0.frameSummary.firstFileName != nil
                        } ?? orderedSessions.first {
                            $0.frameSummary.firstFileName != nil
                        }
                        let firstReference = referenceSession.flatMap { summary -> String? in
                            guard let file = summary.frameSummary.firstFileName else { return nil }
                            return "Sessions/\(summary.session.name)/\(file)"
                        }
                        let current = snapshot.summary(for: record.id)
                        let stableSummary = ProjectSummary(
                            sessionCount: sessions.count,
                            mediaCount: sessions.reduce(0) { result, session in
                                let hasFinalArtifact =
                                    session.videoSummary?.videoFileName != nil ||
                                    session.videoSummary?.clipFileName != nil ||
                                    session.astroSummary?.hasRenderedClip == true
                                return result + max(session.frameSummary.count, hasFinalArtifact ? 1 : 0)
                            },
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
        if let leftNumber = left.sequenceNumber,
           let rightNumber = right.sequenceNumber,
           leftNumber != rightNumber {
            return leftNumber > rightNumber
        }
        return left.createdAt == right.createdAt
            ? left.id.uuidString < right.id.uuidString
            : left.createdAt > right.createdAt
    }

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

import CameraeCore
import CameraeMedia
import Foundation

@MainActor
final class EditProjectViewModel: ObservableObject {
    @Published private(set) var document: EditProjectDocument?
    @Published private(set) var snapshot = MediaLibrarySnapshot(assets: [])
    @Published private(set) var resolvedItems: [UUID: ResolvedMediaAsset] = [:]
    @Published private(set) var resolvedLibraryAssets: [MediaAssetID: ResolvedMediaAsset] = [:]
    @Published var filter = MediaLibraryFilter()
    @Published var selectedAssetIDs: Set<MediaAssetID> = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    let project: CameraProject
    private let catalog: EditProjectCatalog
    private let mediaLibrary: any MediaLibraryProviding

    var filteredAssets: [MediaAssetDescriptor] {
        snapshot.filtered(by: filter)
    }

    var resolvedAssetsForExport: [MediaAssetID: ResolvedMediaAsset] {
        var assets: [MediaAssetID: ResolvedMediaAsset] = [:]
        for item in document?.items ?? [] {
            if let resolved = resolvedItems[item.id] {
                assets[item.asset.id] = resolved
            }
        }
        return assets
    }

    var canExport: Bool {
        guard let items = document?.items, !items.isEmpty else { return false }
        return items.allSatisfy { resolvedItems[$0.id] != nil }
    }

    var sourceProjects: [(id: UUID, name: String)] {
        var names: [UUID: String] = [:]
        for asset in snapshot.assets {
            names[asset.reference.projectID] = asset.projectName
        }
        return names.map { (id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    convenience init(project: CameraProject) {
        self.init(
            project: project,
            mediaLibrary: MediaLibraryCatalog(rootDirectory: project.libraryRootURL)
        )
    }

    init(project: CameraProject, mediaLibrary: any MediaLibraryProviding) {
        self.project = project
        catalog = EditProjectCatalog(project: project.coreRecord)
        self.mediaLibrary = mediaLibrary
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let document = catalog.loadOrCreate()
            async let snapshot = mediaLibrary.load()
            self.document = try await document
            self.snapshot = try await snapshot
            try await resolveLibrary()
            try await resolveTimeline()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshMedia() async {
        await mediaLibrary.invalidate()
        do {
            snapshot = try await mediaLibrary.load()
            try await resolveLibrary()
            try await resolveTimeline()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleSelection(_ id: MediaAssetID) {
        if selectedAssetIDs.contains(id) {
            selectedAssetIDs.remove(id)
        } else {
            selectedAssetIDs.insert(id)
        }
    }

    func addSelection() async {
        let references = snapshot.assets
            .filter { selectedAssetIDs.contains($0.reference.id) }
            .map(\.reference)
        guard !references.isEmpty else { return }
        await save {
            try await catalog.append(references)
        }
        selectedAssetIDs.removeAll()
    }

    func moveItem(from source: Int, to destination: Int) async {
        guard let items = document?.items,
              items.indices.contains(source) else { return }
        let target = min(max(destination, 0), max(items.count - 1, 0))
        await save {
            try await catalog.moveItem(id: items[source].id, to: target)
        }
    }

    func moveItems(from offsets: IndexSet, to destination: Int) async {
        guard offsets.count == 1, let source = offsets.first else { return }
        let adjusted = destination > source ? destination - 1 : destination
        await moveItem(from: source, to: adjusted)
    }

    func removeItem(at index: Int) async {
        guard let items = document?.items, items.indices.contains(index) else { return }
        await save {
            try await catalog.removeItem(id: items[index].id)
        }
    }

    func removeItems(at offsets: IndexSet) async {
        for index in offsets.sorted(by: >) {
            await removeItem(at: index)
        }
    }

    func setCanvas(_ canvas: EditCanvas) async {
        await save {
            try await catalog.setCanvas(canvas)
        }
    }

    func resolvedAsset(for item: EditTimelineItem) -> ResolvedMediaAsset? {
        resolvedItems[item.id]
    }

    func resolvedLibraryAsset(id: MediaAssetID) -> ResolvedMediaAsset? {
        resolvedLibraryAssets[id]
    }

    private func save(
        operation: () async throws -> EditProjectDocument
    ) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            document = try await operation()
            try await resolveTimeline()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolveTimeline() async throws {
        guard let document else {
            resolvedItems = [:]
            return
        }
        var next: [UUID: ResolvedMediaAsset] = [:]
        for item in document.items {
            try Task.checkCancellation()
            if let asset = try await mediaLibrary.resolve(item.asset) {
                next[item.id] = asset
            }
        }
        resolvedItems = next
    }

    private func resolveLibrary() async throws {
        var next: [MediaAssetID: ResolvedMediaAsset] = [:]
        for asset in snapshot.assets {
            try Task.checkCancellation()
            if let resolved = try await mediaLibrary.resolve(asset.reference) {
                next[asset.reference.id] = resolved
            }
        }
        resolvedLibraryAssets = next
    }
}

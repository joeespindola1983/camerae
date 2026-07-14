import Foundation

public actor EditProjectCatalog {
    private let project: ProjectRecord
    private let fileManager: FileManager
    private let dateProvider: any DateProviding
    private let idProvider: any IDProviding
    private let codec = EditProjectCodec()
    private let manifestURL: URL

    public init(
        project: ProjectRecord,
        fileManager: FileManager = .default,
        dateProvider: any DateProviding = SystemDateProvider(),
        idProvider: any IDProviding = SystemIDProvider()
    ) {
        self.project = project
        self.fileManager = fileManager
        self.dateProvider = dateProvider
        self.idProvider = idProvider
        manifestURL = project.directoryURL.appendingPathComponent("edit.json")
    }

    public func loadOrCreate() throws -> EditProjectDocument {
        try validateProject()
        if fileManager.fileExists(atPath: manifestURL.path) {
            return try read()
        }
        let document = EditProjectDocument(
            projectID: project.id,
            canvas: .landscape16x9,
            items: [],
            updatedAt: dateProvider.now()
        )
        try write(document)
        return document
    }

    public func setCanvas(_ canvas: EditCanvas) throws -> EditProjectDocument {
        var document = try loadOrCreate()
        document.canvas = canvas
        document.updatedAt = dateProvider.now()
        try write(document)
        return document
    }

    public func append(_ assets: [MediaAssetReference]) async throws -> EditProjectDocument {
        var document = try loadOrCreate()
        for asset in assets {
            document.items.append(EditTimelineItem(
                id: await idProvider.next(),
                asset: asset,
                addedAt: dateProvider.now()
            ))
        }
        document.updatedAt = dateProvider.now()
        try write(document)
        return document
    }

    public func moveItem(id: UUID, to destination: Int) throws -> EditProjectDocument {
        var document = try loadOrCreate()
        guard let source = document.items.firstIndex(where: { $0.id == id }) else {
            throw EditProjectCatalogError.itemNotFound
        }
        let item = document.items.remove(at: source)
        let safeDestination = min(max(destination, 0), document.items.count)
        document.items.insert(item, at: safeDestination)
        document.updatedAt = dateProvider.now()
        try write(document)
        return document
    }

    public func removeItem(id: UUID) throws -> EditProjectDocument {
        var document = try loadOrCreate()
        guard let index = document.items.firstIndex(where: { $0.id == id }) else {
            throw EditProjectCatalogError.itemNotFound
        }
        document.items.remove(at: index)
        document.updatedAt = dateProvider.now()
        try write(document)
        return document
    }

    public func setLastExport(relativePath: String?) throws -> EditProjectDocument {
        var document = try loadOrCreate()
        document.lastExportRelativePath = relativePath
        document.updatedAt = dateProvider.now()
        try write(document)
        return document
    }

    private func validateProject() throws {
        guard project.module == .edit else {
            throw EditProjectCatalogError.wrongProjectModule
        }
    }

    private func read() throws -> EditProjectDocument {
        let data = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
        let document = try codec.decode(data)
        guard document.projectID == project.id else {
            throw EditProjectCatalogError.projectMismatch
        }
        return document
    }

    private func write(_ document: EditProjectDocument) throws {
        try fileManager.createDirectory(at: project.directoryURL, withIntermediateDirectories: true)
        try codec.encode(document).write(to: manifestURL, options: .atomic)
    }
}

public enum EditProjectCatalogError: Error, Equatable {
    case wrongProjectModule
    case projectMismatch
    case itemNotFound
}

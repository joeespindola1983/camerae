import Foundation

public enum TripodLocationError: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
    case locationNotFound
    case invalidWeekOffset
}

public struct TripodCoordinate: Codable, Equatable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double?
    public let horizontalAccuracy: Double?

    public init(latitude: Double, longitude: Double, altitude: Double? = nil, horizontalAccuracy: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
    }
}

public struct TripodReferencePhoto: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let relativePath: String
    public let caption: String?

    public init(id: UUID, relativePath: String, caption: String? = nil) {
        self.id = id
        self.relativePath = relativePath
        self.caption = caption
    }
}

public struct TripodSpatialRevision: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let relativePackagePath: String
    public let createdAt: Date
    public let sourceProjectID: UUID?

    public init(id: UUID, relativePackagePath: String, createdAt: Date, sourceProjectID: UUID? = nil) {
        self.id = id
        self.relativePackagePath = relativePackagePath
        self.createdAt = createdAt
        self.sourceProjectID = sourceProjectID
    }
}

public struct TripodLocation: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var note: String?
    public var coordinate: TripodCoordinate?
    public var referencePhotos: [TripodReferencePhoto]
    public var spatialRevisions: [TripodSpatialRevision]
    public var projectIDs: [UUID]
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, name: String, note: String? = nil, coordinate: TripodCoordinate? = nil, referencePhotos: [TripodReferencePhoto] = [], spatialRevisions: [TripodSpatialRevision] = [], projectIDs: [UUID] = [], createdAt: Date, updatedAt: Date) {
        self.id = id; self.name = name; self.note = note; self.coordinate = coordinate
        self.referencePhotos = referencePhotos; self.spatialRevisions = spatialRevisions
        self.projectIDs = projectIDs; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct RecapturePlan: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let locationID: UUID
    public let projectID: UUID?
    public let scheduledAt: Date
    public let note: String?
    public let reminderEnabled: Bool
    public let createdAt: Date

    public init(id: UUID, locationID: UUID, projectID: UUID? = nil, scheduledAt: Date, note: String? = nil, reminderEnabled: Bool = true, createdAt: Date) {
        self.id = id; self.locationID = locationID; self.projectID = projectID
        self.scheduledAt = scheduledAt; self.note = note; self.reminderEnabled = reminderEnabled; self.createdAt = createdAt
    }
}

public enum CaptureCalendarEntryKind: String, Codable, Equatable, Hashable, Sendable { case captured, planned }

public struct CaptureCalendarEntry: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let kind: CaptureCalendarEntryKind
    public let date: Date
    public let locationID: UUID
    public let projectID: UUID?
    public let recapturePlanID: UUID?

    public init(id: UUID, kind: CaptureCalendarEntryKind, date: Date, locationID: UUID, projectID: UUID? = nil, recapturePlanID: UUID? = nil) {
        self.id = id; self.kind = kind; self.date = date; self.locationID = locationID
        self.projectID = projectID; self.recapturePlanID = recapturePlanID
    }
}

public struct TripodLocationDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public var locations: [TripodLocation]
    public var recapturePlans: [RecapturePlan]
    public var calendarEntries: [CaptureCalendarEntry]

    public init(schemaVersion: Int = Self.currentSchemaVersion, locations: [TripodLocation], recapturePlans: [RecapturePlan] = [], calendarEntries: [CaptureCalendarEntry]) {
        self.schemaVersion = schemaVersion; self.locations = locations
        self.recapturePlans = recapturePlans; self.calendarEntries = calendarEntries
    }

    public static let empty = TripodLocationDocument(locations: [], calendarEntries: [])
}

public struct TripodLocationCodec: Sendable {
    public init() {}

    public func decode(_ data: Data) throws -> TripodLocationDocument {
        let probe = try JSONDecoder().decode(SchemaProbe.self, from: data)
        let version = probe.schemaVersion ?? 0
        guard version <= TripodLocationDocument.currentSchemaVersion else { throw TripodLocationError.unsupportedSchema(version) }
        let decoded = try Self.decoder.decode(LegacyCompatibleDocument.self, from: data)
        return TripodLocationDocument(locations: decoded.locations, recapturePlans: decoded.recapturePlans ?? [], calendarEntries: decoded.calendarEntries)
    }

    public func encode(_ document: TripodLocationDocument) throws -> Data {
        guard document.schemaVersion == TripodLocationDocument.currentSchemaVersion else { throw TripodLocationError.unsupportedSchema(document.schemaVersion) }
        return try Self.encoder.encode(document)
    }

    private struct SchemaProbe: Decodable { let schemaVersion: Int? }
    private struct LegacyCompatibleDocument: Decodable {
        let locations: [TripodLocation]
        let recapturePlans: [RecapturePlan]?
        let calendarEntries: [CaptureCalendarEntry]
    }
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }()
}

public struct TripodLocationSnapshot: Equatable, Sendable {
    public let locations: [TripodLocation]
    public let recapturePlans: [RecapturePlan]
    public let calendarEntries: [CaptureCalendarEntry]

    public func location(forProjectID projectID: UUID) -> TripodLocation? { locations.first { $0.projectIDs.contains(projectID) } }
    public func location(id: UUID) -> TripodLocation? { locations.first { $0.id == id } }
    public static let empty = TripodLocationSnapshot(locations: [], recapturePlans: [], calendarEntries: [])
}

public actor TripodLocationCatalog {
    private let fileManager: FileManager
    private let dateProvider: any DateProviding
    private let idProvider: any IDProviding
    private let codec = TripodLocationCodec()
    private var cached: TripodLocationDocument?
    public nonisolated let documentURL: URL

    public init(rootDirectory: URL, fileManager: FileManager = .default, dateProvider: any DateProviding = SystemDateProvider(), idProvider: any IDProviding = SystemIDProvider()) {
        self.fileManager = fileManager; self.dateProvider = dateProvider; self.idProvider = idProvider
        documentURL = rootDirectory.appendingPathComponent("Application Support/Camerae/tripod-locations-v1.json")
    }

    public func load() throws -> TripodLocationSnapshot { snapshot(try read()) }

    public func create(name: String, note: String? = nil, coordinate: TripodCoordinate? = nil) async throws -> TripodLocation {
        var document = try read(); let now = dateProvider.now()
        let location = TripodLocation(id: await idProvider.next(), name: normalizedName(name), note: note, coordinate: coordinate, createdAt: now, updatedAt: now)
        document.locations.append(location); try persist(document); return location
    }

    public func update(_ location: TripodLocation) throws {
        var document = try read(); guard let index = document.locations.firstIndex(where: { $0.id == location.id }) else { throw TripodLocationError.locationNotFound }
        var updated = location; updated.updatedAt = dateProvider.now(); document.locations[index] = updated; try persist(document)
    }

    public func link(projectID: UUID, to locationID: UUID) throws {
        var document = try read(); guard document.locations.contains(where: { $0.id == locationID }) else { throw TripodLocationError.locationNotFound }
        for index in document.locations.indices { document.locations[index].projectIDs.removeAll { $0 == projectID } }
        guard let target = document.locations.firstIndex(where: { $0.id == locationID }) else { throw TripodLocationError.locationNotFound }
        document.locations[target].projectIDs.append(projectID); document.locations[target].updatedAt = dateProvider.now(); try persist(document)
    }

    public func addReferencePhoto(_ photo: TripodReferencePhoto, to locationID: UUID) throws {
        var document = try read(); guard let index = document.locations.firstIndex(where: { $0.id == locationID }) else { throw TripodLocationError.locationNotFound }
        document.locations[index].referencePhotos.append(photo); document.locations[index].updatedAt = dateProvider.now(); try persist(document)
    }

    public func addSpatialRevision(_ revision: TripodSpatialRevision, to locationID: UUID) throws {
        var document = try read(); guard let index = document.locations.firstIndex(where: { $0.id == locationID }) else { throw TripodLocationError.locationNotFound }
        guard !document.locations[index].spatialRevisions.contains(where: { $0.relativePackagePath == revision.relativePackagePath }) else { return }
        document.locations[index].spatialRevisions.append(revision); document.locations[index].updatedAt = dateProvider.now(); try persist(document)
    }

    public func scheduleRecapture(locationID: UUID, projectID: UUID? = nil, afterWeeks: Int, note: String? = nil) async throws -> RecapturePlan {
        guard afterWeeks > 0, let date = Calendar(identifier: .gregorian).date(byAdding: .weekOfYear, value: afterWeeks, to: dateProvider.now()) else { throw TripodLocationError.invalidWeekOffset }
        var document = try read(); guard document.locations.contains(where: { $0.id == locationID }) else { throw TripodLocationError.locationNotFound }
        let plan = RecapturePlan(id: await idProvider.next(), locationID: locationID, projectID: projectID, scheduledAt: date, note: note, createdAt: dateProvider.now())
        document.recapturePlans.append(plan)
        document.calendarEntries.append(CaptureCalendarEntry(id: await idProvider.next(), kind: .planned, date: date, locationID: locationID, projectID: projectID, recapturePlanID: plan.id))
        try persist(document); return plan
    }

    private func read() throws -> TripodLocationDocument {
        if let cached { return cached }
        guard fileManager.fileExists(atPath: documentURL.path) else { cached = .empty; return .empty }
        let value = try codec.decode(Data(contentsOf: documentURL)); cached = value; return value
    }
    private func persist(_ document: TripodLocationDocument) throws {
        try fileManager.createDirectory(at: documentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try codec.encode(document).write(to: documentURL, options: .atomic); cached = document
    }
    private func snapshot(_ d: TripodLocationDocument) -> TripodLocationSnapshot { .init(locations: d.locations.sorted { $0.updatedAt > $1.updatedAt }, recapturePlans: d.recapturePlans, calendarEntries: d.calendarEntries.sorted { $0.date < $1.date }) }
    private func normalizedName(_ name: String) -> String { let v = name.trimmingCharacters(in: .whitespacesAndNewlines); return v.isEmpty ? "Nova posição" : v }
}

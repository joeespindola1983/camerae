import Foundation
import Testing
@testable import CameraeCore

@Suite("Tripod location document compatibility")
struct TripodLocationDocumentTests {
    @Test("current document round trips")
    func currentRoundTrip() throws {
        let location = TripodLocation.fixture
        let document = TripodLocationDocument(locations: [location], calendarEntries: [])
        let codec = TripodLocationCodec()

        #expect(try codec.decode(codec.encode(document)) == document)
    }

    @Test("an empty legacy document migrates to v1")
    func emptyLegacyDocument() throws {
        let decoded = try TripodLocationCodec().decode(Data(#"{"locations":[],"calendarEntries":[]}"#.utf8))

        #expect(decoded.schemaVersion == TripodLocationDocument.currentSchemaVersion)
        #expect(decoded.locations.isEmpty)
        #expect(decoded.calendarEntries.isEmpty)
    }

    @Test("future documents are rejected")
    func rejectsFutureDocument() {
        #expect(throws: TripodLocationError.unsupportedSchema(99)) {
            try TripodLocationCodec().decode(Data(#"{"schemaVersion":99,"locations":[],"calendarEntries":[]}"#.utf8))
        }
    }
}

@Suite("Tripod location catalog")
struct TripodLocationCatalogTests {
    @Test("create, link and reload keeps one location as project owner")
    func createLinkReload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let ids = FixedIDProvider([
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        ])
        let catalog = TripodLocationCatalog(rootDirectory: root, idProvider: ids)
        let projectID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        let created = try await catalog.create(name: "Ipê da praça", coordinate: .init(latitude: -23.55, longitude: -46.63))
        try await catalog.link(projectID: projectID, to: created.id)
        let snapshot = try await TripodLocationCatalog(rootDirectory: root).load()

        #expect(snapshot.location(forProjectID: projectID)?.id == created.id)
        #expect(snapshot.locations.first?.coordinate?.latitude == -23.55)
    }

    @Test("linking a project again moves it instead of duplicating membership")
    func projectHasSingleOwner() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = TripodLocationCatalog(rootDirectory: root)
        let first = try await catalog.create(name: "Primeira")
        let second = try await catalog.create(name: "Segunda")
        let projectID = UUID()

        try await catalog.link(projectID: projectID, to: first.id)
        try await catalog.link(projectID: projectID, to: second.id)
        let snapshot = try await catalog.load()

        #expect(snapshot.location(forProjectID: projectID)?.id == second.id)
        #expect(snapshot.locations.flatMap(\.projectIDs).count == 1)
    }

    @Test("four-week recapture is visible in calendar history")
    func recapturePlan() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let catalog = TripodLocationCatalog(rootDirectory: root, dateProvider: FixedDateProvider(now))
        let location = try await catalog.create(name: "Ipê")

        let plan = try await catalog.scheduleRecapture(locationID: location.id, afterWeeks: 4, note: "Repetir sem flores")
        let snapshot = try await catalog.load()

        #expect(plan.scheduledAt == Calendar(identifier: .gregorian).date(byAdding: .weekOfYear, value: 4, to: now))
        #expect(snapshot.calendarEntries.map(\.recapturePlanID).contains(plan.id))
    }
}

private extension TripodLocation {
    static let fixture = TripodLocation(
        id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        name: "Ipê",
        note: "Lado sul",
        coordinate: .init(latitude: -23.55, longitude: -46.63, horizontalAccuracy: 4),
        referencePhotos: [.init(id: UUID(), relativePath: "References/plaza.jpg", caption: "Visão geral")],
        spatialRevisions: [],
        projectIDs: [UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!],
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

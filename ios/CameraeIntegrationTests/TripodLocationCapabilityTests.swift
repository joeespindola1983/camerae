import CameraeCore
import Testing
@testable import Camerae

@Suite("Tripod positions capability contracts")
struct TripodLocationCapabilityTests {
    @Test("catalog actions stay reachable independently of layout")
    func catalogCapabilities() {
        #expect(TripodPositionsCapabilityPolicy.catalog == [
            .create, .switchMapList, .selectMapLocation, .showSavedSummary,
            .openLocation, .returnHome
        ])
    }

    @Test("position detail matches the approved read-only project flow")
    func detailCapabilities() {
        #expect(TripodPositionsCapabilityPolicy.detail == [.addReference, .openProject, .openMap, .scheduleRecapture, .showMetrics])
    }

    @Test("map and list are typed presentation modes")
    func catalogModes() {
        #expect(TripodPositionsViewMode.allCases == [.map, .list])
        #expect(TripodPositionsViewMode.map.title == "Mapa")
        #expect(TripodPositionsViewMode.list.title == "Lista")
        #expect(TripodPositionsCatalogPresentation.savedPositionsDestination == .list)
    }

    @Test("map camera fits every GPS position and ignores positions without GPS")
    func mapCameraFit() throws {
        let locations = [
            TripodLocation.fixture(id: UUID(), latitude: -23.551, longitude: -46.634),
            TripodLocation.fixture(id: UUID(), latitude: -23.548, longitude: -46.628),
            TripodLocation.fixture(id: UUID())
        ]

        let region = try #require(TripodMapCameraFit.region(for: locations))

        #expect(region.minimumLatitude <= -23.551)
        #expect(region.maximumLatitude >= -23.548)
        #expect(region.minimumLongitude <= -46.634)
        #expect(region.maximumLongitude >= -46.628)
    }

    @Test("a single GPS position receives a useful minimum camera span")
    func singleMapPosition() throws {
        let region = try #require(TripodMapCameraFit.region(for: [
            TripodLocation.fixture(id: UUID(), latitude: -23.551, longitude: -46.634)
        ]))

        #expect(region.centerLatitude == -23.551)
        #expect(region.centerLongitude == -46.634)
        #expect(region.latitudeDelta >= TripodMapCameraFit.minimumSpan)
        #expect(region.longitudeDelta >= TripodMapCameraFit.minimumSpan)
        #expect(TripodMapCameraFit.region(for: [.fixture(id: UUID())]) == nil)
    }

    @Test("legacy positions recover GPS from the newest captured session")
    func legacyCoordinateBackfill() throws {
        let older = TripodCoordinateEvidence(
            capturedAt: Date(timeIntervalSince1970: 100),
            latitude: -23.55,
            longitude: -46.63,
            horizontalAccuracy: 12
        )
        let newer = TripodCoordinateEvidence(
            capturedAt: Date(timeIntervalSince1970: 200),
            latitude: -23.548,
            longitude: -46.628,
            horizontalAccuracy: 4
        )

        let coordinate = try #require(TripodCoordinateBackfill.resolve([older, newer]))

        #expect(coordinate.latitude == newer.latitude)
        #expect(coordinate.longitude == newer.longitude)
        #expect(coordinate.horizontalAccuracy == newer.horizontalAccuracy)
        #expect(TripodCoordinateBackfill.resolve([]) == nil)
    }

    @Test("position metrics expose persisted facts without inventing GPS accuracy")
    func positionMetrics() {
        let location = TripodLocation(
            id: UUID(),
            name: "Mirante",
            coordinate: .init(latitude: -23.55052, longitude: -46.633308, horizontalAccuracy: 4.4),
            referencePhotos: [
                .init(id: UUID(), relativePath: "reference-1.jpg"),
                .init(id: UUID(), relativePath: "reference-2.jpg")
            ],
            projectIDs: [UUID()],
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
        let metrics = TripodPositionMetrics(location: location)

        #expect(metrics.gpsAccuracy == "± 4 m")
        #expect(metrics.projectCount == "01")
        #expect(metrics.referenceCount == "02")
        #expect(metrics.coordinateText == "-23.55052, -46.63331")
    }

    @Test("calendar keeps history and planning reachable")
    func calendarCapabilities() {
        #expect(CaptureCalendarCapabilityPolicy.root == [.returnHome, .browseMonth, .openDay, .filterProjects, .showProjectMarkers, .openProjectSummary])
        #expect(CaptureCalendarCapabilityPolicy.summary == [.openProject, .scheduleRecapture])
    }

    @Test("calendar project filters never invent or edit agenda items")
    func calendarProjectFilters() {
        let captured = CalendarProjectAgendaItem.fixture(kind: .captured)
        let planned = CalendarProjectAgendaItem.fixture(kind: .planned)
        let created = CalendarProjectAgendaItem.fixture(kind: .created)

        #expect(CalendarProjectFilter.all.apply(to: [captured, planned, created]) == [captured, planned, created])
        #expect(CalendarProjectFilter.captures.apply(to: [captured, planned, created]) == [captured])
        #expect(CalendarProjectFilter.returns.apply(to: [captured, planned, created]) == [planned])
    }
}

private extension TripodLocation {
    static func fixture(id: UUID, latitude: Double? = nil, longitude: Double? = nil) -> Self {
        let coordinate = latitude.flatMap { latitude in
            longitude.map { longitude in
                TripodCoordinate(latitude: latitude, longitude: longitude)
            }
        }
        return .init(
            id: id,
            name: "Posição",
            coordinate: coordinate,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
    }
}

private extension CalendarProjectAgendaItem {
    static func fixture(kind: CalendarProjectAgendaKind) -> Self {
        .init(
            id: UUID(),
            kind: kind,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            projectID: UUID(),
            locationID: UUID(),
            locationTitle: "Posição",
            title: kind == .captured ? "Capturado" : "Planejado",
            detail: "Detalhe",
            session: nil
        )
    }
}

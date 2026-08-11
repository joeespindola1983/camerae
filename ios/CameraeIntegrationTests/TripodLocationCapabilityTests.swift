import CameraeCore
import Testing
@testable import Camerae

@Suite("Tripod positions capability contracts")
struct TripodLocationCapabilityTests {
    @Test("catalog actions stay reachable independently of layout")
    func catalogCapabilities() {
        #expect(TripodPositionsCapabilityPolicy.catalog == [
            .create, .switchMapList, .selectMapLocation, .showLinkedProjects,
            .filterProjects, .openProjectSummary, .filterVisibleLocations,
            .showSelectionState, .openCluster, .expandOverlappingCluster, .returnHome
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

    @Test("map opens without a selected tripod and a second tap deselects")
    func tripodSelectionToggle() {
        let first = UUID()
        let second = UUID()

        #expect(TripodLocationSelection.initial == nil)
        #expect(TripodLocationSelection.toggle(current: nil, tapped: first) == first)
        #expect(TripodLocationSelection.toggle(current: first, tapped: first) == nil)
        #expect(TripodLocationSelection.toggle(current: first, tapped: second) == second)
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

    @Test("tripod list follows the visible map region")
    func visibleMapLocations() {
        let visible = TripodLocation.fixture(id: UUID(), latitude: -23.550, longitude: -46.630)
        let outside = TripodLocation.fixture(id: UUID(), latitude: -23.600, longitude: -46.700)
        let withoutGPS = TripodLocation.fixture(id: UUID())
        let region = TripodMapCameraRegion(
            centerLatitude: -23.550,
            centerLongitude: -46.630,
            latitudeDelta: 0.02,
            longitudeDelta: 0.02
        )

        #expect(TripodMapViewport.locations(in: region, from: [visible, outside, withoutGPS]) == [visible])
    }

    @Test("visible map region supports the antimeridian")
    func visibleMapLocationsAcrossAntimeridian() {
        let east = TripodLocation.fixture(id: UUID(), latitude: 0, longitude: 179.5)
        let west = TripodLocation.fixture(id: UUID(), latitude: 0, longitude: -179.5)
        let outside = TripodLocation.fixture(id: UUID(), latitude: 0, longitude: -170)
        let region = TripodMapCameraRegion(
            centerLatitude: 0,
            centerLongitude: 180,
            latitudeDelta: 10,
            longitudeDelta: 4
        )

        #expect(TripodMapViewport.locations(in: region, from: [east, west, outside]) == [east, west])
    }

    @Test("nearby tripods cluster at a wide zoom and separate after zooming in")
    func tripodMapClustering() {
        let first = TripodLocation.fixture(id: UUID(), latitude: -23.5500, longitude: -46.6300)
        let second = TripodLocation.fixture(id: UUID(), latitude: -23.5502, longitude: -46.6302)
        let far = TripodLocation.fixture(id: UUID(), latitude: -23.5700, longitude: -46.6500)
        let wide = TripodMapCameraRegion(
            centerLatitude: -23.56,
            centerLongitude: -46.64,
            latitudeDelta: 0.04,
            longitudeDelta: 0.04
        )

        let wideClusters = TripodMapClustering.clusters(
            locations: [first, second, far],
            region: wide,
            viewport: .init(width: 353, height: 270)
        )
        let nearbyCluster = wideClusters.first { $0.locations.contains(first) }

        #expect(nearbyCluster?.count == 2)
        #expect(wideClusters.count == 2)

        let zoomed = TripodMapClusterZoom.region(for: [first, second])
        let zoomedClusters = zoomed.map {
            TripodMapClustering.clusters(
                locations: [first, second],
                region: $0,
                viewport: .init(width: 353, height: 270)
            )
        }
        #expect(zoomedClusters?.count == 2)
    }

    @Test("opening a cluster clears selection and fits every member")
    func clusterInteraction() throws {
        let first = TripodLocation.fixture(id: UUID(), latitude: -23.5500, longitude: -46.6300)
        let second = TripodLocation.fixture(id: UUID(), latitude: -23.5502, longitude: -46.6302)
        let region = try #require(TripodMapClusterZoom.region(for: [first, second]))

        #expect(TripodLocationSelection.afterOpeningCluster == nil)
        #expect(region.minimumLatitude <= -23.5502)
        #expect(region.maximumLatitude >= -23.5500)
        #expect(region.minimumLongitude <= -46.6302)
        #expect(region.maximumLongitude >= -46.6300)
    }

    @Test("overlapping tripods become smaller individually tappable markers")
    func overlappingClusterExpansion() {
        let firstID = UUID()
        let secondID = UUID()
        let locations = [
            TripodLocation.fixture(id: firstID, latitude: -23.5500, longitude: -46.6300),
            TripodLocation.fixture(id: secondID, latitude: -23.5500, longitude: -46.6300)
        ]
        let offsets = TripodClusterExpansion.offsets(count: locations.count)

        #expect(TripodClusterExpansion.markerDiameter < 44)
        #expect(offsets.count == 2)
        #expect(Set(offsets).count == 2)
        #expect(TripodClusterExpansion.members(afterOpening: locations) == [firstID, secondID])
    }

    @Test("large overlapping groups use additional radial rings")
    func largeClusterExpansion() {
        let offsets = TripodClusterExpansion.offsets(count: 12)

        #expect(offsets.count == 12)
        #expect(Set(offsets).count == 12)
        #expect((offsets.map(\.radius).max() ?? 0) > (offsets.map(\.radius).min() ?? 0))
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

    @Test("calendar and tripod positions share the project-list use case")
    func sharedProjectContextCapabilities() {
        #expect(ProjectContextCapabilityPolicy.list == [.filterProjects, .openProjectSummary])
        #expect(ProjectContextCapabilityPolicy.summary == [.openProject, .scheduleRecapture])
    }

    @Test("a tripod position shows one latest entry for each linked project")
    func projectsAtTripodPosition() throws {
        let locationID = UUID()
        let firstProjectID = UUID()
        let secondProjectID = UUID()
        let oldCapture = CalendarProjectAgendaItem.fixture(
            kind: .captured, projectID: firstProjectID, locationID: locationID, date: Date(timeIntervalSince1970: 100)
        )
        let latestReturn = CalendarProjectAgendaItem.fixture(
            kind: .planned, projectID: firstProjectID, locationID: locationID, date: Date(timeIntervalSince1970: 300)
        )
        let secondProject = CalendarProjectAgendaItem.fixture(
            kind: .created, projectID: secondProjectID, locationID: locationID, date: Date(timeIntervalSince1970: 200)
        )
        let anotherLocation = CalendarProjectAgendaItem.fixture(
            kind: .captured, projectID: UUID(), locationID: UUID(), date: Date(timeIntervalSince1970: 400)
        )

        let result = ProjectContextCatalog.projects(
            at: locationID,
            from: [oldCapture, latestReturn, secondProject, anotherLocation]
        )

        #expect(result.count == 2)
        #expect(result.first(where: { $0.projectID == firstProjectID }) == latestReturn)
        #expect(result.first(where: { $0.projectID == secondProjectID }) == secondProject)
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
    static func fixture(
        kind: CalendarProjectAgendaKind,
        projectID: UUID = UUID(),
        locationID: UUID = UUID(),
        date: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Self {
        .init(
            id: UUID(),
            kind: kind,
            date: date,
            projectID: projectID,
            locationID: locationID,
            locationTitle: "Posição",
            title: kind == .captured ? "Capturado" : "Planejado",
            detail: "Detalhe",
            session: nil
        )
    }
}

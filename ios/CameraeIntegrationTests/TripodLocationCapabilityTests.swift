import CameraeCore
import Testing
@testable import Camerae

@Suite("Tripod positions capability contracts")
struct TripodLocationCapabilityTests {
    @Test("catalog actions stay reachable independently of layout")
    func catalogCapabilities() {
        #expect(TripodPositionsCapabilityPolicy.catalog == [.create, .switchMapList, .selectMapLocation, .showSavedSummary, .openLocation])
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
        #expect(CaptureCalendarCapabilityPolicy.root == [.browseMonth, .openDay, .filterProjects, .showProjectMarkers, .openProjectSummary])
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

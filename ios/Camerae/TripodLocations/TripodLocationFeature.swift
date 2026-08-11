import CameraeCore
import Foundation
import MapKit
import PhotosUI
import SwiftUI
import UIKit
import UserNotifications

enum CameraeHomeDestination: Hashable { case calendar, positions }

enum TripodPositionsCapability: Hashable, Sendable {
    case returnHome, create, switchMapList, selectMapLocation, showLinkedProjects, filterProjects, openProjectSummary
    case filterVisibleLocations, showSelectionState
    case addReference, openProject, openMap, scheduleRecapture, showMetrics
}
enum TripodPositionsCapabilityPolicy {
    static let catalog: Set<TripodPositionsCapability> = [
        .create, .switchMapList, .selectMapLocation, .showLinkedProjects,
        .filterProjects, .openProjectSummary, .filterVisibleLocations,
        .showSelectionState, .returnHome
    ]
    static let detail: Set<TripodPositionsCapability> = [.addReference, .openProject, .openMap, .scheduleRecapture, .showMetrics]
}

enum TripodPositionsViewMode: String, CaseIterable, Identifiable, Sendable {
    case map, list

    var id: String { rawValue }
    var title: String { self == .map ? "Mapa" : "Lista" }
}

enum TripodLocationSelection {
    static let initial: UUID? = nil

    static func toggle(current: UUID?, tapped: UUID) -> UUID? {
        current == tapped ? nil : tapped
    }
}

enum TripodPositionsCatalogPresentation {
    static let savedPositionsDestination = TripodPositionsViewMode.list
}

struct TripodMapCameraRegion: Equatable, Sendable {
    let centerLatitude: Double
    let centerLongitude: Double
    let latitudeDelta: Double
    let longitudeDelta: Double

    var minimumLatitude: Double { centerLatitude - latitudeDelta / 2 }
    var maximumLatitude: Double { centerLatitude + latitudeDelta / 2 }
    var minimumLongitude: Double { centerLongitude - longitudeDelta / 2 }
    var maximumLongitude: Double { centerLongitude + longitudeDelta / 2 }
}

enum TripodMapCameraFit {
    static let minimumSpan = 0.006
    private static let padding = 1.45

    static func region(for locations: [TripodLocation]) -> TripodMapCameraRegion? {
        let coordinates = locations.compactMap(\.coordinate)
        guard let first = coordinates.first else { return nil }
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minimumLatitude = latitudes.min() ?? first.latitude
        let maximumLatitude = latitudes.max() ?? first.latitude
        let minimumLongitude = longitudes.min() ?? first.longitude
        let maximumLongitude = longitudes.max() ?? first.longitude
        return TripodMapCameraRegion(
            centerLatitude: (minimumLatitude + maximumLatitude) / 2,
            centerLongitude: (minimumLongitude + maximumLongitude) / 2,
            latitudeDelta: max((maximumLatitude - minimumLatitude) * padding, minimumSpan),
            longitudeDelta: max((maximumLongitude - minimumLongitude) * padding, minimumSpan)
        )
    }
}

enum TripodMapViewport {
    static func locations(
        in region: TripodMapCameraRegion,
        from locations: [TripodLocation]
    ) -> [TripodLocation] {
        locations.filter { location in
            guard let coordinate = location.coordinate,
                  coordinate.latitude >= region.minimumLatitude,
                  coordinate.latitude <= region.maximumLatitude else { return false }
            return containsLongitude(coordinate.longitude, in: region)
        }
    }

    private static func containsLongitude(_ longitude: Double, in region: TripodMapCameraRegion) -> Bool {
        guard region.longitudeDelta < 360 else { return true }
        let minimum = normalizedLongitude(region.minimumLongitude)
        let maximum = normalizedLongitude(region.maximumLongitude)
        let value = normalizedLongitude(longitude)
        return minimum <= maximum ? (minimum...maximum).contains(value) : value >= minimum || value <= maximum
    }

    private static func normalizedLongitude(_ longitude: Double) -> Double {
        var result = longitude.truncatingRemainder(dividingBy: 360)
        if result > 180 { result -= 360 }
        if result < -180 { result += 360 }
        return result
    }
}

struct TripodCoordinateEvidence: Equatable, Sendable {
    let capturedAt: Date
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
}

enum TripodCoordinateBackfill {
    static func resolve(_ evidence: [TripodCoordinateEvidence]) -> TripodCoordinate? {
        guard let newest = evidence.max(by: { $0.capturedAt < $1.capturedAt }) else { return nil }
        return TripodCoordinate(
            latitude: newest.latitude,
            longitude: newest.longitude,
            horizontalAccuracy: newest.horizontalAccuracy
        )
    }
}

struct TripodPositionMetrics: Equatable, Sendable {
    let gpsAccuracy: String
    let projectCount: String
    let referenceCount: String
    let coordinateText: String

    init(location: TripodLocation) {
        if let accuracy = location.coordinate?.horizontalAccuracy {
            gpsAccuracy = "± \(Int(accuracy.rounded())) m"
        } else {
            gpsAccuracy = location.coordinate == nil ? "—" : "GPS"
        }
        projectCount = String(format: "%02d", location.projectIDs.count)
        referenceCount = String(format: "%02d", location.referencePhotos.count)
        if let coordinate = location.coordinate {
            coordinateText = String(
                format: "%.5f, %.5f",
                locale: Locale(identifier: "en_US_POSIX"),
                coordinate.latitude,
                coordinate.longitude
            )
        } else {
            coordinateText = "GPS indisponível"
        }
    }
}

enum CaptureCalendarCapability: Hashable, Sendable {
    case returnHome, browseMonth, openDay, filterProjects, showProjectMarkers, openProjectSummary, openProject, scheduleRecapture
}
enum CaptureCalendarCapabilityPolicy {
    static let root: Set<CaptureCalendarCapability> = [.returnHome, .browseMonth, .openDay, .filterProjects, .showProjectMarkers, .openProjectSummary]
    static let summary: Set<CaptureCalendarCapability> = [.openProject, .scheduleRecapture]
}

@MainActor
final class TripodLocationStore: ObservableObject {
    @Published private(set) var snapshot: TripodLocationSnapshot = .empty
    @Published private(set) var error: Error?
    private let catalog: TripodLocationCatalog
    private let rootDirectory: URL

    init(rootDirectory: URL? = nil) {
        let root = rootDirectory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.rootDirectory = root
        catalog = TripodLocationCatalog(rootDirectory: root)
        reload()
    }

    func reload() { Task { await reloadNow() } }
    func reloadNow() async {
        do { snapshot = try await catalog.load(); error = nil } catch { self.error = error }
    }
    func create(name: String, note: String?, coordinate: TripodCoordinate?) async throws -> TripodLocation {
        let value = try await catalog.create(name: name, note: note, coordinate: coordinate); await reloadNow(); return value
    }
    func update(_ location: TripodLocation) async throws { try await catalog.update(location); await reloadNow() }
    func link(projectID: UUID, to locationID: UUID) async throws { try await catalog.link(projectID: projectID, to: locationID); await reloadNow() }
    func addReferencePhoto(data: Data, to locationID: UUID) async throws {
        let id = UUID()
        let relativePath = "TripodLocations/\(locationID.uuidString)/References/\(id.uuidString).jpg"
        let url = rootDirectory.appendingPathComponent("Application Support/Camerae").appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try await catalog.addReferencePhoto(.init(id: id, relativePath: relativePath), to: locationID)
        await reloadNow()
    }
    func referencePhotoURL(_ photo: TripodReferencePhoto) -> URL {
        rootDirectory
            .appendingPathComponent("Application Support/Camerae")
            .appendingPathComponent(photo.relativePath)
    }
    func migrateLegacyProjects(_ projects: [CameraProject]) async {
        for project in projects where project.module == .repeatable {
            let recoveredCoordinate = TripodCoordinateBackfill.resolve(
                TimelapseSessionStore(project: project).sessionSummaries().compactMap { summary in
                    guard let pose = summary.session.referenceGeoPose else { return nil }
                    return TripodCoordinateEvidence(
                        capturedAt: summary.session.createdAt,
                        latitude: pose.latitude,
                        longitude: pose.longitude,
                        horizontalAccuracy: pose.horizontalAccuracy
                    )
                }
            )

            if var existing = snapshot.location(forProjectID: project.id) {
                if existing.coordinate == nil, let recoveredCoordinate {
                    existing.coordinate = recoveredCoordinate
                    try? await catalog.update(existing)
                }
                continue
            }

            let source = project.directoryURL.appendingPathComponent("spatial_reference", isDirectory: true)
            guard FileManager.default.fileExists(atPath: source.path),
                  let location = try? await catalog.create(name: project.name, coordinate: recoveredCoordinate) else { continue }
            let relativePath = "TripodLocations/\(location.id.uuidString)/SpatialRevisions/\(project.id.uuidString)"
            let target = rootDirectory.appendingPathComponent("Application Support/Camerae").appendingPathComponent(relativePath, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: target)
                try await catalog.addSpatialRevision(.init(id: UUID(), relativePackagePath: relativePath, createdAt: project.updatedAt, sourceProjectID: project.id), to: location.id)
                try await catalog.link(projectID: project.id, to: location.id)
            } catch { self.error = error }
        }
        await reloadNow()
    }
    func seedProject(_ project: CameraProject, from locationID: UUID) throws {
        guard let revision = snapshot.location(id: locationID)?.spatialRevisions.sorted(by: { $0.createdAt > $1.createdAt }).first else { return }
        let source = rootDirectory.appendingPathComponent("Application Support/Camerae").appendingPathComponent(revision.relativePackagePath, isDirectory: true)
        let target = project.directoryURL.appendingPathComponent("spatial_reference", isDirectory: true)
        guard FileManager.default.fileExists(atPath: source.path), !FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.copyItem(at: source, to: target)
    }
    func schedule(locationID: UUID, projectID: UUID?, weeks: Int, note: String?) async throws {
        let plan = try await catalog.scheduleRecapture(locationID: locationID, projectID: projectID, afterWeeks: weeks, note: note)
        await reloadNow()
        guard plan.reminderEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Hora de repetir a captura"
        content.body = note ?? snapshot.location(id: locationID)?.name ?? "Posição salva"
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.scheduledAt)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: plan.id.uuidString, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
    }
}

struct TripodPositionsView: View {
    @EnvironmentObject private var store: TripodLocationStore
    @EnvironmentObject private var projects: ProjectStore
    @State private var viewMode = TripodPositionsViewMode.map
    @State private var selectedLocationID = TripodLocationSelection.initial
    @State private var isCreating = false
    @State private var mapPosition = MapCameraPosition.automatic
    @State private var visibleMapRegion: TripodMapCameraRegion?
    @State private var hasUserAdjustedMap = false
    @State private var filter = CalendarProjectFilter.all

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                modePicker

                if store.snapshot.locations.isEmpty {
                    emptyState
                } else if viewMode == .map {
                    mapCard
                } else {
                    LazyVStack(spacing: 12) {
                        HStack {
                            CameraeNextSectionLabel(title: "Posições visíveis", theme: theme)
                            Spacer()
                            Text("\(visibleLocations.count)")
                                .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
                                .foregroundStyle(theme.muted)
                        }
                        ForEach(visibleLocations) { location in
                            Button { toggleSelection(location.id) } label: {
                                TripodLocationCatalogRow(
                                    location: location,
                                    subtitle: listSubtitle(for: location),
                                    referenceImage: referenceImage(for: location),
                                    isSelected: selectedLocationID == location.id,
                                    theme: theme
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let selectedLocation {
                    ProjectContextListSection(
                        title: selectedLocation.name,
                        items: linkedProjectItems,
                        filter: $filter,
                        theme: theme
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .tint(theme.accent)
        .preferredColorScheme(.light)
        .navigationDestination(for: TripodLocation.self) { TripodLocationDetailView(locationID: $0.id) }
        .navigationDestination(for: CalendarProjectAgendaItem.self) { item in
            CalendarProjectSummaryView(
                item: item,
                history: agendaItems.filter { $0.projectID == item.projectID }.sorted { $0.date > $1.date }
            )
        }
        .sheet(isPresented: $isCreating) { TripodLocationEditorView() }
        .onAppear {
            store.reload()
            fitMapToLocations()
        }
        .onChange(of: store.snapshot.locations) { _, _ in
            fitMapToLocations()
        }
    }

    private let theme = CameraeNextTheme(workflow: .repeatable)

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("POSIÇÕES")
                    .font(.custom("DMMono-Medium", size: 11, relativeTo: .caption))
                    .tracking(1.2)
                    .foregroundStyle(theme.accent)
                Text("Seus pontos de tripé")
                    .font(.custom("Outfit-SemiBold", size: 28, relativeTo: .title))
                    .foregroundStyle(theme.text)
            }
            Spacer()
            Button { isCreating = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(theme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Nova posição")
        }
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(TripodPositionsViewMode.allCases) { mode in
                Button(mode.title) { viewMode = mode }
                    .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                    .foregroundStyle(viewMode == mode ? Color.white : theme.muted)
                    .frame(width: 79, height: 34)
                    .background(viewMode == mode ? theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tripod.positions.mode.\(mode.rawValue)")
            }
        }
        .padding(4)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mapCard: some View {
        ZStack(alignment: .bottomLeading) {
            Map(position: $mapPosition) {
                ForEach(locationsWithGPS) { location in
                    if let coordinate = location.coordinate {
                        Annotation(
                            location.name,
                            coordinate: CLLocationCoordinate2D(
                                latitude: coordinate.latitude,
                                longitude: coordinate.longitude
                            ),
                            anchor: .center
                        ) {
                            Button { toggleSelection(location.id) } label: {
                                mapThumbnail(for: location)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(location.name)
                            .accessibilityIdentifier("tripod.positions.marker.\(location.id.uuidString)")
                        }
                        .annotationTitles(.hidden)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                guard hasUserAdjustedMap else { return }
                updateVisibleRegion(context.region)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 1).onChanged { _ in hasUserAdjustedMap = true }
            )
            .simultaneousGesture(
                MagnifyGesture().onChanged { _ in hasUserAdjustedMap = true }
            )

            if locationsWithGPS.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NENHUMA POSIÇÃO COM GPS")
                        .font(.custom("DMMono-Medium", size: 11, relativeTo: .caption))
                        .foregroundStyle(theme.accent)
                    Text("Abra a lista para consultar os pontos salvos.")
                        .font(.custom("Outfit-Regular", size: 14, relativeTo: .subheadline))
                        .foregroundStyle(theme.muted)
                }
                .padding(16)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(16)
            }

            if let selectedLocation {
                selectedLocationBadge(selectedLocation)
                .padding(16)
            }
        }
        .frame(height: 270)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var savedPositionsSummary: some View {
        Button { viewMode = TripodPositionsCatalogPresentation.savedPositionsDestination } label: {
            savedPositionsSummaryContent
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abrir lista de posições salvas")
        .accessibilityIdentifier("tripod.positions.open-list")
    }

    private var savedPositionsSummaryContent: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(store.snapshot.locations.count) POSIÇÕES SALVAS")
                    .font(.custom("DMMono-Medium", size: 11, relativeTo: .caption))
                    .tracking(1.1)
                    .foregroundStyle(theme.accent)
                Text(mapSummaryText)
                    .font(.custom("Outfit-Regular", size: 14, relativeTo: .subheadline))
                    .foregroundStyle(theme.muted)
            }
            Spacer()
            Text("ABRIR  ›")
                .font(.custom("DMMono-Medium", size: 10, relativeTo: .caption2))
                .foregroundStyle(theme.accent)
        }
        .padding(.horizontal, 16)
        .frame(height: 76)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Nenhuma posição ainda",
            systemImage: "mappin.and.ellipse",
            description: Text("Salve GPS, fotos e a referência espacial do ponto onde o tripé volta.")
        )
        .foregroundStyle(theme.text)
        .frame(maxWidth: .infinity, minHeight: 380)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var selectedLocation: TripodLocation? {
        selectedLocationID.flatMap { store.snapshot.location(id: $0) }
    }

    private var locationsWithGPS: [TripodLocation] {
        store.snapshot.locations.filter { $0.coordinate != nil }
    }

    private var visibleLocations: [TripodLocation] {
        guard let visibleMapRegion else { return locationsWithGPS }
        return TripodMapViewport.locations(in: visibleMapRegion, from: store.snapshot.locations)
    }

    private var agendaItems: [CalendarProjectAgendaItem] {
        ProjectContextCatalog.agenda(snapshot: store.snapshot, projects: projects.projects)
    }

    private var linkedProjectItems: [CalendarProjectAgendaItem] {
        guard let selectedLocationID else { return [] }
        return ProjectContextCatalog.projects(at: selectedLocationID, from: agendaItems)
    }

    @ViewBuilder
    private func mapThumbnail(for location: TripodLocation) -> some View {
        let selected = selectedLocationID == location.id
        Group {
            if let image = referenceImage(for: location) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(selected ? theme.accent : theme.muted)
                    .overlay {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(
            width: selected ? 52 : 44,
            height: selected ? 52 : 44
        )
        .clipShape(Circle())
        .overlay { Circle().stroke(selected ? theme.accent : Color.white, lineWidth: selected ? 4 : 3) }
        .shadow(color: .black.opacity(0.24), radius: 4, y: 2)
        .animation(.easeOut(duration: 0.16), value: selectedLocationID)
    }

    private func fitMapToLocations() {
        hasUserAdjustedMap = false
        guard let fitted = TripodMapCameraFit.region(for: store.snapshot.locations) else {
            mapPosition = .automatic
            visibleMapRegion = nil
            return
        }
        mapPosition = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: fitted.centerLatitude,
                longitude: fitted.centerLongitude
            ),
            span: MKCoordinateSpan(
                latitudeDelta: fitted.latitudeDelta,
                longitudeDelta: fitted.longitudeDelta
            )
        ))
        visibleMapRegion = fitted
    }

    private func toggleSelection(_ locationID: UUID) {
        selectedLocationID = TripodLocationSelection.toggle(
            current: selectedLocationID,
            tapped: locationID
        )
    }

    private func updateVisibleRegion(_ region: MKCoordinateRegion) {
        let visible = TripodMapCameraRegion(
            centerLatitude: region.center.latitude,
            centerLongitude: region.center.longitude,
            latitudeDelta: region.span.latitudeDelta,
            longitudeDelta: region.span.longitudeDelta
        )
        visibleMapRegion = visible
        if let selectedLocationID,
           !TripodMapViewport.locations(in: visible, from: store.snapshot.locations)
            .contains(where: { $0.id == selectedLocationID }) {
            self.selectedLocationID = nil
        }
    }

    private func selectedLocationBadge(_ location: TripodLocation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(location.name)
                .font(.custom("Outfit-Regular", size: 16, relativeTo: .body))
                .foregroundStyle(theme.text)
                .lineLimit(1)
            Text(latestCaptureText(for: location))
                .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                .foregroundStyle(theme.accent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(width: 250, height: 64)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var mapSummaryText: String {
        let withGPS = store.snapshot.locations.count { $0.coordinate != nil }
        let withoutGPS = store.snapshot.locations.count - withGPS
        if withoutGPS == 0 { return "\(withGPS) pontos disponíveis no mapa" }
        return "\(withGPS) com GPS · \(withoutGPS) sem GPS"
    }

    private func linkedProjects(for location: TripodLocation) -> [CameraProject] {
        projects.projects.filter { location.projectIDs.contains($0.id) }
    }

    private func latestCaptureDate(for location: TripodLocation) -> Date? {
        linkedProjects(for: location)
            .flatMap { TimelapseSessionStore(project: $0).sessionSummaries() }
            .map(\.session.createdAt)
            .max()
    }

    private func latestCaptureText(for location: TripodLocation) -> String {
        guard let date = latestCaptureDate(for: location) else { return "Ainda sem capturas" }
        if Calendar.current.isDateInToday(date) { return "Última captura · hoje" }
        return "Última captura · \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    private func listSubtitle(for location: TripodLocation) -> String {
        let count = location.projectIDs.count
        let projectText = count == 1 ? "1 projeto" : "\(count) projetos"
        guard let date = latestCaptureDate(for: location) else { return "\(projectText) · sem capturas" }
        let dateText = Calendar.current.isDateInToday(date)
            ? "hoje"
            : date.formatted(.dateTime.day().month(.abbreviated))
        return "\(projectText) · \(dateText)"
    }

    private func referenceImage(for location: TripodLocation) -> UIImage? {
        guard let photo = location.referencePhotos.last else { return nil }
        return UIImage(contentsOfFile: store.referencePhotoURL(photo).path)
    }
}

private struct TripodLocationCatalogRow: View {
    let location: TripodLocation
    let subtitle: String
    let referenceImage: UIImage?
    let isSelected: Bool
    let theme: CameraeNextTheme

    var body: some View {
        HStack(spacing: 18) {
            Group {
                if let referenceImage {
                    Image(uiImage: referenceImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(theme.accent.opacity(location.coordinate == nil ? 0.42 : 1))
                        .overlay {
                            Image(systemName: location.coordinate == nil ? "mappin.slash" : "mappin.and.ellipse")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(.white.opacity(0.92))
                        }
                }
            }
            .frame(width: 98, height: 98)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? theme.accent : Color.clear, lineWidth: 3)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(location.name)
                    .font(.custom("Outfit-SemiBold", size: 18, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.custom("DMMono-Medium", size: 11, relativeTo: .caption))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
                Text(isSelected ? "SELECIONADO" : "SELECIONAR")
                    .font(.custom("DMMono-Medium", size: 10, relativeTo: .caption2))
                    .foregroundStyle(theme.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .leading)
        .background(isSelected ? theme.surface : theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isSelected ? theme.accent : Color.clear, lineWidth: 2)
        }
    }
}

struct TripodLocationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TripodLocationStore
    @State private var name = ""
    @State private var note = ""
    @State private var latitude = ""
    @State private var longitude = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Identificação") { TextField("Nome da posição", text: $name); TextField("Notas para encontrar o ponto", text: $note, axis: .vertical) }
                Section("GPS opcional") { TextField("Latitude", text: $latitude).keyboardType(.numbersAndPunctuation); TextField("Longitude", text: $longitude).keyboardType(.numbersAndPunctuation) }
                Section { Label("Faça as referências sem o tripé na cena. Depois posicione o tripé e selecione sua base.", systemImage: "viewfinder") }
            }
            .navigationTitle("Nova posição")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar") { Task { _ = try? await store.create(name: name, note: note.nilIfEmpty, coordinate: coordinate); dismiss() } } }
            }
        }
    }
    private var coordinate: TripodCoordinate? { guard let lat = Double(latitude), let lon = Double(longitude) else { return nil }; return .init(latitude: lat, longitude: lon) }
}

struct TripodLocationDetailView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: TripodLocationStore
    @EnvironmentObject private var projects: ProjectStore
    let locationID: UUID
    @State private var isPlanning = false
    @State private var selectedPhoto: PhotosPickerItem?

    private var location: TripodLocation? { store.snapshot.location(id: locationID) }
    var body: some View {
        ScrollView {
            if let location {
                VStack(alignment: .leading, spacing: 14) {
                    referenceHero(location)
                    HStack(spacing: 10) {
                        let metrics = TripodPositionMetrics(location: location)
                        metricCard("GPS", value: metrics.gpsAccuracy)
                        metricCard("PROJETOS", value: metrics.projectCount)
                        metricCard("REFERÊNCIAS", value: metrics.referenceCount)
                    }
                    locationCard(location)
                    CameraeNextSectionLabel(title: "Projetos nesta posição", theme: theme)
                    if linkedProjects(for: location).isEmpty {
                        Text("Nenhum projeto vinculado a esta posição.")
                            .font(.custom("Outfit-Regular", size: 13, relativeTo: .footnote))
                            .foregroundStyle(theme.muted)
                            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
                            .padding(.horizontal, 14)
                            .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        ForEach(linkedProjects(for: location)) { project in
                            NavigationLink(value: project) { linkedProjectRow(project) }
                                .buttonStyle(.plain)
                        }
                    }
                    HStack(spacing: 10) {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Text("ADICIONAR REFERÊNCIA")
                                .font(.custom("Outfit-SemiBold", size: 11, relativeTo: .caption))
                                .foregroundStyle(theme.text)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(theme.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        Button("PLANEJAR RETORNO") { isPlanning = true }
                            .font(.custom("Outfit-SemiBold", size: 11, relativeTo: .caption))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(theme.accent, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .background(theme.background)
        .foregroundStyle(theme.text)
        .tint(theme.accent)
        .preferredColorScheme(.light)
        .navigationTitle("Detalhe da posição")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if let location, location.coordinate != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Abrir no Mapas", systemImage: "map") { openInMaps(location) }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .sheet(isPresented: $isPlanning) { RecapturePlannerView(locationID: locationID) }
        .onChange(of: selectedPhoto) { _, item in Task { if let data = try? await item?.loadTransferable(type: Data.self) { try? await store.addReferencePhoto(data: data, to: locationID) } } }
    }

    private let theme = CameraeNextTheme(workflow: .repeatable)

    private func referenceHero(_ location: TripodLocation) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let image = referenceImage(for: location) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.72)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [theme.accent.opacity(0.72), theme.accent],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                TripodReferenceHeroArtwork()
                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("FOTO DE REFERÊNCIA").font(.custom("DMMono-Regular", size: 10)).tracking(1.2)
                Text(location.name).font(.custom("Outfit-SemiBold", size: 28, relativeTo: .title))
                if let note = location.note { Text(note).font(.custom("Outfit-Regular", size: 12)) }
            }
            .foregroundStyle(.white)
            .padding(18)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func metricCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.custom("DMMono-Regular", size: 9)).tracking(1.1).foregroundStyle(theme.muted)
            Text(value).font(.custom("Outfit-SemiBold", size: 22)).foregroundStyle(title == "GPS" ? theme.accent : theme.text)
        }.frame(maxWidth: .infinity, minHeight: 68, alignment: .leading).padding(10).background(theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func locationCard(_ location: TripodLocation) -> some View {
        let metrics = TripodPositionMetrics(location: location)
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                CameraeNextSectionLabel(title: "Localização", theme: theme)
                Text(metrics.coordinateText)
                    .font(.custom("Outfit-Regular", size: 14))
            }
            Spacer()
            if location.coordinate != nil {
                Button("ABRIR MAPA  ›") { openInMaps(location) }
                    .font(.custom("DMMono-Medium", size: 9, relativeTo: .caption2))
                    .foregroundStyle(theme.accent)
                    .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(minHeight: 72)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private func linkedProjects(for location: TripodLocation) -> [CameraProject] {
        projects.projects.filter { location.projectIDs.contains($0.id) }
    }

    private func linkedProjectRow(_ project: CameraProject) -> some View {
        let presentation = ProjectListCardPresentation(
            summaries: TimelapseSessionStore(project: project).sessionSummaries(),
            fallbackHardware: project.captureProfile?.hardware
        )
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.accent.gradient)
                .frame(width: 52, height: 46)
                .overlay(Image(systemName: "camera.fill").foregroundStyle(.white.opacity(0.9)))
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.custom("Outfit-SemiBold", size: 15, relativeTo: .body))
                    .foregroundStyle(theme.text)
                Text(presentation.lastCaptureText ?? "Ainda sem capturas")
                    .font(.custom("Outfit-Regular", size: 11, relativeTo: .caption))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.muted)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 70)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func openInMaps(_ location: TripodLocation) {
        guard let coordinate = location.coordinate else { return }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "q", value: location.name)
        ]
        if let url = components?.url { openURL(url) }
    }

    private func referenceImage(for location: TripodLocation) -> UIImage? {
        guard let photo = location.referencePhotos.last else { return nil }
        return UIImage(contentsOfFile: store.referencePhotoURL(photo).path)
    }
}

private struct TripodReferenceHeroArtwork: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.maxX * 0.73, y: rect.minY + rect.height * 0.42)
        for inset in stride(from: CGFloat(0), through: rect.width * 0.55, by: 22) {
            path.addEllipse(in: CGRect(
                x: center.x - inset,
                y: center.y - inset * 0.62,
                width: inset * 2,
                height: inset * 1.24
            ))
        }
        path.move(to: CGPoint(x: rect.minX - 20, y: rect.height * 0.34))
        path.addCurve(
            to: CGPoint(x: rect.maxX + 20, y: rect.height * 0.18),
            control1: CGPoint(x: rect.width * 0.28, y: rect.height * 0.08),
            control2: CGPoint(x: rect.width * 0.62, y: rect.height * 0.42)
        )
        return path
    }
}

struct CaptureCalendarView: View {
    @EnvironmentObject private var store: TripodLocationStore
    @EnvironmentObject private var projects: ProjectStore
    @State private var selectedDate = Date()
    @State private var visibleMonth = Date()
    @State private var filter = CalendarProjectFilter.all

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CALENDÁRIO")
                        .font(.custom("DMMono-Medium", size: 11, relativeTo: .caption))
                        .foregroundStyle(theme.accent)
                    Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
                        .font(.custom("Outfit-SemiBold", size: 28, relativeTo: .title))
                        .foregroundStyle(theme.text)
                }

                CameraeCalendarMonthGrid(
                    visibleMonth: $visibleMonth,
                    selectedDate: $selectedDate,
                    markedDates: Set(agendaItems.map { Calendar.current.startOfDay(for: $0.date) }),
                    theme: theme
                )

                ProjectContextListSection(
                    title: selectedDate.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)),
                    items: selectedItems,
                    filter: $filter,
                    theme: theme
                )
            }
            .padding()
        }
        .background(theme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .foregroundStyle(theme.text)
        .tint(theme.accent)
        .preferredColorScheme(.light)
        .navigationDestination(for: CalendarProjectAgendaItem.self) { item in
            CalendarProjectSummaryView(
                item: item,
                history: agendaItems.filter { $0.projectID == item.projectID }.sorted { $0.date > $1.date }
            )
        }
        .onAppear { store.reload() }
    }

    private let theme = CameraeNextTheme(workflow: .repeatable)

    private var selectedItems: [CalendarProjectAgendaItem] {
        agendaItems.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    private var agendaItems: [CalendarProjectAgendaItem] {
        ProjectContextCatalog.agenda(snapshot: store.snapshot, projects: projects.projects)
    }
}

enum ProjectContextCapability: Hashable, Sendable {
    case filterProjects, openProjectSummary, openProject, scheduleRecapture
}

enum ProjectContextCapabilityPolicy {
    static let list: Set<ProjectContextCapability> = [.filterProjects, .openProjectSummary]
    static let summary: Set<ProjectContextCapability> = [.openProject, .scheduleRecapture]
}

enum ProjectContextCatalog {
    static func agenda(
        snapshot: TripodLocationSnapshot,
        projects: [CameraProject]
    ) -> [CalendarProjectAgendaItem] {
        let planned = snapshot.calendarEntries.compactMap { entry -> CalendarProjectAgendaItem? in
            guard entry.kind == .planned,
                  let location = snapshot.location(id: entry.locationID) else { return nil }
            let project = entry.projectID.flatMap { id in projects.first { $0.id == id } }
            return CalendarProjectAgendaItem(
                id: entry.id,
                kind: .planned,
                date: entry.date,
                projectID: project?.id,
                locationID: location.id,
                locationTitle: location.name,
                title: project?.name ?? location.name,
                detail: "Retorno planejado · \(entry.date.formatted(date: .omitted, time: .shortened))",
                session: nil
            )
        }
        let captured = projects.flatMap { project -> [CalendarProjectAgendaItem] in
            guard let location = snapshot.location(forProjectID: project.id) else { return [] }
            return TimelapseSessionStore(project: project).sessionSummaries().map { summary in
                CalendarProjectAgendaItem(
                    id: summary.id,
                    kind: .captured,
                    date: summary.session.createdAt,
                    projectID: project.id,
                    locationID: location.id,
                    locationTitle: location.name,
                    title: project.name,
                    detail: "Captura concluída · \(summary.session.createdAt.formatted(date: .omitted, time: .shortened))",
                    session: .init(
                        captureKind: summary.captureKind.title,
                        lens: summary.session.cameraLens?.title ?? "—",
                        frameCount: summary.frameCount,
                        duration: summary.captureDuration
                    )
                )
            }
        }
        let created = projects.compactMap { project -> CalendarProjectAgendaItem? in
            guard let location = snapshot.location(forProjectID: project.id) else { return nil }
            return CalendarProjectAgendaItem(
                id: project.id,
                kind: .created,
                date: project.createdAt,
                projectID: project.id,
                locationID: location.id,
                locationTitle: location.name,
                title: project.name,
                detail: "Projeto criado nesta posição",
                session: nil
            )
        }
        return (planned + captured + created).sorted { $0.date < $1.date }
    }

    static func projects(
        at locationID: UUID,
        from items: [CalendarProjectAgendaItem]
    ) -> [CalendarProjectAgendaItem] {
        let linked = items.filter { $0.locationID == locationID && $0.projectID != nil }
        let latestByProject = Dictionary(grouping: linked, by: \.projectID).compactMap { _, entries in
            entries.max { $0.date < $1.date }
        }
        return latestByProject.sorted { $0.date > $1.date }
    }
}

enum CalendarProjectAgendaKind: Hashable, Sendable { case captured, planned, created }

struct CalendarProjectSessionSummary: Hashable, Sendable {
    let captureKind: String
    let lens: String
    let frameCount: Int
    let duration: TimeInterval?
}

struct CalendarProjectAgendaItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: CalendarProjectAgendaKind
    let date: Date
    let projectID: UUID?
    let locationID: UUID
    let locationTitle: String
    let title: String
    let detail: String
    let session: CalendarProjectSessionSummary?
}

enum CalendarProjectFilter: String, CaseIterable, Identifiable, Sendable {
    case all, captures, returns
    var id: String { rawValue }
    var title: String { switch self { case .all: "Todos"; case .captures: "Capturas"; case .returns: "Retornos" } }
    func apply(to items: [CalendarProjectAgendaItem]) -> [CalendarProjectAgendaItem] {
        switch self {
        case .all: items
        case .captures: items.filter { $0.kind == .captured }
        case .returns: items.filter { $0.kind == .planned }
        }
    }
}

private struct CameraeCalendarMonthGrid: View {
    @Binding var visibleMonth: Date
    @Binding var selectedDate: Date
    let markedDates: Set<Date>
    let theme: CameraeNextTheme
    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(visibleMonth.formatted(.dateTime.month(.wide)).uppercased())
                    .font(.custom("DMMono-Medium", size: 11, relativeTo: .caption))
                Spacer()
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
            }
            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(calendar.veryShortWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol.uppercased()).font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2)).foregroundStyle(theme.muted)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in dayCell(day) }
            }
        }
        .padding(12)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var days: [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: visibleMonth),
              let gridStart = calendar.dateInterval(of: .weekOfMonth, for: interval.start)?.start else { return [] }
        guard let monthEnd = calendar.date(byAdding: .day, value: -1, to: interval.end),
              let fifthWeekEnd = calendar.date(byAdding: .day, value: 34, to: gridStart) else { return [] }
        let count = monthEnd > fifthWeekEnd ? 42 : 35
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private func dayCell(_ day: Date) -> some View {
        let selected = calendar.isDate(day, inSameDayAs: selectedDate)
        let insideMonth = calendar.isDate(day, equalTo: visibleMonth, toGranularity: .month)
        let marked = markedDates.contains(calendar.startOfDay(for: day))
        return Button { selectedDate = day } label: {
            VStack(spacing: 1) {
                Text(day.formatted(.dateTime.day()))
                    .font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
                Circle().fill(selected ? Color.white : theme.accent).frame(width: 5, height: 5).opacity(marked ? 1 : 0)
            }
            .foregroundStyle(selected ? Color.white : (insideMonth ? theme.text : theme.muted))
            .frame(maxWidth: .infinity).frame(height: 34)
            .background(selected ? theme.accent : Color.clear, in: Circle())
        }.buttonStyle(.plain)
    }

    private func moveMonth(_ offset: Int) {
        guard let next = calendar.date(byAdding: .month, value: offset, to: visibleMonth) else { return }
        visibleMonth = next
        selectedDate = next
    }
}

private struct ProjectContextListSection: View {
    let title: String
    let items: [CalendarProjectAgendaItem]
    @Binding var filter: CalendarProjectFilter
    let theme: CameraeNextTheme

    private var filteredItems: [CalendarProjectAgendaItem] { filter.apply(to: items) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CameraeNextSectionLabel(title: title, theme: theme)
                Spacer()
                Text("\(items.count) PROJETOS")
                    .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
                    .tracking(2.2)
                    .foregroundStyle(theme.muted)
            }

            HStack(spacing: 8) {
                ForEach(CalendarProjectFilter.allCases) { candidate in
                    Button(candidate.title) { filter = candidate }
                        .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                        .foregroundStyle(filter == candidate ? Color.white : theme.text)
                        .padding(.horizontal, 18)
                        .frame(height: 34)
                        .background(filter == candidate ? theme.accent : theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .buttonStyle(.plain)
                }
            }

            if filteredItems.isEmpty {
                ContentUnavailableView("Nenhum projeto neste contexto", systemImage: "rectangle.stack")
                    .foregroundStyle(theme.text)
            } else {
                ForEach(filteredItems) { item in
                    NavigationLink(value: item) { CalendarProjectAgendaRow(item: item, theme: theme) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct CalendarProjectAgendaRow: View {
    let item: CalendarProjectAgendaItem
    let theme: CameraeNextTheme
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(item.kind == .captured ? Color.green : theme.accent).frame(width: 4, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.custom("Outfit-Regular", size: 16, relativeTo: .body)).foregroundStyle(theme.text)
                Text(item.detail).font(.custom("Outfit-Regular", size: 12, relativeTo: .caption)).foregroundStyle(theme.muted)
            }
            Spacer(); Image(systemName: "chevron.right").foregroundStyle(theme.muted)
        }
        .padding(12)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

private struct CalendarProjectSummaryView: View {
    @EnvironmentObject private var projects: ProjectStore
    let item: CalendarProjectAgendaItem
    let history: [CalendarProjectAgendaItem]
    @State private var isPlanning = false
    private let theme = CameraeNextTheme(workflow: .repeatable)
    private var project: CameraProject? { item.projectID.flatMap { id in projects.projects.first { $0.id == id } } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                CameraeNextSectionLabel(title: "Projeto do calendário", theme: theme)
                Text(item.title).font(.custom("Outfit-SemiBold", size: 28, relativeTo: .title)).foregroundStyle(theme.text)
                Text(item.detail).font(.custom("Outfit-Regular", size: 16, relativeTo: .body)).foregroundStyle(theme.muted)
                summaryCard
                metrics
                positionCard
                CameraeNextSectionLabel(title: "Histórico do projeto", theme: theme)
                ForEach(history.prefix(3)) { historyRow($0) }
                if let project {
                    NavigationLink(value: project) {
                        Text("IR PARA O PROJETO").frame(maxWidth: .infinity).frame(height: 46)
                    }
                    .font(.custom("DMMono-Medium", size: 11, relativeTo: .caption))
                    .foregroundStyle(.white).background(theme.accent, in: RoundedRectangle(cornerRadius: 17)).buttonStyle(.plain)
                }
                Button("PLANEJAR RETORNO") { isPlanning = true }
                    .font(.custom("DMMono-Medium", size: 11, relativeTo: .caption))
                    .foregroundStyle(theme.accent).frame(maxWidth: .infinity).frame(height: 46)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 17))
                    .overlay { RoundedRectangle(cornerRadius: 17).stroke(theme.border) }
                    .buttonStyle(.plain)
            }.padding()
        }
        .background(theme.background).navigationTitle("Resumo").navigationBarTitleDisplayMode(.inline)
        .tint(theme.accent).preferredColorScheme(.light)
        .sheet(isPresented: $isPlanning) { RecapturePlannerView(locationID: item.locationID, projectID: item.projectID) }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(statusTitle)
                .font(.custom("DMMono-Medium", size: 11, relativeTo: .caption)).foregroundStyle(.white)
                .padding(.horizontal, 14).frame(height: 28).background(item.kind == .captured ? Color.green : theme.accent, in: RoundedRectangle(cornerRadius: 12))
            Text(item.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3)).foregroundStyle(theme.text)
            if let session = item.session { Text("Sessão · \(session.frameCount) fotos").font(.custom("Outfit-Regular", size: 12, relativeTo: .caption)).foregroundStyle(theme.muted) }
        }.frame(maxWidth: .infinity, minHeight: 104, alignment: .leading).padding(12).background(theme.card, in: RoundedRectangle(cornerRadius: 22))
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            metric("MODO", item.session?.captureKind.uppercased() ?? "—")
            metric("LENTE", item.session?.lens.uppercased() ?? "—")
            metric("SESSÃO", String(format: "%02d", max(history.count, 1)))
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2)).tracking(1.4).foregroundStyle(theme.muted)
            Text(value).font(.custom("Outfit-Medium", size: 22, relativeTo: .title2)).foregroundStyle(title == "SESSÃO" ? theme.accent : theme.text).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, minHeight: 60, alignment: .leading).padding(10).background(theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private var positionCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "scope").foregroundStyle(theme.accent).frame(width: 42, height: 42).background(theme.surface, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                CameraeNextSectionLabel(title: "Posição vinculada", theme: theme)
                Text(storeLocationName).font(.custom("Outfit-Regular", size: 16, relativeTo: .body)).foregroundStyle(theme.text)
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(theme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var storeLocationName: String { item.locationTitle }

    private var statusTitle: String {
        switch item.kind { case .captured: "CONCLUÍDO"; case .planned: "PLANEJADO"; case .created: "PROJETO" }
    }

    private func historyRow(_ entry: CalendarProjectAgendaItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(theme.accent).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date.formatted(.dateTime.day().month(.abbreviated).hour().minute())).font(.custom("DMMono-Medium", size: 11, relativeTo: .caption))
                Text(entry.detail).font(.custom("Outfit-Regular", size: 12, relativeTo: .caption)).foregroundStyle(theme.muted)
            }
        }.frame(minHeight: 42)
    }
}

struct RecapturePlannerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TripodLocationStore
    let locationID: UUID
    var projectID: UUID? = nil
    @State private var weeks = 4
    @State private var note = ""
    @State private var notificationDenied = false
    var body: some View {
        NavigationStack {
            Form {
                Picker("Quando", selection: $weeks) { Text("Em 1 semana").tag(1); Text("Em 2 semanas").tag(2); Text("Em 4 semanas").tag(4) }
                TextField("Nota, por exemplo: repetir sem flores", text: $note, axis: .vertical)
                if notificationDenied { Label("Notificações desativadas. O plano continuará no calendário.", systemImage: "bell.slash").foregroundStyle(.orange) }
            }
            .navigationTitle("Planejar retorno")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Salvar") { Task { let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) == true; notificationDenied = !granted; try? await store.schedule(locationID: locationID, projectID: projectID, weeks: weeks, note: note.nilIfEmpty); if granted { dismiss() } } } } }
        }
    }
}

private extension String { var nilIfEmpty: String? { let v = trimmingCharacters(in: .whitespacesAndNewlines); return v.isEmpty ? nil : v } }

import CameraeCore
import CoreLocation
import MapKit
import PhotosUI
import SwiftUI
import UserNotifications

enum CameraeHomeDestination: Hashable { case calendar, positions }

enum TripodPositionsCapability: Hashable, Sendable { case create, switchMapList, openLocation, addReference, createProject, linkProject, scheduleRecapture, showMetrics }
enum TripodPositionsCapabilityPolicy {
    static let catalog: Set<TripodPositionsCapability> = [.create, .switchMapList, .openLocation]
    static let detail: Set<TripodPositionsCapability> = [.addReference, .createProject, .linkProject, .scheduleRecapture, .showMetrics]
}

enum CaptureCalendarCapability: Hashable, Sendable {
    case browseMonth, openDay, filterProjects, showProjectMarkers, openProjectSummary, openProject, scheduleRecapture
}
enum CaptureCalendarCapabilityPolicy {
    static let root: Set<CaptureCalendarCapability> = [.browseMonth, .openDay, .filterProjects, .showProjectMarkers, .openProjectSummary]
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
    func migrateLegacyProjects(_ projects: [CameraProject]) async {
        for project in projects where project.module == .repeatable && snapshot.location(forProjectID: project.id) == nil {
            let source = project.directoryURL.appendingPathComponent("spatial_reference", isDirectory: true)
            guard FileManager.default.fileExists(atPath: source.path), let location = try? await catalog.create(name: project.name) else { continue }
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
    @State private var showsList = false
    @State private var isCreating = false

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            if store.snapshot.locations.isEmpty {
                ContentUnavailableView("Nenhuma posição ainda", systemImage: "mappin.and.ellipse", description: Text("Salve GPS, fotos e a referência espacial do ponto onde o tripé volta."))
                    .foregroundStyle(theme.text)
            } else if showsList {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.snapshot.locations) { location in
                            NavigationLink(value: location) { TripodLocationRow(location: location) }
                                .buttonStyle(.plain)
                                .padding(14)
                                .background(theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
                    .padding()
                }
            } else {
                Map {
                    ForEach(store.snapshot.locations.filter { $0.coordinate != nil }) { location in
                        if let coordinate = location.coordinate { Marker(location.name, coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)).tint(CameraeColor.accentRepeatable) }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .overlay(alignment: .bottom) {
                    if let location = store.snapshot.locations.first {
                        NavigationLink(value: location) {
                            TripodLocationRow(location: location)
                                .padding(14)
                                .background(theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(28)
                    }
                }
            }
        }
        .navigationTitle("Seus pontos de tripé")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(showsList ? "Mapa" : "Lista", systemImage: showsList ? "map" : "list.bullet") { showsList.toggle() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { isCreating = true } label: { Image(systemName: "plus").fontWeight(.semibold) }
            }
        }
        .tint(theme.accent)
        .preferredColorScheme(.light)
        .navigationDestination(for: TripodLocation.self) { TripodLocationDetailView(locationID: $0.id) }
        .sheet(isPresented: $isCreating) { TripodLocationEditorView() }
        .onAppear { store.reload() }
    }

    private let theme = CameraeNextTheme(workflow: .repeatable)
}

private struct TripodLocationRow: View {
    let location: TripodLocation
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: location.coordinate == nil ? "mappin.slash" : "mappin.circle.fill").font(.title2).foregroundStyle(CameraeColor.accentRepeatable)
            VStack(alignment: .leading) { Text(location.name).font(.custom("Outfit-SemiBold", size: 17)); Text("\(location.projectIDs.count) projetos · \(location.referencePhotos.count) referências").font(.caption).foregroundStyle(.secondary) }
            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
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
    @EnvironmentObject private var store: TripodLocationStore
    @EnvironmentObject private var projects: ProjectStore
    let locationID: UUID
    @State private var newProjectName = ""
    @State private var isCreatingProject = false
    @State private var isPlanning = false
    @State private var selectedPhoto: PhotosPickerItem?

    private var location: TripodLocation? { store.snapshot.location(id: locationID) }
    var body: some View {
        ScrollView {
            if let location {
                VStack(alignment: .leading, spacing: 14) {
                    referenceHero(location)
                    HStack(spacing: 10) {
                        metricCard("GPS", value: location.coordinate == nil ? "—" : "± 4 m")
                        metricCard("PROJETOS", value: String(format: "%02d", location.projectIDs.count))
                        metricCard("REFERÊNCIAS", value: String(format: "%02d", location.referencePhotos.count))
                    }
                    locationCard(location)
                    CameraeNextSectionLabel(title: "Projetos nesta posição", theme: theme)
                    ForEach(projects.projects.filter { location.projectIDs.contains($0.id) }) { project in
                        NavigationLink(value: project) {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 10).fill(theme.accent).frame(width: 44, height: 38)
                                Text(project.name).font(.custom("Outfit-Regular", size: 15)).foregroundStyle(theme.text)
                                Spacer(); Image(systemName: "chevron.right").foregroundStyle(theme.muted)
                            }
                            .padding(12).background(theme.card, in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain)
                    }
                    HStack(spacing: 10) {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("Referência", systemImage: "photo.badge.plus").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered)
                        Button("Planejar retorno") { isPlanning = true }.buttonStyle(.borderedProminent)
                    }
                    Button("Criar projeto nesta posição") { isCreatingProject = true }
                        .font(.custom("Outfit-SemiBold", size: 15)).frame(maxWidth: .infinity)
                }.padding()
            }
        }
        .background(theme.background)
        .foregroundStyle(theme.text)
        .tint(theme.accent)
        .preferredColorScheme(.light)
        .navigationTitle(location?.name ?? "Posição")
        .sheet(isPresented: $isCreatingProject) { CameraeNextNewProjectSheet(module: .repeatable, name: $newProjectName, defaultName: projects.defaultProjectName(for: .repeatable)) { Task { if let project = try? await projects.createProject(module: .repeatable, name: newProjectName) { try? await store.link(projectID: project.id, to: locationID); try? store.seedProject(project, from: locationID); isCreatingProject = false } } } }
        .sheet(isPresented: $isPlanning) { RecapturePlannerView(locationID: locationID) }
        .onChange(of: selectedPhoto) { _, item in Task { if let data = try? await item?.loadTransferable(type: Data.self) { try? await store.addReferencePhoto(data: data, to: locationID) } } }
    }

    private let theme = CameraeNextTheme(workflow: .repeatable)

    private func referenceHero(_ location: TripodLocation) -> some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(theme.accent.gradient)
            .frame(height: 210)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FOTO DE REFERÊNCIA").font(.custom("DMMono-Regular", size: 10)).tracking(1.2)
                    Text(location.name).font(.custom("Outfit-SemiBold", size: 24))
                    if let note = location.note { Text(note).font(.custom("Outfit-Regular", size: 12)) }
                }.foregroundStyle(.white).padding()
            }
    }

    private func metricCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.custom("DMMono-Regular", size: 9)).tracking(1.1).foregroundStyle(theme.muted)
            Text(value).font(.custom("Outfit-SemiBold", size: 22)).foregroundStyle(title == "GPS" ? theme.accent : theme.text)
        }.frame(maxWidth: .infinity, minHeight: 64, alignment: .leading).padding(10).background(theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func locationCard(_ location: TripodLocation) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                CameraeNextSectionLabel(title: "Localização", theme: theme)
                Text(location.coordinate.map { "\($0.latitude), \($0.longitude)" } ?? "GPS indisponível")
                    .font(.custom("Outfit-Regular", size: 14))
            }
            Spacer(); Image(systemName: "map").foregroundStyle(theme.accent)
        }.padding(14).background(theme.card, in: RoundedRectangle(cornerRadius: 18))
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

                HStack {
                    CameraeNextSectionLabel(
                        title: selectedDate.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)),
                        theme: theme
                    )
                    Spacer()
                    Text("\(selectedItems.count) PROJETOS")
                        .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
                        .tracking(2.2)
                        .foregroundStyle(theme.muted)
                }

                filterPicker

                if filteredItems.isEmpty {
                    ContentUnavailableView("Nenhum projeto nesta data", systemImage: "calendar")
                        .foregroundStyle(theme.text)
                } else {
                    ForEach(filteredItems) { item in
                        NavigationLink(value: item) { CalendarProjectAgendaRow(item: item, theme: theme) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .background(theme.background)
        .navigationTitle("")
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

    private var filterPicker: some View {
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
    }

    private var selectedItems: [CalendarProjectAgendaItem] {
        agendaItems.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    private var filteredItems: [CalendarProjectAgendaItem] { filter.apply(to: selectedItems) }

    private var agendaItems: [CalendarProjectAgendaItem] {
        let planned = store.snapshot.calendarEntries.compactMap { entry -> CalendarProjectAgendaItem? in
            guard entry.kind == .planned,
                  let location = store.snapshot.location(id: entry.locationID) else { return nil }
            let project = entry.projectID.flatMap { id in projects.projects.first { $0.id == id } }
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
        let captured = projects.projects.flatMap { project -> [CalendarProjectAgendaItem] in
            guard let location = store.snapshot.location(forProjectID: project.id) else { return [] }
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
        let created = projects.projects.compactMap { project -> CalendarProjectAgendaItem? in
            guard let location = store.snapshot.location(forProjectID: project.id) else { return nil }
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

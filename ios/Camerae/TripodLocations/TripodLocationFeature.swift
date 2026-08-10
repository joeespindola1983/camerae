import CameraeCore
import CoreLocation
import MapKit
import PhotosUI
import SwiftUI
import UserNotifications

enum CameraeHomeDestination: Hashable { case calendar, positions }

enum TripodPositionsCapability: Hashable, Sendable { case create, switchMapList, openLocation, addReference, createProject, linkProject, scheduleRecapture }
enum TripodPositionsCapabilityPolicy {
    static let catalog: Set<TripodPositionsCapability> = [.create, .switchMapList, .openLocation]
    static let detail: Set<TripodPositionsCapability> = [.addReference, .createProject, .linkProject, .scheduleRecapture]
}

enum CaptureCalendarCapability: Hashable, Sendable { case browseMonth, openDay, openLocation, scheduleRecapture }
enum CaptureCalendarCapabilityPolicy {
    static let root: Set<CaptureCalendarCapability> = [.browseMonth, .openDay, .openLocation, .scheduleRecapture]
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
        Group {
            if store.snapshot.locations.isEmpty {
                ContentUnavailableView("Nenhuma posição ainda", systemImage: "mappin.and.ellipse", description: Text("Salve GPS, fotos e a referência espacial do ponto onde o tripé volta."))
            } else if showsList {
                List(store.snapshot.locations) { location in NavigationLink(value: location) { TripodLocationRow(location: location) } }
            } else {
                Map {
                    ForEach(store.snapshot.locations.filter { $0.coordinate != nil }) { location in
                        if let coordinate = location.coordinate { Marker(location.name, coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)).tint(CameraeColor.accentRepeatable) }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .overlay(alignment: .bottom) {
                    if let location = store.snapshot.locations.first { NavigationLink(value: location) { TripodLocationRow(location: location).padding(14).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20)) }.buttonStyle(.plain).padding() }
                }
            }
        }
        .navigationTitle("Posições")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button(showsList ? "Mapa" : "Lista") { showsList.toggle() } }
            ToolbarItem(placement: .topBarTrailing) { Button { isCreating = true } label: { Image(systemName: "plus") } }
        }
        .navigationDestination(for: TripodLocation.self) { TripodLocationDetailView(locationID: $0.id) }
        .sheet(isPresented: $isCreating) { TripodLocationEditorView() }
        .onAppear { store.reload() }
    }
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
                VStack(alignment: .leading, spacing: 16) {
                    RoundedRectangle(cornerRadius: 24).fill(CameraeColor.accentRepeatable.opacity(0.22)).frame(height: 210).overlay(alignment: .bottomLeading) { VStack(alignment: .leading) { Text("FOTO DE REFERÊNCIA").font(.caption2.monospaced()); Text(location.name).font(.custom("Outfit-SemiBold", size: 24)) }.padding() }
                    GroupBox("Localização") { Text(location.coordinate.map { "\($0.latitude), \($0.longitude)" } ?? "GPS indisponível") }.frame(maxWidth: .infinity, alignment: .leading)
                    GroupBox("Referência espacial") { Label(location.spatialRevisions.isEmpty ? "Ainda não criada" : "Pronta para reutilizar", systemImage: location.spatialRevisions.isEmpty ? "viewfinder" : "checkmark.circle.fill") }.frame(maxWidth: .infinity, alignment: .leading)
                    PhotosPicker(selection: $selectedPhoto, matching: .images) { Label("Adicionar foto de referência", systemImage: "photo.badge.plus") }.buttonStyle(.bordered)
                    Text("Projetos nesta posição").font(.headline)
                    ForEach(projects.projects.filter { location.projectIDs.contains($0.id) }) { project in NavigationLink(value: project) { Text(project.name).frame(maxWidth: .infinity, alignment: .leading).padding().background(CameraeColor.surface, in: RoundedRectangle(cornerRadius: 16)) } }
                    Button("Criar projeto nesta posição") { isCreatingProject = true }.buttonStyle(.borderedProminent)
                    Button("Planejar nova captura") { isPlanning = true }.buttonStyle(.bordered)
                }.padding()
            }
        }
        .navigationTitle(location?.name ?? "Posição")
        .sheet(isPresented: $isCreatingProject) { CameraeNextNewProjectSheet(module: .repeatable, name: $newProjectName, defaultName: projects.defaultProjectName(for: .repeatable)) { Task { if let project = try? await projects.createProject(module: .repeatable, name: newProjectName) { try? await store.link(projectID: project.id, to: locationID); try? store.seedProject(project, from: locationID); isCreatingProject = false } } } }
        .sheet(isPresented: $isPlanning) { RecapturePlannerView(locationID: locationID) }
        .onChange(of: selectedPhoto) { _, item in Task { if let data = try? await item?.loadTransferable(type: Data.self) { try? await store.addReferencePhoto(data: data, to: locationID) } } }
    }
}

struct CaptureCalendarView: View {
    @EnvironmentObject private var store: TripodLocationStore
    @EnvironmentObject private var projects: ProjectStore
    @State private var selectedDate = Date()
    var body: some View {
        List {
            DatePicker("Data", selection: $selectedDate, displayedComponents: .date).datePickerStyle(.graphical)
            let entries = store.snapshot.calendarEntries.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
            let captures = capturedSessions(on: selectedDate)
            if entries.isEmpty && captures.isEmpty { ContentUnavailableView("Nenhuma captura nesta data", systemImage: "calendar") }
            ForEach(entries) { entry in
                if let location = store.snapshot.location(id: entry.locationID) { NavigationLink(value: location) { VStack(alignment: .leading) { Text(location.name); Text(entry.kind == .planned ? "Retorno planejado" : "Captura concluída").font(.caption).foregroundStyle(.secondary) } } }
            }
            ForEach(captures, id: \.id) { capture in
                NavigationLink(value: capture.location) {
                    VStack(alignment: .leading) { Text(capture.location.name); Text("Captura concluída · \(capture.date.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("Calendário")
        .navigationDestination(for: TripodLocation.self) { TripodLocationDetailView(locationID: $0.id) }
        .onAppear { store.reload() }
    }

    private func capturedSessions(on date: Date) -> [CalendarCaptureRow] {
        projects.projects.flatMap { project -> [CalendarCaptureRow] in
            guard let location = store.snapshot.location(forProjectID: project.id) else { return [] }
            return TimelapseSessionStore(project: project).sessionSummaries().compactMap { summary in
                guard Calendar.current.isDate(summary.session.createdAt, inSameDayAs: date) else { return nil }
                return CalendarCaptureRow(id: summary.id, location: location, date: summary.session.createdAt)
            }
        }.sorted { $0.date < $1.date }
    }
}

private struct CalendarCaptureRow: Identifiable {
    let id: UUID
    let location: TripodLocation
    let date: Date
}

struct RecapturePlannerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TripodLocationStore
    let locationID: UUID
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
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Salvar") { Task { let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) == true; notificationDenied = !granted; try? await store.schedule(locationID: locationID, projectID: nil, weeks: weeks, note: note.nilIfEmpty); if granted { dismiss() } } } } }
        }
    }
}

private extension String { var nilIfEmpty: String? { let v = trimmingCharacters(in: .whitespacesAndNewlines); return v.isEmpty ? nil : v } }

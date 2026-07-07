import SwiftUI

struct AppRootView: View {
    @StateObject private var projectStore = ProjectStore()
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ModuleSelectionView()
                .navigationDestination(for: CameraModule.self) { module in
                    ProjectListView(module: module, path: $path)
                }
                .navigationDestination(for: CameraProject.self) { project in
                    ModuleRuntimeView(project: project, path: $path)
                }
        }
        .environmentObject(projectStore)
    }
}

private struct ModuleSelectionView: View {
    var body: some View {
        List(CameraModule.allCases) { module in
            NavigationLink(value: module) {
                ModuleRow(module: module)
            }
        }
        .navigationTitle("Camerae")
    }
}

private struct ModuleRow: View {
    let module: CameraModule

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: module.systemImage)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(module.title)
                    .font(.headline)
                Text(module.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct ProjectListView: View {
    @EnvironmentObject private var projectStore: ProjectStore

    let module: CameraModule
    @Binding var path: NavigationPath

    @State private var isCreatingProject = false
    @State private var projectName = ""
    @State private var errorMessage: String?

    private var activeProjects: [CameraProject] {
        projectStore.activeProjects(for: module)
    }

    private var lastOpenedProject: CameraProject? {
        activeProjects.first
    }

    private var remainingActiveProjects: [CameraProject] {
        guard let lastOpenedProject else {
            return []
        }

        return activeProjects.filter { $0.id != lastOpenedProject.id }
    }

    private var archivedProjects: [CameraProject] {
        projectStore.archivedProjects(for: module)
    }

    var body: some View {
        List {
            if let lastOpenedProject {
                Section("Ultimo aberto") {
                    projectLink(lastOpenedProject, isHighlighted: true)
                }
            }

            if activeProjects.isEmpty {
                Section("Projetos") {
                    Text("Nenhum projeto ainda")
                        .foregroundStyle(.secondary)
                }
            } else if !remainingActiveProjects.isEmpty {
                Section("Projetos") {
                    ForEach(remainingActiveProjects) { project in
                        projectLink(project)
                    }
                }
            }

            if !archivedProjects.isEmpty {
                Section("Arquivados") {
                    ForEach(archivedProjects) { project in
                        NavigationLink(value: project) {
                            ProjectRow(project: project)
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                setArchived(project, false)
                            } label: {
                                Label("Restaurar", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.green)
                        }
                    }
                }
            }
        }
        .navigationTitle(module.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    projectName = ""
                    isCreatingProject = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Novo projeto")
            }
        }
        .sheet(isPresented: $isCreatingProject) {
            NewProjectSheet(
                module: module,
                name: $projectName,
                defaultName: projectStore.defaultProjectName(for: module),
                createAction: {
                    createProject(named: projectName)
                }
            )
        }
        .alert("Erro", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            projectStore.reload()
        }
    }

    private func createProject(named name: String) {
        do {
            let project = try projectStore.createProject(module: module, name: name)
            isCreatingProject = false
            path.append(project)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setArchived(_ project: CameraProject, _ isArchived: Bool) {
        do {
            try projectStore.setArchived(project, isArchived: isArchived)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func projectLink(_ project: CameraProject, isHighlighted: Bool = false) -> some View {
        NavigationLink(value: project) {
            ProjectRow(project: project, isHighlighted: isHighlighted)
        }
        .listRowBackground(isHighlighted ? Color.accentColor.opacity(0.12) : nil)
        .swipeActions(edge: .trailing) {
            Button {
                setArchived(project, true)
            } label: {
                Label("Arquivar", systemImage: "archivebox")
            }
            .tint(.orange)
        }
    }
}

private struct ProjectRow: View {
    let project: CameraProject
    var isHighlighted = false

    private var summary: ProjectRowSummary {
        ProjectRowSummary(project: project)
    }

    private var thumbnailURL: URL? {
        TimelapseSessionStore(project: project).firstReferenceFrameURL()
    }

    var body: some View {
        HStack(spacing: 12) {
            ReferenceThumbnail(imageURL: thumbnailURL, systemImage: project.module.systemImage)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .font(.headline)
                    if isHighlighted {
                        Image(systemName: "clock.fill")
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                    if project.isArchived {
                        Image(systemName: "archivebox")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(summary.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let detail = summary.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isHighlighted {
                    Text("Ultimo projeto aberto")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ProjectRowSummary {
    let project: CameraProject

    private var store: TimelapseSessionStore {
        TimelapseSessionStore(project: project)
    }

    var subtitle: String {
        if let lastOpenedAt = project.lastOpenedAt {
            return "Aberto \(lastOpenedAt.formatted(date: .abbreviated, time: .shortened))"
        }

        return "Criado \(project.createdAt.formatted(date: .abbreviated, time: .shortened))"
    }

    var detail: String? {
        guard project.module == .astrophotography,
              let latest = store.latestSessionSummaryWithFrames() else {
            return nil
        }

        var parts = ["\(latest.frameCount) frames"]
        parts.append(latest.isAstroProcessed ? "processado" : "nao processado")
        return parts.joined(separator: " · ")
    }
}

private struct NewProjectSheet: View {
    let module: CameraModule
    @Binding var name: String
    let defaultName: String
    let createAction: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(defaultName, text: $name)
                        .textInputAutocapitalization(.words)
                } footer: {
                    Text("Deixe vazio para usar: \(defaultName)")
                }
            }
            .navigationTitle("Novo projeto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Criar") {
                        createAction()
                    }
                }
            }
        }
    }
}

private struct ModuleRuntimeView: View {
    @EnvironmentObject private var projectStore: ProjectStore
    let project: CameraProject
    @Binding var path: NavigationPath

    var body: some View {
        Group {
            switch project.module {
            case .astrophotography:
                AstroProjectRuntimeView(project: project, path: $path)
            case .repeatable:
                RepeatableProjectRuntimeView(project: project) {
                    try TimelapseSessionStore(project: project).deleteProject()
                    path.removeLast()
                }
            }
        }
        .onAppear {
            projectStore.markOpened(project)
        }
    }
}

private struct AstroProjectRuntimeView: View {
    let project: CameraProject
    @Binding var path: NavigationPath

    @State private var mode = AstroProjectMode.loading
    private let store: TimelapseSessionStore

    init(project: CameraProject, path: Binding<NavigationPath>) {
        self.project = project
        _path = path
        store = TimelapseSessionStore(project: project)
    }

    var body: some View {
        Group {
            switch mode {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(project.name)
                    .navigationBarTitleDisplayMode(.inline)
            case .capture:
                CameraView(project: project) {
                    try store.deleteProject()
                    path.removeLast()
                }
            case .processing(let session):
                AstroProcessingView(session: session) {
                    mode = .capture
                } onDeleteProject: {
                    try store.deleteProject()
                    path.removeLast()
                }
            }
        }
        .onAppear {
            guard mode == .loading else { return }
            if let session = store.latestSessionWithFrames() {
                mode = .processing(session)
            } else {
                mode = .capture
            }
        }
    }
}

private enum AstroProjectMode: Equatable {
    case loading
    case capture
    case processing(TimelapseSession)
}

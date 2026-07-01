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

    private var projects: [CameraProject] {
        projectStore.projects(for: module)
    }

    var body: some View {
        List {
            Section("Projetos") {
                if projects.isEmpty {
                    Text("Nenhum projeto ainda")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(projects) { project in
                        NavigationLink(value: project) {
                            ProjectRow(project: project)
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
}

private struct ProjectRow: View {
    let project: CameraProject

    private var thumbnailURL: URL? {
        TimelapseSessionStore(project: project).firstReferenceFrameURL()
    }

    var body: some View {
        HStack(spacing: 12) {
            ReferenceThumbnail(imageURL: thumbnailURL, systemImage: project.module.systemImage)

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                Text(project.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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
    let project: CameraProject
    @Binding var path: NavigationPath

    var body: some View {
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

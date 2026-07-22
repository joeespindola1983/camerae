import SwiftUI

struct AppRootView: View {
    @StateObject private var projectStore = ProjectStore()
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            EntryHomeView(path: $path)
                .navigationDestination(for: CameraModule.self) { module in
                    if module == .repeatable || module == .astrophotography {
                        ProjectListScreen(module: module, path: $path)
                    } else {
                        ProjectListView(module: module, path: $path)
                    }
                }
                .navigationDestination(for: CameraProject.self) { project in
                    ModuleRuntimeView(project: project, path: $path)
                }
        }
        .environmentObject(projectStore)
        .onAppear {
            AppOrientationLock.shared.restorePortrait()
        }
    }
}

private struct LegacyModuleSelectionView: View {
    @EnvironmentObject private var projectStore: ProjectStore
    @Binding var path: NavigationPath

    @State private var creatingModule: CameraModule?
    @State private var projectName = ""
    @State private var errorMessage: String?

    private var lastOpenedProject: CameraProject? {
        projectStore.projects.first { !$0.isArchived }
    }

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height

            ZStack {
                Image(isLandscape ? "HomeBackgroundLandscape" : "HomeBackgroundPortrait")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [.black.opacity(0.18), .clear, .black.opacity(0.62)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: isLandscape ? 28 : 18) {
                        Image("CameraeLogoWhite")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: isLandscape ? 510 : 280)
                            .accessibilityLabel("Camerae")

                        moduleCards(isLandscape: isLandscape)

                        if let lastOpenedProject {
                            lastProjectCard(lastOpenedProject, isLandscape: isLandscape)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, isLandscape ? 42 : 20)
                    .padding(.top, isLandscape ? 18 : 28)
                    .padding(.bottom, 28)
                    .frame(minHeight: proxy.size.height, alignment: .center)
                }
                .scrollIndicators(.hidden)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .sheet(item: $creatingModule) { module in
            NewProjectSheet(
                module: module,
                name: $projectName,
                defaultName: projectStore.defaultProjectName(for: module),
                createAction: {
                    createProject(module: module, named: projectName)
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

    @ViewBuilder
    private func moduleCards(isLandscape: Bool) -> some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: isLandscape ? 28 : 12),
                count: isLandscape ? 3 : 2
            ),
            alignment: .center,
            spacing: isLandscape ? 28 : 12
        ) {
            HomeModuleCard(
                module: .repeatable,
                projectCount: projectStore.projects(for: .repeatable).count,
                isCompact: !isLandscape,
                createAction: { startCreating(.repeatable) },
                projectsAction: { path.append(CameraModule.repeatable) }
            )

            HomeModuleCard(
                module: .astrophotography,
                projectCount: projectStore.projects(for: .astrophotography).count,
                isCompact: !isLandscape,
                createAction: { startCreating(.astrophotography) },
                projectsAction: { path.append(CameraModule.astrophotography) }
            )

            HomeModuleCard(
                module: .edit,
                projectCount: projectStore.projects(for: .edit).count,
                isCompact: !isLandscape,
                createAction: { startCreating(.edit) },
                projectsAction: { path.append(CameraModule.edit) }
            )
        }
        .frame(maxWidth: isLandscape ? 980 : 380)
    }

    private func lastProjectCard(_ project: CameraProject, isLandscape: Bool) -> some View {
        let summary = ProjectRowSummary(project: project)
        let thumbnailURL = project.referenceFrameURL

        return Button {
            path.append(project)
        } label: {
            HStack(spacing: 14) {
                ReferenceThumbnail(imageURL: thumbnailURL, systemImage: project.module.systemImage)

                VStack(alignment: .leading, spacing: 4) {
                    Text("ULTIMO PROJETO")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.6)
                        .foregroundStyle(.white.opacity(0.62))
                    Text(project.name)
                        .font(isLandscape ? .title3 : .headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(summary.detail ?? summary.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.right")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.08), in: Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.24), lineWidth: 1)
                    }
            }
            .padding(16)
            .frame(maxWidth: isLandscape ? 700 : 360)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abrir ultimo projeto, \(project.name)")
    }

    private func startCreating(_ module: CameraModule) {
        projectName = ""
        creatingModule = module
    }

    private func createProject(module: CameraModule, named name: String) {
        Task {
            do {
                let project = try await projectStore.createProject(module: module, name: name)
                creatingModule = nil
                path.append(project)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct HomeModuleCard: View {
    let module: CameraModule
    let projectCount: Int
    let isCompact: Bool
    let createAction: () -> Void
    let projectsAction: () -> Void

    private var accent: Color { module.designTheme.accent }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: module.systemImage)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(accent)
                .frame(height: 44)

            Text(homeTitle)
                .font(.system(size: 18, weight: .medium))
                .tracking(5)
                .foregroundStyle(.white)

            Rectangle()
                .fill(accent)
                .frame(width: 36, height: 1)

            Button(action: createAction) {
                Text("+ Criar")
                    .font(.headline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
            .frame(height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("Criar projeto \(module.title)")

            Button(action: projectsAction) {
                Text("Projetos (\(projectCount))")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.86))
            .frame(height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("Projetos \(module.title), \(projectCount)")
        }
        .padding(.horizontal, isCompact ? 10 : 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    private var homeTitle: String {
        switch module {
        case .astrophotography: return "ASTRO"
        case .repeatable: return "REPEATABLE"
        case .edit: return "EDIT"
        }
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
        .cameraeTheme(module.designTheme)
    }

    private func createProject(named name: String) {
        Task {
            do {
                let project = try await projectStore.createProject(module: module, name: name)
                isCreatingProject = false
                path.append(project)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func setArchived(_ project: CameraProject, _ isArchived: Bool) {
        Task {
            do {
                try await projectStore.setArchived(project, isArchived: isArchived)
            } catch {
                errorMessage = error.localizedDescription
            }
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
        project.referenceFrameURL
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

struct ProjectRowSummary {
    let project: CameraProject

    var subtitle: String {
        if let lastOpenedAt = project.lastOpenedAt {
            return CameraeL10n.openedAt(lastOpenedAt.formatted(date: .abbreviated, time: .shortened))
        }

        return CameraeL10n.createdAt(project.createdAt.formatted(date: .abbreviated, time: .shortened))
    }

    var detail: String? {
        guard let summary = project.summary else { return nil }
        if project.module == .edit {
            return CameraeL10n.editProjectDetail(clipCount: summary.mediaCount) + storageSuffix(summary.totalKnownBytes)
        }
        return CameraeL10n.captureProjectDetail(
            sessionCount: summary.sessionCount,
            frameCount: summary.mediaCount
        ) + storageSuffix(summary.totalKnownBytes)
    }

    private func storageSuffix(_ bytes: UInt64?) -> String {
        guard let bytes else { return "" }
        let formatted = ByteCountFormatter.string(
            fromByteCount: Int64(clamping: bytes),
            countStyle: .file
        )
        return " · \(formatted)"
    }
}

struct NewProjectSheet: View {
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
            case .edit:
                EditProjectRuntimeView(project: project)
            }
        }
        .onAppear {
            Task {
                await projectStore.markOpened(project)
            }
        }
    }
}

struct AstroProjectRuntimeView: View {
    let project: CameraProject
    @Binding var path: NavigationPath

    @State private var mode = AstroProjectMode.list
    @State private var sessions: [TimelapseSessionSummary] = []
    @State private var errorMessage: String?
    private let store: TimelapseSessionStore

    init(project: CameraProject, path: Binding<NavigationPath>) {
        self.project = project
        _path = path
        store = TimelapseSessionStore(project: project)
    }

    var body: some View {
        Group {
            switch mode {
            case .list:
                sessionList
            case .capture:
                CameraView(
                    project: project,
                    onDeleteProject: deleteProject,
                    onClose: {
                        reloadSessions()
                        mode = .list
                    },
                    onCompletedSession: { session in
                        reloadSessions()
                        mode = .processing(session)
                    }
                )
            case .processing(let session):
                AstroProcessingView(session: session) {
                    reloadSessions()
                    mode = .list
                } onDeleteProject: {
                    deleteProject()
                }
            }
        }
        .onAppear {
            reloadSessions()
        }
        .alert("Erro", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var sessionList: some View {
        List {
            Section {
                Button {
                    mode = .capture
                } label: {
                    Label("Criar timelapse Astro", systemImage: "camera.viewfinder")
                }
            }

            Section("Timelapses") {
                if sessions.isEmpty {
                    Text("Nenhum timelapse ainda")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessions) { summary in
                            RepeatableSessionRow(
                                summary: summary,
                                isRendering: false,
                                isBusy: false,
                                showsActions: false,
                                renderAction: {},
                                shareAction: {}
                            )
                        .onTapGesture {
                            mode = .processing(summary.session)
                        }
                        .accessibilityAddTraits(.isButton)
                        .swipeActions {
                            Button(role: .destructive) {
                                deleteSession(summary.session)
                            } label: {
                                Label("Excluir captura", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive, action: deleteProject) {
                    Label("Excluir projeto", systemImage: "trash")
                }
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func reloadSessions() {
        Task {
            do {
                sessions = try await store.sessionSummariesFromCatalog()
                    .filter { $0.frameCount > 0 }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteSession(_ session: TimelapseSession) {
        do {
            try store.deleteSession(session)
            reloadSessions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteProject() {
        do {
            try store.deleteProject()
            path.removeLast()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum AstroProjectMode: Equatable {
    case list
    case capture
    case processing(TimelapseSession)
}

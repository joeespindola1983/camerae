import SwiftUI

enum CameraeNextProjectCatalogFilter: String, CaseIterable, Identifiable, Sendable {
    case recent
    case inProgress
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "Recentes"
        case .inProgress: "Em andamento"
        case .completed: "Concluídos"
        }
    }

    var systemImage: String {
        switch self {
        case .recent: "clock"
        case .inProgress: "circle.dotted"
        case .completed: "checkmark.circle"
        }
    }
}

struct CameraeNextProjectCatalogModel: Equatable {
    let projects: [CameraProject]
    let module: CameraModule
    let filter: CameraeNextProjectCatalogFilter

    private var activeProjects: [CameraProject] {
        projects
            .filter { $0.module == module && !$0.isArchived }
            .sorted { lhs, rhs in
                let lhsDate = lhs.lastOpenedAt ?? lhs.updatedAt
                let rhsDate = rhs.lastOpenedAt ?? rhs.updatedAt
                if lhsDate == rhsDate { return lhs.name < rhs.name }
                return lhsDate > rhsDate
            }
    }

    var featuredProject: CameraProject? { activeProjects.first }
    var projectCount: Int { activeProjects.count }

    var remainingProjects: [CameraProject] {
        let remaining = Array(activeProjects.dropFirst())
        switch filter {
        case .recent:
            return remaining
        case .inProgress:
            return remaining.filter { ($0.summary?.mediaCount ?? 0) == 0 }
        case .completed:
            return remaining.filter { ($0.summary?.mediaCount ?? 0) > 0 }
        }
    }
}

enum CameraeNextTemporaryProjectPolicy {
    static func shouldOfferRemoval(hasCapturedMedia: Bool) -> Bool {
        !hasCapturedMedia
    }
}

struct CameraeNextProjectCatalogLayout: Equatable {
    let horizontalContentInset: CGFloat

    init(module: CameraModule) {
        switch module {
        case .repeatable, .astrophotography, .edit:
            horizontalContentInset = 16
        }
    }

    func contentWidth(containerWidth: CGFloat) -> CGFloat {
        max(0, containerWidth - (horizontalContentInset * 2))
    }
}

struct CameraeNextProjectCatalogView: View {
    @EnvironmentObject private var projectStore: ProjectStore

    let module: CameraModule
    @Binding var path: NavigationPath

    @State private var filter = CameraeNextProjectCatalogFilter.recent
    @State private var isCreatingProject = false
    @State private var projectName = ""
    @State private var errorMessage: String?
    @State private var pendingTemporaryProject: CameraeNextPendingTemporaryProject?
    @State private var emptyProjectToRemove: CameraProject?

    private var theme: ProjectListTheme { .init(module: module) }
    private var layout: CameraeNextProjectCatalogLayout { .init(module: module) }
    private var catalog: CameraeNextProjectCatalogModel {
        .init(projects: projectStore.projects, module: module, filter: filter)
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            if theme.showsStars {
                ProjectListStarField(color: theme.text)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            Circle()
                .fill(theme.accent.opacity(theme.showsStars ? 0.16 : 0.12))
                .frame(width: 460, height: 300)
                .blur(radius: 42)
                .offset(y: -420)
                .allowsHitTesting(false)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if let featured = catalog.featuredProject {
                        NavigationLink(value: featured) {
                            ProjectListHeroCard(project: featured, theme: theme)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 12)
                    } else {
                        ProjectListEmptyHero(theme: theme, createAction: beginCreatingProject)
                            .padding(.top, 12)
                    }

                    HStack {
                        Text("PROJETOS")
                            .tracking(1.6)
                        Spacer()
                        Text("\(catalog.projectCount)")
                            .foregroundStyle(theme.accent)
                    }
                    .font(.custom("DMMono-Regular", size: 10, relativeTo: .caption2))
                    .foregroundStyle(theme.muted)
                    .frame(height: 28)
                    .padding(.top, 20)

                    filterBar
                        .padding(.top, 4)

                    if catalog.remainingProjects.isEmpty {
                        emptyFilteredState
                            .padding(.top, 26)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(catalog.remainingProjects) { project in
                                NavigationLink(value: project) {
                                    ProjectListRow(project: project, theme: theme)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button {
                                        setArchived(project, true)
                                    } label: {
                                        Label("Arquivar", systemImage: "archivebox")
                                    }
                                    .tint(theme.accent)
                                }
                            }
                        }
                        .padding(.top, 10)
                    }

                    Text(theme.caption)
                        .font(.custom("DMMono-Regular", size: 8, relativeTo: .caption2))
                        .tracking(1.44)
                        .foregroundStyle(theme.muted)
                        .padding(.top, 28)
                        .padding(.bottom, 18)
                }
            }
            .frame(width: layout.contentWidth(containerWidth: UIScreen.main.bounds.width))
            .scrollIndicators(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.background.opacity(0.96), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Label(theme.title, systemImage: theme.systemImage)
                    .font(.custom("Outfit-SemiBold", size: 24, relativeTo: .title2))
                    .foregroundStyle(theme.text)
                    .labelStyle(ProjectListTitleLabelStyle(theme: theme))
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Filtrar projetos", selection: $filter) {
                        ForEach(CameraeNextProjectCatalogFilter.allCases) { option in
                            Label(option.title, systemImage: option.systemImage).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .accessibilityLabel("Filtrar projetos")

                Button(action: beginCreatingProject) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Novo projeto \(theme.title)")
            }
        }
        .tint(theme.accent)
        .preferredColorScheme(theme.colorScheme)
        .sheet(isPresented: $isCreatingProject) {
            CameraeNextNewProjectSheet(
                module: module,
                name: $projectName,
                defaultName: projectStore.defaultProjectName(for: module),
                createAction: createProject
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
        .alert("Projeto temporário vazio", isPresented: Binding(
            get: { emptyProjectToRemove != nil },
            set: { if !$0 { emptyProjectToRemove = nil } }
        )) {
            Button("Remover projeto", role: .destructive, action: removeEmptyTemporaryProject)
        } message: {
            Text("Nenhuma captura foi criada. Este projeto temporário será removido para manter sua lista organizada.")
        }
        .onAppear {
            AppOrientationLock.shared.restorePortrait()
            projectStore.reload()
            evaluatePendingTemporaryProject()
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(CameraeNextProjectCatalogFilter.allCases) { option in
                Button(option.title) { filter = option }
                    .font(.custom("Outfit-Regular", size: 10, relativeTo: .caption2))
                    .foregroundStyle(filter == option ? .white : theme.text)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(filter == option ? theme.accent : theme.surface, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyFilteredState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack")
                .font(.title2)
            Text(catalog.projectCount == 0 ? "Nenhum projeto ainda" : "Nenhum projeto neste filtro")
                .font(.custom("Outfit-Medium", size: 15, relativeTo: .subheadline))
        }
        .foregroundStyle(theme.muted)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func beginCreatingProject() {
        projectName = ""
        isCreatingProject = true
    }

    private func createProject() {
        Task {
            do {
                let project = try await projectStore.createProject(module: module, name: projectName)
                isCreatingProject = false
                pendingTemporaryProject = .init(project: project, returnPathCount: path.count)
                path.append(project)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func evaluatePendingTemporaryProject() {
        guard let pendingTemporaryProject,
              path.count == pendingTemporaryProject.returnPathCount else { return }

        Task {
            do {
                let sessions = try await TimelapseSessionStore(project: pendingTemporaryProject.project)
                    .sessionSummariesFromCatalog()
                let hasCapturedMedia = sessions.contains {
                    $0.frameCount > 0 || $0.videoURL != nil || $0.videoClipURL != nil
                }
                if CameraeNextTemporaryProjectPolicy.shouldOfferRemoval(hasCapturedMedia: hasCapturedMedia) {
                    emptyProjectToRemove = pendingTemporaryProject.project
                } else {
                    self.pendingTemporaryProject = nil
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func removeEmptyTemporaryProject() {
        guard let project = emptyProjectToRemove else { return }
        emptyProjectToRemove = nil
        Task {
            do {
                try await projectStore.deleteProject(project)
                pendingTemporaryProject = nil
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
}

private struct CameraeNextPendingTemporaryProject {
    let project: CameraProject
    let returnPathCount: Int
}

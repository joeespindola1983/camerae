import SwiftUI

enum ProjectCatalogAction: Hashable, Sendable {
    case archive
    case unarchive
    case delete
}

enum ProjectCatalogActionPolicy {
    static func actions(for project: CameraProject) -> [ProjectCatalogAction] {
        [project.isArchived ? .unarchive : .archive, .delete]
    }
}

enum CameraeNextProjectCatalogFilter: String, CaseIterable, Identifiable, Sendable {
    case recent
    case withCaptures
    case archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: CameraeL10n.recent
        case .withCaptures: CameraeL10n.withCaptures
        case .archived: CameraeL10n.archived
        }
    }

    var systemImage: String {
        switch self {
        case .recent: "clock"
        case .withCaptures: "camera.fill"
        case .archived: "archivebox"
        }
    }
}

enum CameraeNextProjectCatalogSort: String, CaseIterable, Identifiable, Sendable {
    case lastActivity
    case createdNewest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lastActivity: CameraeL10n.sortLastActivity
        case .createdNewest: CameraeL10n.sortCreatedNewest
        }
    }

    var systemImage: String {
        switch self {
        case .lastActivity: "clock.arrow.circlepath"
        case .createdNewest: "calendar.badge.clock"
        }
    }
}

struct CameraeNextProjectCatalogModel: Equatable {
    let projects: [CameraProject]
    let module: CameraModule
    let filter: CameraeNextProjectCatalogFilter
    var sort: CameraeNextProjectCatalogSort = .lastActivity

    private var moduleProjects: [CameraProject] {
        projects
            .filter { $0.module == module }
            .sorted { lhs, rhs in
                let lhsDate: Date
                let rhsDate: Date
                switch sort {
                case .lastActivity:
                    lhsDate = lhs.lastOpenedAt ?? lhs.updatedAt
                    rhsDate = rhs.lastOpenedAt ?? rhs.updatedAt
                case .createdNewest:
                    lhsDate = lhs.createdAt
                    rhsDate = rhs.createdAt
                }
                if lhsDate == rhsDate { return lhs.name < rhs.name }
                return lhsDate > rhsDate
            }
    }

    var visibleProjects: [CameraProject] {
        switch filter {
        case .recent:
            return moduleProjects.filter { !$0.isArchived }
        case .withCaptures:
            return moduleProjects.filter { !$0.isArchived && ($0.summary?.mediaCount ?? 0) > 0 }
        case .archived:
            return moduleProjects.filter(\.isArchived)
        }
    }

    var featuredProject: CameraProject? { visibleProjects.first }
    var projectCount: Int { visibleProjects.count }
    var remainingProjects: [CameraProject] { Array(visibleProjects.dropFirst()) }
}

enum CameraeNextTemporaryProjectPolicy {
    static func shouldAutomaticallyDiscard(hasDurableContent: Bool) -> Bool {
        !hasDurableContent
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
    @State private var sort = CameraeNextProjectCatalogSort.lastActivity
    @State private var isCreatingProject = false
    @State private var projectName = ""
    @State private var errorMessage: String?
    @State private var pendingTemporaryProject: CameraeNextPendingTemporaryProject?
    @State private var projectForStorageManagement: CameraProject?
    @State private var projectToDelete: CameraProject?

    private var theme: ProjectListTheme { .init(module: module) }
    private var layout: CameraeNextProjectCatalogLayout { .init(module: module) }
    private var catalog: CameraeNextProjectCatalogModel {
        .init(projects: projectStore.projects, module: module, filter: filter, sort: sort)
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
                        ZStack(alignment: .topTrailing) {
                            NavigationLink(value: featured) {
                                ProjectListHeroCard(project: featured, theme: theme)
                            }
                            .buttonStyle(.plain)

                            projectActionsMenu(featured)
                                .padding(12)
                        }
                        .padding(.top, 12)
                    } else {
                        ProjectListEmptyHero(theme: theme, createAction: beginCreatingProject)
                            .padding(.top, 12)
                    }

                    HStack {
                        Text(CameraeL10n.projectsSection)
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
                                ZStack(alignment: .trailing) {
                                    NavigationLink(value: project) {
                                        ProjectListRow(project: project, theme: theme)
                                    }
                                    .buttonStyle(.plain)

                                    projectActionsMenu(project)
                                        .padding(.trailing, 12)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button {
                                        projectForStorageManagement = project
                                    } label: {
                                        Label("Armazenamento", systemImage: "externaldrive")
                                    }
                                    .tint(theme.accent)

                                    Button(role: .destructive) {
                                        projectToDelete = project
                                    } label: {
                                        Label("Excluir", systemImage: "trash")
                                    }

                                    Button {
                                        setArchived(project, !project.isArchived)
                                    } label: {
                                        Label(
                                            project.isArchived ? CameraeL10n.unarchive : CameraeL10n.archive,
                                            systemImage: project.isArchived ? "archivebox.fill" : "archivebox"
                                        )
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
                    .foregroundStyle(theme.titleText)
                    .labelStyle(ProjectListTitleLabelStyle(theme: theme))
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker(CameraeL10n.filterProjects, selection: $filter) {
                        ForEach(CameraeNextProjectCatalogFilter.allCases) { option in
                            Label(option.title, systemImage: option.systemImage).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .accessibilityLabel(CameraeL10n.filterProjects)

                Menu {
                    Picker(CameraeL10n.sortProjects, selection: $sort) {
                        ForEach(CameraeNextProjectCatalogSort.allCases) { option in
                            Label(option.title, systemImage: option.systemImage).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel(CameraeL10n.sortProjects)

                Button(action: beginCreatingProject) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(CameraeL10n.newProject(theme.title))
                .accessibilityIdentifier(CameraeAccessibility.newProject(module))
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
        .sheet(item: $projectForStorageManagement) { project in
            CameraeNextProjectStorageView(project: project) {
                projectForStorageManagement = nil
                projectStore.reload()
            } onRequestProjectDeletion: {
                projectForStorageManagement = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    projectToDelete = project
                }
            }
        }
        .alert("Excluir “\(projectToDelete?.name ?? "")”?", isPresented: Binding(
            get: { projectToDelete != nil },
            set: { if !$0 { projectToDelete = nil } }
        )) {
            Button("Excluir projeto permanentemente", role: .destructive, action: deletePendingProject)
            Button(CameraeL10n.cancel, role: .cancel) { projectToDelete = nil }
        } message: {
            Text("A referência, os frames, fotos, vídeos e arquivos exportados serão removidos permanentemente.")
        }
        .alert(CameraeL10n.error, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(CameraeL10n.okay, role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
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
            Text(catalog.projectCount == 0 ? CameraeL10n.noProjectsYet : CameraeL10n.noProjectsInFilter)
                .font(.custom("Outfit-Medium", size: 15, relativeTo: .subheadline))
        }
        .foregroundStyle(theme.muted)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func projectActionsMenu(_ project: CameraProject) -> some View {
        Menu {
            Button("Gerenciar armazenamento", systemImage: "externaldrive") {
                projectForStorageManagement = project
            }
            Button {
                setArchived(project, !project.isArchived)
            } label: {
                Label(
                    project.isArchived ? CameraeL10n.unarchive : CameraeL10n.archive,
                    systemImage: project.isArchived ? "archivebox.fill" : "archivebox"
                )
            }
            Button("Excluir projeto", systemImage: "trash", role: .destructive) {
                projectToDelete = project
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.text)
                .frame(width: 44, height: 44)
                .background(theme.surface, in: Circle())
        }
        .accessibilityLabel("Ações do projeto \(project.name)")
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
                let hasDurableContent = try await TimelapseSessionStore(
                    project: pendingTemporaryProject.project
                ).hasDurableProjectContent()
                if CameraeNextTemporaryProjectPolicy.shouldAutomaticallyDiscard(
                    hasDurableContent: hasDurableContent
                ) {
                    try await projectStore.deleteProject(pendingTemporaryProject.project)
                }
                self.pendingTemporaryProject = nil
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

    private func deletePendingProject() {
        guard let project = projectToDelete else { return }
        projectToDelete = nil
        Task {
            do {
                try await projectStore.deleteProject(project)
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

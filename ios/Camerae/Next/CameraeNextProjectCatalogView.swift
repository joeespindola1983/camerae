import CameraeCore
import SwiftUI

enum ProjectCatalogAction: Hashable, Sendable {
    case move
    case archive
    case unarchive
    case delete
}

enum ProjectCatalogActionPolicy {
    static func actions(for project: CameraProject) -> [ProjectCatalogAction] {
        let organizationActions: [ProjectCatalogAction] = project.module == .repeatable ? [.move] : []
        return organizationActions + [project.isArchived ? .unarchive : .archive, .delete]
    }
}

enum ProjectOrganizationAction: Hashable, Sendable {
    case rename
    case archive
    case unarchive
    case deletePreservingProjects
}

enum ProjectOrganizationActionPolicy {
    static func actions(for node: ProjectOrganizationNode) -> [ProjectOrganizationAction] {
        [.rename, node.isArchived ? .unarchive : .archive, .deletePreservingProjects]
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

enum CameraeNextProjectCatalogCapability: Hashable, Sendable {
    case filter
    case sort
    case createGroup
    case createProject
}

enum CameraeNextProjectCatalogCapabilityPolicy {
    static func actions(for module: CameraModule) -> [CameraeNextProjectCatalogCapability] {
        switch module {
        case .repeatable:
            [.filter, .sort, .createGroup, .createProject]
        case .astrophotography, .edit:
            [.filter, .sort, .createProject]
        }
    }
}

enum CameraeNextCatalogEmptyStateScope: Equatable, Sendable {
    case projects
    case groups
}

struct CameraeNextCatalogEmptyStatePresentation: Equatable, Sendable {
    let title: String
    let message: String
    let action: CameraeNextProjectCatalogCapability?

    init(
        scope: CameraeNextCatalogEmptyStateScope,
        filter: CameraeNextProjectCatalogFilter
    ) {
        switch scope {
        case .projects:
            title = filter == .recent ? CameraeL10n.noProjectsYet : CameraeL10n.noProjectsInFilter
            message = CameraeL10n.startFirstProject
            action = filter == .recent ? .createProject : nil
        case .groups:
            title = filter == .archived
                ? CameraeL10n.organizationNoArchivedGroups
                : CameraeL10n.organizationOrganizeLocations
            message = CameraeL10n.organizationHelper
            action = filter == .archived ? nil : .createGroup
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

struct CameraeNextProjectCatalogContentPolicy: Equatable {
    let hasGroups: Bool
    let hasUngroupedProjects: Bool

    var showsFirstProjectOnboarding: Bool { !hasGroups && !hasUngroupedProjects }
    var showsProjectSection: Bool { !hasGroups || hasUngroupedProjects }
    var showsProjectFilters: Bool { hasUngroupedProjects }
}

struct CameraeNextProjectOrganizationModel: Equatable {
    let projects: [CameraProject]
    let module: CameraModule
    let organization: ProjectOrganizationSnapshot
    let filter: CameraeNextProjectCatalogFilter
    var sort: CameraeNextProjectCatalogSort = .lastActivity

    private var moduleProjects: [CameraProject] {
        projects
            .filter { $0.module == module }
            .sorted(by: projectSort)
    }

    private var visibleProjects: [CameraProject] {
        moduleProjects
            .filter { project in
                switch filter {
                case .recent:
                    !project.isArchived
                case .withCaptures:
                    !project.isArchived && (project.summary?.mediaCount ?? 0) > 0
                case .archived:
                    project.isArchived
                }
            }
    }

    private var visibleNodes: [ProjectOrganizationNode] {
        organization.nodes
            .filter { $0.module == module.coreValue }
            .filter {
                filter == .archived
                    ? isEffectivelyArchived($0)
                    : !isEffectivelyArchived($0)
            }
            .sorted(by: nodeSort)
    }

    var rootNodes: [ProjectOrganizationNode] {
        visibleNodes.filter { $0.parentID == nil }
    }

    var hasGroups: Bool {
        organization.nodes.contains { $0.module == module.coreValue }
    }

    var hasUngroupedProjects: Bool {
        moduleProjects.contains { organization.nodeID(for: $0.id) == nil }
    }

    var ungroupedProjects: [CameraProject] {
        visibleProjects.filter { organization.nodeID(for: $0.id) == nil }
    }

    func childNodes(of parentID: UUID) -> [ProjectOrganizationNode] {
        visibleNodes.filter { $0.parentID == parentID }
    }

    func directProjects(in nodeID: UUID) -> [CameraProject] {
        let assigned = moduleProjects.filter { organization.nodeID(for: $0.id) == nodeID }
        guard filter == .archived,
              let node = organization.nodes.first(where: { $0.id == nodeID }),
              isEffectivelyArchived(node) else {
            return assigned.filter { project in
                switch filter {
                case .recent:
                    !project.isArchived
                case .withCaptures:
                    !project.isArchived && (project.summary?.mediaCount ?? 0) > 0
                case .archived:
                    project.isArchived
                }
            }
        }
        return assigned
    }

    func descendantProjects(in nodeID: UUID) -> [CameraProject] {
        directProjects(in: nodeID) + childNodes(of: nodeID).flatMap { directProjects(in: $0.id) }
    }

    func mosaicProjects(in nodeID: UUID) -> [CameraProject] {
        Array(descendantProjects(in: nodeID).prefix(4))
    }

    func overflowCount(in nodeID: UUID) -> Int {
        max(0, descendantProjects(in: nodeID).count - 4)
    }

    private func projectSort(_ lhs: CameraProject, _ rhs: CameraProject) -> Bool {
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
        return lhsDate == rhsDate ? lhs.name < rhs.name : lhsDate > rhsDate
    }

    private func nodeSort(_ lhs: ProjectOrganizationNode, _ rhs: ProjectOrganizationNode) -> Bool {
        let lhsDate = sort == .createdNewest ? lhs.createdAt : lhs.updatedAt
        let rhsDate = sort == .createdNewest ? rhs.createdAt : rhs.updatedAt
        return lhsDate == rhsDate ? lhs.name < rhs.name : lhsDate > rhsDate
    }

    private func isEffectivelyArchived(_ node: ProjectOrganizationNode) -> Bool {
        guard let parentID = node.parentID,
              let parent = organization.nodes.first(where: { $0.id == parentID }) else {
            return node.isArchived
        }
        return node.isArchived || parent.isArchived
    }
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
    @State private var isCreatingGroup = false
    @State private var groupName = ""
    @State private var errorMessage: String?
    @State private var pendingTemporaryProject: CameraeNextPendingTemporaryProject?
    @State private var projectForStorageManagement: CameraProject?
    @State private var projectToMove: CameraProject?
    @State private var projectToDelete: CameraProject?
    @State private var groupToRename: ProjectOrganizationNode?
    @State private var groupToDelete: ProjectOrganizationNode?

    private var theme: ProjectListTheme { .init(module: module) }
    private var layout: CameraeNextProjectCatalogLayout { .init(module: module) }
    private var catalogCapabilities: Set<CameraeNextProjectCatalogCapability> {
        Set(CameraeNextProjectCatalogCapabilityPolicy.actions(for: module))
    }
    private var organizationModel: CameraeNextProjectOrganizationModel {
        .init(
            projects: projectStore.projects,
            module: module,
            organization: projectStore.organization,
            filter: filter,
            sort: sort
        )
    }
    private var catalog: CameraeNextProjectCatalogModel {
        .init(
            projects: module == .repeatable ? organizationModel.ungroupedProjects : projectStore.projects,
            module: module,
            filter: filter,
            sort: sort
        )
    }
    private var contentPolicy: CameraeNextProjectCatalogContentPolicy {
        if module == .repeatable {
            return .init(
                hasGroups: organizationModel.hasGroups,
                hasUngroupedProjects: organizationModel.hasUngroupedProjects
            )
        }
        return .init(
            hasGroups: false,
            hasUngroupedProjects: projectStore.projects.contains { $0.module == module }
        )
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
                    if module == .repeatable {
                        organizationSection
                            .padding(.top, 12)
                            .padding(.bottom, 18)
                    }

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
                    } else if contentPolicy.showsFirstProjectOnboarding {
                        ProjectListEmptyHero(theme: theme, createAction: beginCreatingProject)
                            .padding(.top, 12)
                    }

                    if contentPolicy.showsProjectSection {
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

                        if contentPolicy.showsProjectFilters {
                            filterBar
                                .padding(.top, 4)
                        }

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
                if catalogCapabilities.contains(.filter) {
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
                }

                if catalogCapabilities.contains(.sort) {
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
                }

                if catalogCapabilities.contains(.createGroup) {
                    Menu {
                        Button(CameraeL10n.organizationNewGroup, systemImage: "folder.badge.plus", action: beginCreatingGroup)
                        Button(CameraeL10n.newProject, systemImage: "plus.rectangle", action: beginCreatingProject)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel(CameraeL10n.organizationCreateGroupOrProject)
                } else if catalogCapabilities.contains(.createProject) {
                    Button(action: beginCreatingProject) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel(CameraeL10n.newProject(theme.title))
                    .accessibilityIdentifier(CameraeAccessibility.newProject(module))
                }
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
        .sheet(isPresented: $isCreatingGroup) {
            CameraeNextOrganizationEditorSheet(
                title: CameraeL10n.organizationNewGroup,
                kind: CameraeL10n.organizationGroup,
                name: $groupName,
                saveTitle: CameraeL10n.create,
                save: createGroup
            )
        }
        .sheet(item: $groupToRename) { selected in
            CameraeNextOrganizationRenameHost(node: selected, rename: renameGroup)
        }
        .sheet(item: $projectToMove) { project in
            CameraeNextProjectMoveSheet(project: project, organization: projectStore.organization) { destination in
                move(project, to: destination)
            }
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
        .alert("Excluir “\(groupToDelete?.name ?? "")”?", isPresented: Binding(
            get: { groupToDelete != nil },
            set: { if !$0 { groupToDelete = nil } }
        )) {
            Button(CameraeL10n.organizationDelete, role: .destructive, action: deletePendingGroup)
            Button(CameraeL10n.cancel, role: .cancel) { groupToDelete = nil }
        } message: {
            Text(CameraeL10n.organizationDeletePreservingMessage)
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

    private var organizationSection: some View {
        let emptyPresentation = CameraeNextCatalogEmptyStatePresentation(
            scope: .groups,
            filter: filter
        )

        return VStack(spacing: 10) {
            HStack {
                Text(
                    filter == .archived
                        ? CameraeL10n.organizationArchivedGroups
                        : CameraeL10n.organizationGroups
                )
                    .tracking(1.6)
                Spacer()
                Text("\(organizationModel.rootNodes.count)")
                    .foregroundStyle(theme.accent)
            }
            .font(.custom("DMMono-Regular", size: 10, relativeTo: .caption2))
            .foregroundStyle(theme.muted)
            .frame(height: 28)

            if organizationModel.rootNodes.isEmpty {
                Button(action: beginCreatingGroup) {
                    HStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2")
                            .font(.title2)
                            .foregroundStyle(theme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(emptyPresentation.title)
                                .font(.custom("Outfit-SemiBold", size: 16, relativeTo: .headline))
                                .foregroundStyle(theme.text)
                            Text(emptyPresentation.message)
                                .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                                .foregroundStyle(theme.muted)
                        }
                        Spacer()
                        if emptyPresentation.action == .createGroup {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(theme.border, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(emptyPresentation.action == nil)
                .accessibilityIdentifier("organization.create.first")
            } else {
                ForEach(organizationModel.rootNodes) { node in
                    ZStack(alignment: .topTrailing) {
                        NavigationLink(value: ProjectOrganizationRoute(nodeID: node.id)) {
                            CameraeNextProjectGroupCard(
                                node: node,
                                projects: organizationModel.mosaicProjects(in: node.id),
                                childCount: organizationModel.childNodes(of: node.id).count,
                                overflowCount: organizationModel.overflowCount(in: node.id),
                                theme: theme
                            )
                        }
                        .buttonStyle(.plain)

                        Menu {
                            organizationMenuButtons(node)
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(.black.opacity(0.58), in: Circle())
                        }
                        .padding(12)
                        .accessibilityLabel("Ações do grupo \(node.name)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func organizationMenuButtons(_ node: ProjectOrganizationNode) -> some View {
        ForEach(ProjectOrganizationActionPolicy.actions(for: node), id: \.self) { action in
            switch action {
            case .rename:
                Button(CameraeL10n.organizationRename, systemImage: "pencil") { groupToRename = node }
            case .archive:
                Button(CameraeL10n.archive, systemImage: "archivebox") { setGroupArchived(node, true) }
            case .unarchive:
                Button(CameraeL10n.unarchive, systemImage: "archivebox.fill") { setGroupArchived(node, false) }
            case .deletePreservingProjects:
                Button(CameraeL10n.organizationDelete, systemImage: "trash", role: .destructive) {
                    groupToDelete = node
                }
            }
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
        let presentation = CameraeNextCatalogEmptyStatePresentation(
            scope: .projects,
            filter: filter
        )

        return VStack(spacing: 8) {
            Image(systemName: "rectangle.stack")
                .font(.title2)
            Text(presentation.title)
                .font(.custom("Outfit-Medium", size: 15, relativeTo: .subheadline))
        }
        .foregroundStyle(theme.muted)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func projectActionsMenu(_ project: CameraProject) -> some View {
        Menu {
            if project.module == .repeatable {
                Button(CameraeL10n.organizationMoveToGroup, systemImage: "folder") {
                    projectToMove = project
                }
            }
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

    private func beginCreatingGroup() {
        groupName = ""
        isCreatingGroup = true
    }

    private func createGroup() {
        Task {
            do {
                _ = try await projectStore.createOrganizationNode(
                    module: module,
                    parentID: nil,
                    name: groupName
                )
                isCreatingGroup = false
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func renameGroup(_ node: ProjectOrganizationNode, to name: String) {
        Task {
            do {
                try await projectStore.renameOrganizationNode(node, name: name)
                groupToRename = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func setGroupArchived(_ node: ProjectOrganizationNode, _ isArchived: Bool) {
        Task {
            do {
                try await projectStore.setOrganizationNodeArchived(node, isArchived: isArchived)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func move(_ project: CameraProject, to nodeID: UUID?) {
        Task {
            do {
                try await projectStore.moveProject(project, toOrganizationNode: nodeID)
                projectToMove = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deletePendingGroup() {
        guard let node = groupToDelete else { return }
        groupToDelete = nil
        Task {
            do {
                try await projectStore.deleteOrganizationNode(node)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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

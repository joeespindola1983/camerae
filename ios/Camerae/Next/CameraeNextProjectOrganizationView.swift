import CameraeCore
import SwiftUI

struct ProjectOrganizationRoute: Hashable {
    let nodeID: UUID
}

struct CameraeNextProjectOrganizationRouteView: View {
    @EnvironmentObject private var projectStore: ProjectStore

    let route: ProjectOrganizationRoute
    @Binding var path: NavigationPath

    var body: some View {
        if let node = projectStore.organization.nodes.first(where: { $0.id == route.nodeID }) {
            CameraeNextProjectOrganizationDetailView(node: node, path: $path)
        } else {
            ContentUnavailableView(
                CameraeL10n.organizationUnavailable,
                systemImage: "folder.badge.questionmark",
                description: Text(CameraeL10n.organizationUnavailableMessage)
            )
            .task { await projectStore.reloadNow() }
        }
    }
}

struct CameraeNextProjectGroupCard: View {
    let node: ProjectOrganizationNode
    let projects: [CameraProject]
    let childCount: Int
    let overflowCount: Int
    let theme: ProjectListTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                CameraeNextProjectGroupMosaic(projects: projects, overflowCount: overflowCount, theme: theme)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.76)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 58)

                Text(node.name)
                    .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .headline))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
            .frame(height: 160)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(node.isSubgroup ? "SUBGRUPO" : "GRUPO")
                    .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
                    .tracking(1.6)
                    .foregroundStyle(theme.accent)

                Text(summary)
                    .font(.custom("Outfit-Regular", size: 14, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                Text(node.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                    .foregroundStyle(theme.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        }
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(node.isSubgroup ? CameraeL10n.organizationSubgroup : CameraeL10n.organizationGroup) \(node.name), \(summary)"
        )
        .accessibilityIdentifier("organization.open.\(node.id.uuidString)")
    }

    private var summary: String {
        let projectLabel = CameraeL10n.organizationProjectCount(projects.count + overflowCount)
        guard !node.isSubgroup, childCount > 0 else { return projectLabel }
        let subgroupLabel = CameraeL10n.organizationSubgroupCount(childCount)
        return "\(subgroupLabel) · \(projectLabel)"
    }
}

struct CameraeNextProjectGroupMosaicLayout {
    static func frames(count: Int, size: CGSize, gap: CGFloat = 2) -> [CGRect] {
        let itemCount = min(max(count, 0), 4)
        guard itemCount > 0 else { return [] }
        guard itemCount > 1 else { return [CGRect(origin: .zero, size: size)] }

        if itemCount < 4 {
            let width = (size.width - gap * CGFloat(itemCount - 1)) / CGFloat(itemCount)
            return (0..<itemCount).map { index in
                CGRect(
                    x: CGFloat(index) * (width + gap),
                    y: 0,
                    width: width,
                    height: size.height
                )
            }
        }

        let width = (size.width - gap) / 2
        let height = (size.height - gap) / 2
        return (0..<itemCount).map { index in
            CGRect(
                x: CGFloat(index % 2) * (width + gap),
                y: CGFloat(index / 2) * (height + gap),
                width: width,
                height: height
            )
        }
    }
}

private struct CameraeNextProjectGroupMosaic: View {
    let projects: [CameraProject]
    let overflowCount: Int
    let theme: ProjectListTheme

    var body: some View {
        GeometryReader { proxy in
            if projects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 27, weight: .medium))
                        .foregroundStyle(theme.accent)
                    Text(CameraeL10n.organizationNoProjects)
                        .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                        .foregroundStyle(theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.surface)
            } else {
                let frames = CameraeNextProjectGroupMosaicLayout.frames(
                    count: projects.count,
                    size: proxy.size
                )
                ForEach(Array(projects.prefix(4).enumerated()), id: \.element.id) { index, project in
                    mosaicImage(project)
                        .frame(width: frames[index].width, height: frames[index].height)
                        .position(
                            x: frames[index].midX,
                            y: frames[index].midY
                        )
                        .overlay(alignment: .center) {
                            if index == 3, overflowCount > 0 {
                                Color.black.opacity(0.60)
                                    .overlay {
                                        Text("+\(overflowCount)")
                                            .font(.custom("Outfit-SemiBold", size: 24, relativeTo: .title3))
                                            .foregroundStyle(.white)
                                    }
                            }
                        }
                        .clipped()
                }
            }
        }
    }

    @ViewBuilder
    private func mosaicImage(_ project: CameraProject) -> some View {
        if let url = project.referenceFrameURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholder(project)
                }
            }
        } else {
            placeholder(project)
        }
    }

    private func placeholder(_ project: CameraProject) -> some View {
        Rectangle()
            .fill(theme.surface)
            .overlay {
                Image(systemName: project.module.systemImage)
                    .font(.title2)
                    .foregroundStyle(theme.accent)
            }
    }

}

struct CameraeNextOrganizationEditorSheet: View {
    let title: String
    let kind: String
    @Binding var name: String
    let saveTitle: String
    let save: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(kind.uppercased()) {
                    TextField("Nome", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("organization.name")
                }
                Section {
                    Label(
                        CameraeL10n.organizationSafety,
                        systemImage: "checkmark.shield"
                    )
                    .font(.footnote)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CameraeL10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle, action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct CameraeNextProjectMoveSheet: View {
    let project: CameraProject
    let organization: ProjectOrganizationSnapshot
    let move: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss

    private var roots: [ProjectOrganizationNode] {
        organization.nodes
            .filter { $0.module == project.module.coreValue && $0.parentID == nil && !$0.isArchived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                destinationRow(
                    name: CameraeL10n.organizationUngrouped,
                    detail: CameraeL10n.organizationListRoot,
                    nodeID: nil
                )

                ForEach(roots) { root in
                    Section(root.name) {
                        destinationRow(
                            name: root.name,
                            detail: CameraeL10n.organizationGroup,
                            nodeID: root.id
                        )
                        ForEach(organization.children(of: root.id).filter { !$0.isArchived }) { child in
                            destinationRow(
                                name: child.name,
                                detail: CameraeL10n.organizationSubgroup,
                                nodeID: child.id
                            )
                        }
                    }
                }
            }
            .navigationTitle(CameraeL10n.organizationMoveProject)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CameraeL10n.cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func destinationRow(name: String, detail: String, nodeID: UUID?) -> some View {
        Button {
            move(nodeID)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if organization.nodeID(for: project.id) == nodeID {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .accessibilityIdentifier(nodeID.map { "organization.move.\($0.uuidString)" } ?? "organization.move.ungrouped")
    }
}

private struct CameraeNextProjectOrganizationDetailView: View {
    @EnvironmentObject private var projectStore: ProjectStore

    let node: ProjectOrganizationNode
    @Binding var path: NavigationPath

    @State private var sort = CameraeNextProjectCatalogSort.lastActivity
    @State private var isCreatingSubgroup = false
    @State private var subgroupName = ""
    @State private var isCreatingProject = false
    @State private var projectName = ""
    @State private var nodeToRename: ProjectOrganizationNode?
    @State private var nodeToDelete: ProjectOrganizationNode?
    @State private var projectToMove: CameraProject?
    @State private var projectToDelete: CameraProject?
    @State private var errorMessage: String?

    private var module: CameraModule {
        CameraModule(rawValue: node.module.rawValue) ?? .repeatable
    }

    private var theme: ProjectListTheme { .init(module: module) }

    private var model: CameraeNextProjectOrganizationModel {
        .init(
            projects: projectStore.projects,
            module: module,
            organization: projectStore.organization,
            filter: organizationFilter,
            sort: sort
        )
    }

    private var currentNode: ProjectOrganizationNode {
        projectStore.organization.nodes.first(where: { $0.id == node.id }) ?? node
    }

    private var organizationFilter: CameraeNextProjectCatalogFilter {
        guard let parentID = currentNode.parentID,
              let parent = projectStore.organization.nodes.first(where: { $0.id == parentID }) else {
            return currentNode.isArchived ? .archived : .recent
        }
        return currentNode.isArchived || parent.isArchived ? .archived : .recent
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 10) {
                    if !currentNode.isSubgroup {
                        sectionHeader(
                            CameraeL10n.organizationSubgroups,
                            count: model.childNodes(of: currentNode.id).count
                        )
                        ForEach(model.childNodes(of: currentNode.id)) { child in
                            organizationCard(child)
                        }
                    }

                    sectionHeader(
                        CameraeL10n.organizationProjectsSection(isSubgroup: currentNode.isSubgroup),
                        count: model.directProjects(in: currentNode.id).count
                    )
                        .padding(.top, currentNode.isSubgroup ? 4 : 14)

                    ForEach(model.directProjects(in: currentNode.id)) { project in
                        ZStack(alignment: .topTrailing) {
                            NavigationLink(value: project) {
                                ProjectListRow(project: project, theme: theme)
                            }
                            .buttonStyle(.plain)
                            projectMenu(project).padding(10)
                        }
                    }

                    if model.directProjects(in: currentNode.id).isEmpty {
                        ContentUnavailableView(
                            CameraeL10n.organizationNoProjectHere,
                            systemImage: "rectangle.stack.badge.plus",
                            description: Text(CameraeL10n.organizationNoProjectHereMessage)
                        )
                        .foregroundStyle(theme.muted)
                        .padding(.top, 30)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle(currentNode.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.background.opacity(0.96), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    if !currentNode.isSubgroup {
                        Button(CameraeL10n.organizationNewSubgroup, systemImage: "folder.badge.plus") {
                            subgroupName = ""
                            isCreatingSubgroup = true
                        }
                    }
                    Button(CameraeL10n.newProject, systemImage: "plus.rectangle") {
                        projectName = ""
                        isCreatingProject = true
                    }
                    Divider()
                    organizationMenuButtons(currentNode)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Ações de \(currentNode.name)")

                Menu {
                    Picker("Ordenar", selection: $sort) {
                        ForEach(CameraeNextProjectCatalogSort.allCases) { option in
                            Label(option.title, systemImage: option.systemImage).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .tint(theme.accent)
        .preferredColorScheme(theme.colorScheme)
        .sheet(isPresented: $isCreatingSubgroup) {
            CameraeNextOrganizationEditorSheet(
                title: CameraeL10n.organizationNewSubgroup,
                kind: CameraeL10n.organizationSubgroup,
                name: $subgroupName,
                saveTitle: CameraeL10n.create,
                save: createSubgroup
            )
        }
        .sheet(item: $nodeToRename) { selected in
            CameraeNextOrganizationRenameHost(node: selected, rename: rename)
        }
        .sheet(isPresented: $isCreatingProject) {
            CameraeNextNewProjectSheet(
                module: module,
                name: $projectName,
                defaultName: projectStore.defaultProjectName(for: module),
                createAction: createProject
            )
        }
        .sheet(item: $projectToMove) { project in
            CameraeNextProjectMoveSheet(project: project, organization: projectStore.organization) { destination in
                move(project, to: destination)
            }
        }
        .alert("Excluir “\(nodeToDelete?.name ?? "")”?", isPresented: Binding(
            get: { nodeToDelete != nil },
            set: { if !$0 { nodeToDelete = nil } }
        )) {
            Button(CameraeL10n.organizationDelete, role: .destructive, action: deletePendingNode)
            Button(CameraeL10n.cancel, role: .cancel) { nodeToDelete = nil }
        } message: {
            Text(CameraeL10n.organizationDeletePreservingMessage)
        }
        .alert("Excluir “\(projectToDelete?.name ?? "")”?", isPresented: Binding(
            get: { projectToDelete != nil },
            set: { if !$0 { projectToDelete = nil } }
        )) {
            Button("Excluir projeto permanentemente", role: .destructive, action: deletePendingProject)
            Button(CameraeL10n.cancel, role: .cancel) { projectToDelete = nil }
        } message: {
            Text("A referência, capturas, vídeos, timelapses e exportações serão removidos.")
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

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).tracking(1.6)
            Spacer()
            Text("\(count)").foregroundStyle(theme.accent)
        }
        .font(.custom("DMMono-Regular", size: 10, relativeTo: .caption2))
        .foregroundStyle(theme.muted)
        .frame(height: 34)
    }

    private func organizationCard(_ child: ProjectOrganizationNode) -> some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(value: ProjectOrganizationRoute(nodeID: child.id)) {
                CameraeNextProjectGroupCard(
                    node: child,
                    projects: model.mosaicProjects(in: child.id),
                    childCount: 0,
                    overflowCount: model.overflowCount(in: child.id),
                    theme: theme
                )
            }
            .buttonStyle(.plain)

            Menu {
                organizationMenuButtons(child)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(.black.opacity(0.58), in: Circle())
            }
            .padding(12)
            .accessibilityLabel("Ações do subgrupo \(child.name)")
        }
    }

    @ViewBuilder
    private func organizationMenuButtons(_ selected: ProjectOrganizationNode) -> some View {
        ForEach(ProjectOrganizationActionPolicy.actions(for: selected), id: \.self) { action in
            switch action {
            case .rename:
                Button(CameraeL10n.organizationRename, systemImage: "pencil") { nodeToRename = selected }
            case .archive:
                Button(CameraeL10n.archive, systemImage: "archivebox") { setArchived(selected, true) }
            case .unarchive:
                Button(CameraeL10n.unarchive, systemImage: "archivebox.fill") { setArchived(selected, false) }
            case .deletePreservingProjects:
                Button(CameraeL10n.organizationDelete, systemImage: "trash", role: .destructive) {
                    nodeToDelete = selected
                }
            }
        }
    }

    private func projectMenu(_ project: CameraProject) -> some View {
        Menu {
            Button(CameraeL10n.organizationMoveToGroup, systemImage: "folder") { projectToMove = project }
            Button(
                project.isArchived ? CameraeL10n.unarchive : CameraeL10n.archive,
                systemImage: project.isArchived ? "archivebox.fill" : "archivebox"
            ) {
                setProjectArchived(project, !project.isArchived)
            }
            Button(CameraeL10n.deleteProject, systemImage: "trash", role: .destructive) {
                projectToDelete = project
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.black.opacity(0.58), in: Circle())
        }
        .accessibilityLabel("Ações do projeto \(project.name)")
    }

    private func createSubgroup() {
        Task {
            do {
                _ = try await projectStore.createOrganizationNode(
                    module: module,
                    parentID: currentNode.id,
                    name: subgroupName
                )
                isCreatingSubgroup = false
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func createProject() {
        Task {
            do {
                let project = try await projectStore.createProject(module: module, name: projectName)
                try await projectStore.moveProject(project, toOrganizationNode: currentNode.id)
                isCreatingProject = false
                path.append(project)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func rename(_ selected: ProjectOrganizationNode, to name: String) {
        Task {
            do {
                try await projectStore.renameOrganizationNode(selected, name: name)
                nodeToRename = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func setArchived(_ selected: ProjectOrganizationNode, _ archived: Bool) {
        Task {
            do {
                try await projectStore.setOrganizationNodeArchived(selected, isArchived: archived)
                if selected.id == currentNode.id, archived {
                    path.removeLast()
                }
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

    private func deletePendingNode() {
        guard let selected = nodeToDelete else { return }
        nodeToDelete = nil
        Task {
            do {
                try await projectStore.deleteOrganizationNode(selected)
                if selected.id == currentNode.id {
                    path.removeLast()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func setProjectArchived(_ project: CameraProject, _ archived: Bool) {
        Task {
            do {
                try await projectStore.setArchived(project, isArchived: archived)
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

struct CameraeNextOrganizationRenameHost: View {
    let node: ProjectOrganizationNode
    let rename: (ProjectOrganizationNode, String) -> Void

    @State private var name: String

    init(
        node: ProjectOrganizationNode,
        rename: @escaping (ProjectOrganizationNode, String) -> Void
    ) {
        self.node = node
        self.rename = rename
        _name = State(initialValue: node.name)
    }

    var body: some View {
        CameraeNextOrganizationEditorSheet(
            title: CameraeL10n.organizationRename,
            kind: node.isSubgroup ? CameraeL10n.organizationSubgroup : CameraeL10n.organizationGroup,
            name: $name,
            saveTitle: CameraeL10n.save,
            save: { rename(node, name) }
        )
    }
}

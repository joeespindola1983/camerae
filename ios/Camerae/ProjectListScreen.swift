import SwiftUI

struct ProjectNavigationRoute: Hashable, Sendable {
    let projectID: UUID

    init(project: CameraProject) {
        projectID = project.id
    }
}

struct ProjectListScreen: View {
    @EnvironmentObject private var projectStore: ProjectStore

    let module: CameraModule
    @Binding var path: NavigationPath

    @State private var filter = CameraeNextProjectCatalogFilter.recent
    @State private var sort = CameraeNextProjectCatalogSort.createdNewest
    @State private var isCreatingProject = false
    @State private var projectName = ""
    @State private var errorMessage: String?
    @State private var pendingTemporaryProject: PendingTemporaryProject?
    @State private var projectToDelete: CameraProject?

    private var theme: ProjectListTheme { .init(module: module) }
    private var catalog: CameraeNextProjectCatalogModel {
        .init(projects: projectStore.projects, module: module, filter: filter, sort: sort)
    }
    private var lastOpenedProject: CameraProject? { catalog.featuredProject }
    private var remainingProjects: [CameraProject] { catalog.remainingProjects }

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
                    if let lastOpenedProject {
                        NavigationLink(value: ProjectNavigationRoute(project: lastOpenedProject)) {
                            ProjectListHeroCard(project: lastOpenedProject, theme: theme)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            archiveButton(for: lastOpenedProject)
                        }
                        .overlay(alignment: .topTrailing) {
                            actionsMenu(for: lastOpenedProject)
                        }
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

                    if remainingProjects.isEmpty {
                        emptyFilteredState
                            .padding(.top, 26)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(remainingProjects) { project in
                                NavigationLink(value: ProjectNavigationRoute(project: project)) {
                                    ProjectListRow(project: project, theme: theme)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    archiveButton(for: project)
                                    .tint(theme.accent)
                                }
                                .contextMenu {
                                    archiveButton(for: project)
                                }
                                .overlay(alignment: .topTrailing) {
                                    actionsMenu(for: project)
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
                .padding(.horizontal, 16)
            }
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

                Button {
                    beginCreatingProject()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Novo projeto \(theme.title)")
            }
        }
        .tint(theme.accent)
        .preferredColorScheme(theme.colorScheme)
        .sheet(isPresented: $isCreatingProject) {
            NewProjectSheet(
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
        .alert(CameraeL10n.deleteProject, isPresented: Binding(
            get: { projectToDelete != nil },
            set: { if !$0 { projectToDelete = nil } }
        )) {
            Button(CameraeL10n.cancel, role: .cancel) {
                projectToDelete = nil
            }
            Button(CameraeL10n.deleteProject, role: .destructive, action: deleteSelectedProject)
        } message: {
            Text(CameraeL10n.deleteProjectConfirmation)
        }
        .onAppear {
            AppOrientationLock.shared.restorePortrait()
            projectStore.reload()
            evaluatePendingTemporaryProject()
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
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
        }
    }

    private var emptyFilteredState: some View {
        VStack(spacing: 8) {
            Image(systemName: filter == .archived ? "archivebox" : "rectangle.stack")
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
                pendingTemporaryProject = PendingTemporaryProject(
                    project: project,
                    returnPathCount: path.count
                )
                path.append(ProjectNavigationRoute(project: project))
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

    @ViewBuilder
    private func archiveButton(for project: CameraProject) -> some View {
        Button {
            setArchived(project, !project.isArchived)
        } label: {
            Label(
                project.isArchived ? CameraeL10n.unarchive : CameraeL10n.archive,
                systemImage: project.isArchived ? "archivebox.fill" : "archivebox"
            )
        }
    }

    private func actionsMenu(for project: CameraProject) -> some View {
        ProjectCatalogActionsMenu(
            project: project,
            theme: theme,
            setArchived: { isArchived in
                setArchived(project, isArchived)
            },
            requestDelete: {
                projectToDelete = project
            }
        )
    }

    private func deleteSelectedProject() {
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

private struct PendingTemporaryProject {
    let project: CameraProject
    let returnPathCount: Int
}

struct ProjectListTheme {
    let module: CameraModule

    var isAstro: Bool { module == .astrophotography }
    var title: String { CameraeL10n.moduleTitle(module) }
    var caption: String { isAstro ? "ASTRO · LISTA" : "REPEATABLE · LISTA" }
    var systemImage: String { isAstro ? "sparkles" : "sun.max.fill" }
    var showsStars: Bool { isAstro }
    var colorScheme: ColorScheme { isAstro ? .dark : .light }

    var background: Color { isAstro ? CameraeColor.astroDarkBackground : CameraeColor.repeatableLightBackground }
    var card: Color { isAstro ? CameraeColor.astroDarkCard : CameraeColor.repeatableLightCard }
    var surface: Color { isAstro ? CameraeColor.astroDarkSurface : CameraeColor.repeatableLightSurface }
    var text: Color { isAstro ? CameraeColor.astroDarkText : CameraeColor.repeatableLightText }
    var titleText: Color { accent }
    var muted: Color { isAstro ? CameraeColor.astroDarkMuted : CameraeColor.repeatableLightMuted }
    var accent: Color { isAstro ? CameraeColor.astroDarkAccent : CameraeColor.repeatableLightAccent }
    var border: Color { isAstro ? CameraeColor.astroDarkBorder : CameraeColor.repeatableLightBorder }

    var gradient: [Color] {
        isAstro
            ? [Color(red: 0.01, green: 0.02, blue: 0.09), Color(red: 0.08, green: 0.13, blue: 0.52), Color(red: 0.30, green: 0.48, blue: 1)]
            : [Color(red: 0.24, green: 0.03, blue: 0), accent, Color(red: 1, green: 0.62, blue: 0.22)]
    }
}

struct ProjectCatalogActionsMenu: View {
    let project: CameraProject
    let theme: ProjectListTheme
    let setArchived: (Bool) -> Void
    let requestDelete: () -> Void
    var requestMove: () -> Void = {}

    var body: some View {
        Menu {
            ForEach(ProjectCatalogActionPolicy.actions(for: project), id: \.self) { action in
                switch action {
                case .move:
                    Button(action: requestMove) {
                        Label("Mover para grupo", systemImage: "folder")
                    }
                case .archive:
                    Button {
                        setArchived(true)
                    } label: {
                        Label(CameraeL10n.archive, systemImage: "archivebox")
                    }
                case .unarchive:
                    Button {
                        setArchived(false)
                    } label: {
                        Label(CameraeL10n.unarchive, systemImage: "archivebox.fill")
                    }
                case .delete:
                    Button(role: .destructive, action: requestDelete) {
                        Label(CameraeL10n.deleteProject, systemImage: "trash")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(.black.opacity(0.58), in: Circle())
                .padding(10)
        }
        .accessibilityLabel("Opções do projeto \(project.name)")
    }
}

struct ProjectListHeroCard: View {
    let project: CameraProject
    let theme: ProjectListTheme
    private let presentation: ProjectListCardPresentation

    init(project: CameraProject, theme: ProjectListTheme) {
        self.project = project
        self.theme = theme
        presentation = .init(
            summaries: TimelapseSessionStore(project: project).sessionSummaries(),
            fallbackHardware: project.captureProfile?.hardware
        )
    }
    private let layout = ProjectListRowLayout(containerWidth: 361)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProjectListImageHeader(
                project: project,
                height: layout.thumbnailSize.height,
                theme: theme
            ) { EmptyView() }

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.captureTypesText)
                        .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
                        .foregroundStyle(theme.accent)
                        .lineLimit(1)
                    if let camera = presentation.cameraText {
                        Text(camera)
                            .font(.custom("Outfit-SemiBold", size: 11, relativeTo: .caption))
                            .foregroundStyle(theme.muted)
                            .lineLimit(1)
                    }
                    if let date = presentation.lastCaptureText {
                        Text(date)
                            .font(.custom("DMMono-Regular", size: 8, relativeTo: .caption2))
                            .foregroundStyle(theme.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(theme.border, lineWidth: 1) }
        .shadow(color: theme.accent.opacity(0.10), radius: 24, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(CameraeL10n.lastOpenedProject(project.name))
        .accessibilityIdentifier(CameraeAccessibility.openProject(project.id))
    }

}

struct ProjectListRowLayout: Equatable {
    let containerWidth: CGFloat
    let thumbnailHeight: CGFloat = 160
    let informationHeight: CGFloat = 84

    var thumbnailSize: CGSize {
        CGSize(width: containerWidth, height: thumbnailHeight)
    }

    var minimumHeight: CGFloat {
        thumbnailHeight + informationHeight
    }

    var thumbnailRange: ClosedRange<CGFloat> {
        0...thumbnailHeight
    }

    var informationRange: ClosedRange<CGFloat> {
        thumbnailHeight...minimumHeight
    }
}

enum ProjectListCardRegion: Equatable {
    case thumbnail
    case information
}

enum ProjectListCardCapabilityPolicy {
    static let optionsRegion: ProjectListCardRegion = .thumbnail
    static let openRegion: ProjectListCardRegion = .information
}

struct ProjectListCardPresentation: Equatable {
    let captureTypesText: String
    let cameraText: String?
    let lastCaptureText: String?

    init(
        summaries: [TimelapseSessionSummary],
        fallbackHardware: ProjectCaptureHardware?,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        let captures = summaries.filter { summary in
            summary.session.purpose == .capture && (
                summary.frameCount > 0 || summary.videoURL != nil ||
                    summary.videoClipURL != nil || summary.alignedVideoURL != nil ||
                    summary.isAstroProcessed || summary.hasRenderedOutput
            )
        }
        let labels: [RepeatableCaptureKind: String] = [
            .photo: "FOTO", .video: "VÍDEO", .timelapse: "TIMELAPSE"
        ]
        captureTypesText = [RepeatableCaptureKind.photo, .video, .timelapse].compactMap { kind in
            let count = captures.count { $0.captureKind == kind }
            return count > 0 ? "\(labels[kind]!) (\(count))" : nil
        }.joined(separator: " · ")

        let latest = captures.max { $0.session.createdAt < $1.session.createdAt }
        let lens = latest?.session.cameraLens ?? fallbackHardware?.cameraLens
        let zoom = latest?.session.cameraZoomFactor ?? fallbackHardware?.cameraZoomFactor
        if let lens {
            let lensName = switch lens {
            case .ultraWide: "ULTRA-ANGULAR"
            case .wide: "PRINCIPAL"
            case .telephoto: "TELEOBJETIVA"
            }
            let zoomText = zoom.map {
                $0.formatted(.number.locale(locale).precision(.fractionLength(0...1))) + "×"
            }
            cameraText = "CÂMERA · " + [lensName, zoomText].compactMap { $0 }.joined(separator: " ")
        } else {
            cameraText = nil
        }

        if let date = latest?.session.createdAt {
            var style = Date.FormatStyle(
                date: .abbreviated,
                time: .shortened,
                locale: locale,
                calendar: .current,
                timeZone: timeZone
            )
            style = style.weekday(.wide)
            lastCaptureText = date.formatted(style).uppercased(with: locale)
        } else {
            lastCaptureText = nil
        }
    }
}

struct ProjectListRow: View {
    let project: CameraProject
    let theme: ProjectListTheme
    private let layout = ProjectListRowLayout(containerWidth: 361)
    private let presentation: ProjectListCardPresentation

    init(project: CameraProject, theme: ProjectListTheme) {
        self.project = project
        self.theme = theme
        presentation = .init(
            summaries: TimelapseSessionStore(project: project).sessionSummaries(),
            fallbackHardware: project.captureProfile?.hardware
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProjectListImageHeader(
                project: project,
                height: layout.thumbnailSize.height,
                theme: theme
            ) { EmptyView() }

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.captureTypesText)
                        .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
                        .foregroundStyle(theme.accent)
                        .lineLimit(1)
                    if let camera = presentation.cameraText {
                        Text(camera)
                            .font(.custom("Outfit-SemiBold", size: 11, relativeTo: .caption))
                            .foregroundStyle(theme.muted)
                            .lineLimit(1)
                    }
                    if let date = presentation.lastCaptureText {
                        Text(date)
                            .font(.custom("DMMono-Regular", size: 8, relativeTo: .caption2))
                            .foregroundStyle(theme.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: layout.informationHeight, alignment: .topLeading)
        }
        .frame(minHeight: layout.minimumHeight)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.border, lineWidth: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(CameraeL10n.openProject(project.name))
        .accessibilityIdentifier(CameraeAccessibility.openProject(project.id))
    }
}

private struct ProjectListImageHeader<Accessory: View>: View {
    let project: CameraProject
    let height: CGFloat
    let theme: ProjectListTheme
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ProjectListThumbnail(
                imageURL: project.referenceFrameURL,
                label: nil,
                height: height,
                cornerRadius: 0,
                theme: theme
            )
            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .center,
                endPoint: .bottom
            )
            Text(project.name)
                .font(.custom("Outfit-SemiBold", size: 16, relativeTo: .headline))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
        .frame(height: height)
        .overlay(alignment: .topLeading) {
            Text(project.shotNumberLabel)
                .font(.custom("DMMono-Regular", size: 18, relativeTo: .headline).weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(.black.opacity(0.72), in: Capsule())
                .padding(12)
                .accessibilityLabel(
                    project.sequenceNumber.map { "Tomada \($0)" } ?? "Tomada sem número"
                )
        }
        .overlay(alignment: .topTrailing) {
            accessory()
        }
    }
}

private struct ProjectListThumbnail: View {
    let imageURL: URL?
    let label: String?
    let height: CGFloat
    let cornerRadius: CGFloat
    let theme: ProjectListTheme

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: theme.gradient, startPoint: .leading, endPoint: .trailing)
            if imageURL != nil {
                ReferenceThumbnail(
                    imageURL: imageURL,
                    systemImage: theme.systemImage,
                    width: nil,
                    height: height,
                    maxPixelSize: 900,
                    cornerRadius: cornerRadius
                )
                    .overlay(theme.accent.opacity(0.12))
            }
            if let label {
                Text(label)
                    .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
                    .foregroundStyle(.white)
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct ProjectListCaptureCountBadge: View {
    let count: Int
    let theme: ProjectListTheme

    var body: some View {
        Text(CameraeL10n.captureCount(count))
            .font(.custom("DMMono-Regular", size: 8, relativeTo: .caption2))
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(theme.surface, in: Capsule())
    }
}

struct ProjectListEmptyHero: View {
    let theme: ProjectListTheme
    let createAction: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: theme.systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(theme.accent)
            Text(CameraeL10n.startFirstProject)
                .font(.custom("Outfit-SemiBold", size: 17, relativeTo: .headline))
                .foregroundStyle(theme.text)
            Button(action: createAction) {
                Label(CameraeL10n.newProject, systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(CameraeAccessibility.createFirstProject)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 230)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(theme.border, lineWidth: 1) }
    }
}

struct ProjectListTitleLabelStyle: LabelStyle {
    let theme: ProjectListTheme
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(theme.accent, in: Circle())
            configuration.title
        }
    }
}

struct ProjectListStarField: View {
    let color: Color
    var body: some View {
        Canvas { context, size in
            for index in 0..<64 {
                let diameter: CGFloat = index.isMultiple(of: 11) ? 2.4 : (index.isMultiple(of: 5) ? 1.5 : 0.9)
                let x = CGFloat((index * 83 + 37) % 378) + 6
                let y = CGFloat((index * 137 + 91) % 790) + 30
                let opacity = index.isMultiple(of: 11) ? 0.9 : (index.isMultiple(of: 3) ? 0.55 : 0.32)
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)), with: .color(color.opacity(opacity)))
            }
        }
    }
}

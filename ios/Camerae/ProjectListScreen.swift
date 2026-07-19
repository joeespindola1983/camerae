import SwiftUI

struct ProjectListScreen: View {
    @EnvironmentObject private var projectStore: ProjectStore

    let module: CameraModule
    @Binding var path: NavigationPath

    @State private var filter = ProjectListFilter.recent
    @State private var isCreatingProject = false
    @State private var projectName = ""
    @State private var errorMessage: String?
    @State private var pendingTemporaryProject: PendingTemporaryProject?
    @State private var emptyProjectToRemove: CameraProject?

    private var theme: ProjectListTheme { .init(module: module) }
    private var projects: [CameraProject] { projectStore.activeProjects(for: module) }
    private var lastOpenedProject: CameraProject? { projects.first }

    private var remainingProjects: [CameraProject] {
        let remaining = projects.filter { $0.id != lastOpenedProject?.id }
        switch filter {
        case .recent: return remaining
        case .inProgress: return remaining.filter { ($0.summary?.mediaCount ?? 0) == 0 }
        case .completed: return remaining.filter { ($0.summary?.mediaCount ?? 0) > 0 }
        case .favorites: return []
        }
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
                    if let lastOpenedProject {
                        NavigationLink(value: lastOpenedProject) {
                            ProjectListHeroCard(project: lastOpenedProject, theme: theme)
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
                        Text("\(projects.count)")
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
                        ForEach(ProjectListFilter.allCases) { option in
                            Label(option.title, systemImage: option.systemImage).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .accessibilityLabel("Filtrar projetos")

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
        .alert("Projeto temporário vazio", isPresented: Binding(
            get: { emptyProjectToRemove != nil },
            set: { if !$0 { emptyProjectToRemove = nil } }
        )) {
            Button("Remover projeto", role: .destructive) {
                removeEmptyTemporaryProject()
            }
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ProjectListFilter.allCases) { option in
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
            Image(systemName: filter == .favorites ? "star" : "rectangle.stack")
                .font(.title2)
            Text(projects.isEmpty ? "Nenhum projeto ainda" : "Nenhum projeto neste filtro")
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
                let hasCapture = sessions.contains {
                    $0.frameCount > 0 || $0.videoURL != nil || $0.videoClipURL != nil
                }

                if hasCapture {
                    self.pendingTemporaryProject = nil
                } else {
                    emptyProjectToRemove = pendingTemporaryProject.project
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

private struct PendingTemporaryProject {
    let project: CameraProject
    let returnPathCount: Int
}

struct ProjectListTheme {
    let module: CameraModule

    var isAstro: Bool { module == .astrophotography }
    var title: String { isAstro ? "Astro" : "Repeatable" }
    var caption: String { isAstro ? "ASTRO · LISTA" : "REPEATABLE · LISTA" }
    var systemImage: String { isAstro ? "sparkles" : "sun.max.fill" }
    var showsStars: Bool { isAstro }
    var colorScheme: ColorScheme { isAstro ? .dark : .light }

    var background: Color { isAstro ? CameraeColor.astroDarkBackground : CameraeColor.repeatableLightBackground }
    var card: Color { isAstro ? CameraeColor.astroDarkCard : CameraeColor.repeatableLightCard }
    var surface: Color { isAstro ? CameraeColor.astroDarkSurface : CameraeColor.repeatableLightSurface }
    var text: Color { isAstro ? CameraeColor.astroDarkText : CameraeColor.repeatableLightText }
    var muted: Color { isAstro ? CameraeColor.astroDarkMuted : CameraeColor.repeatableLightMuted }
    var accent: Color { isAstro ? CameraeColor.astroDarkAccent : CameraeColor.repeatableLightAccent }
    var border: Color { isAstro ? CameraeColor.astroDarkBorder : CameraeColor.repeatableLightBorder }

    var gradient: [Color] {
        isAstro
            ? [Color(red: 0.01, green: 0.02, blue: 0.09), Color(red: 0.08, green: 0.13, blue: 0.52), Color(red: 0.30, green: 0.48, blue: 1)]
            : [Color(red: 0.24, green: 0.03, blue: 0), accent, Color(red: 1, green: 0.62, blue: 0.22)]
    }
}

private enum ProjectListFilter: String, CaseIterable, Identifiable {
    case recent, inProgress, completed, favorites
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recent: "Recentes"
        case .inProgress: "Em andamento"
        case .completed: "Concluídos"
        case .favorites: "Favoritos"
        }
    }
    var systemImage: String {
        switch self {
        case .recent: "clock"
        case .inProgress: "circle.dotted"
        case .completed: "checkmark.circle"
        case .favorites: "star"
        }
    }
}

struct ProjectListHeroCard: View {
    let project: CameraProject
    let theme: ProjectListTheme

    private var summary: ProjectRowSummary { .init(project: project) }
    private var completed: Bool { (project.summary?.mediaCount ?? 0) > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                ProjectListThumbnail(imageURL: project.referenceFrameURL, label: nil, height: 137, cornerRadius: 0, theme: theme)
                Text("ÚLTIMO ABERTO")
                    .font(.custom("DMMono-Regular", size: 8, relativeTo: .caption2))
                    .tracking(0.64)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(.black.opacity(0.62), in: Capsule())
                    .padding(12)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(project.name)
                    .font(.custom("Outfit-SemiBold", size: 17, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text(summary.subtitle)
                    .font(.custom("Outfit-Regular", size: 11, relativeTo: .caption))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
                HStack(spacing: 14) {
                    metric("camera", "\(project.summary?.sessionCount ?? 0)x")
                    metric("photo.stack", "\(project.summary?.mediaCount ?? 0)f")
                    if let bytes = project.summary?.totalKnownBytes {
                        metric("externaldrive", ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file))
                    }
                    Spacer(minLength: 2)
                    ProjectListStatusBadge(completed: completed, theme: theme)
                }
                .padding(.top, 3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(theme.border, lineWidth: 1) }
        .shadow(color: theme.accent.opacity(0.10), radius: 24, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Último projeto aberto, \(project.name)")
    }

    private func metric(_ image: String, _ value: String) -> some View {
        Label(value, systemImage: image)
            .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
            .foregroundStyle(theme.muted)
    }
}

struct ProjectListRow: View {
    let project: CameraProject
    let theme: ProjectListTheme
    private var completed: Bool { (project.summary?.mediaCount ?? 0) > 0 }

    var body: some View {
        HStack(spacing: 12) {
            ProjectListThumbnail(imageURL: project.referenceFrameURL, label: "\(project.summary?.mediaCount ?? 0)f", height: 60, cornerRadius: 12, theme: theme)
                .frame(width: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.custom("Outfit-SemiBold", size: 14, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text(ProjectRowSummary(project: project).subtitle)
                    .font(.custom("Outfit-Regular", size: 10, relativeTo: .caption2))
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
                HStack {
                    Text(completed ? "CONCLUÍDO" : "EM ANDAMENTO")
                        .foregroundStyle(completed ? Color.green : theme.accent)
                    Spacer()
                    Text(project.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(theme.muted)
                }
                .font(.custom("DMMono-Regular", size: 8, relativeTo: .caption2))
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.muted)
        }
        .padding(12)
        .frame(minHeight: 88)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.border, lineWidth: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Abrir projeto \(project.name)")
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
                ReferenceThumbnail(imageURL: imageURL, systemImage: theme.systemImage, width: nil, height: height, maxPixelSize: 900)
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

private struct ProjectListStatusBadge: View {
    let completed: Bool
    let theme: ProjectListTheme
    var body: some View {
        Text(completed ? "CONCLUÍDO" : "EM ANDAMENTO")
            .font(.custom("DMMono-Regular", size: 8, relativeTo: .caption2))
            .foregroundStyle(completed ? Color.green : theme.accent)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(completed ? Color.green.opacity(0.15) : theme.surface, in: Capsule())
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
            Text("Comece seu primeiro projeto")
                .font(.custom("Outfit-SemiBold", size: 17, relativeTo: .headline))
                .foregroundStyle(theme.text)
            Button("Novo projeto", systemImage: "plus", action: createAction)
                .buttonStyle(.borderedProminent)
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

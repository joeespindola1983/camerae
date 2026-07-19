import SwiftUI

struct RepeatableProjectsMakeView: View {
    @EnvironmentObject private var projectStore: ProjectStore
    @Binding var path: NavigationPath

    @State private var filter = RepeatableProjectFilter.recent
    @State private var isCreatingProject = false
    @State private var projectName = ""
    @State private var errorMessage: String?

    private var projects: [CameraProject] {
        projectStore.activeProjects(for: .repeatable)
    }

    private var lastOpenedProject: CameraProject? {
        projects.first
    }

    private var remainingProjects: [CameraProject] {
        let candidates = projects.filter { $0.id != lastOpenedProject?.id }
        switch filter {
        case .recent:
            return candidates
        case .inProgress:
            return candidates.filter { ($0.summary?.mediaCount ?? 0) == 0 }
        case .completed:
            return candidates.filter { ($0.summary?.mediaCount ?? 0) > 0 }
        case .favorites:
            return []
        }
    }

    var body: some View {
        ZStack {
            CameraeColor.repeatableLightBackground
                .ignoresSafeArea()

            Circle()
                .fill(CameraeColor.repeatableLightAccent.opacity(0.12))
                .frame(width: 460, height: 300)
                .blur(radius: 42)
                .offset(y: -420)
                .allowsHitTesting(false)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if let lastOpenedProject {
                        NavigationLink(value: lastOpenedProject) {
                            RepeatableLatestProjectCard(project: lastOpenedProject)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 12)
                    } else {
                        RepeatableEmptyHero {
                            beginCreatingProject()
                        }
                        .padding(.top, 12)
                    }

                    projectsHeader
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
                                    RepeatableProjectCard(project: project)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button {
                                        setArchived(project, true)
                                    } label: {
                                        Label("Arquivar", systemImage: "archivebox")
                                    }
                                    .tint(CameraeColor.repeatableLightAccent)
                                }
                            }
                        }
                        .padding(.top, 10)
                    }

                    Text("REPEATABLE · LISTA")
                        .font(.custom("DMMono-Regular", size: 8, relativeTo: .caption2))
                        .tracking(1.44)
                        .foregroundStyle(CameraeColor.repeatableLightMuted)
                        .padding(.top, 28)
                        .padding(.bottom, 18)
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(CameraeColor.repeatableLightBackground.opacity(0.96), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Label("Repeatable", systemImage: "sun.max.fill")
                    .font(.custom("Outfit-SemiBold", size: 24, relativeTo: .title2))
                    .foregroundStyle(CameraeColor.repeatableLightText)
                    .labelStyle(RepeatableTitleLabelStyle())
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Filtrar projetos", selection: $filter) {
                        ForEach(RepeatableProjectFilter.allCases) { option in
                            Label(option.title, systemImage: option.systemImage)
                                .tag(option)
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
                .accessibilityLabel("Novo projeto Repeatable")
            }
        }
        .tint(CameraeColor.repeatableLightAccent)
        .preferredColorScheme(.light)
        .sheet(isPresented: $isCreatingProject) {
            NewProjectSheet(
                module: .repeatable,
                name: $projectName,
                defaultName: projectStore.defaultProjectName(for: .repeatable),
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
        .onAppear {
            AppOrientationLock.shared.restorePortrait()
            projectStore.reload()
        }
    }

    private var projectsHeader: some View {
        HStack {
            Text("PROJETOS")
                .font(.custom("DMMono-Regular", size: 10, relativeTo: .caption2))
                .tracking(1.6)
                .foregroundStyle(CameraeColor.repeatableLightMuted)
            Spacer()
            Text("\(projects.count)")
                .font(.custom("DMMono-Regular", size: 11, relativeTo: .caption2))
                .foregroundStyle(CameraeColor.repeatableLightAccent)
        }
        .frame(height: 28)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(RepeatableProjectFilter.allCases) { option in
                    Button(option.title) {
                        filter = option
                    }
                    .font(.custom("Outfit-Regular", size: 10, relativeTo: .caption2))
                    .foregroundStyle(filter == option ? .white : CameraeColor.repeatableLightText)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(
                        filter == option
                            ? CameraeColor.repeatableLightAccent
                            : CameraeColor.repeatableLightSurface,
                        in: Capsule()
                    )
                }
            }
        }
    }

    private var emptyFilteredState: some View {
        VStack(spacing: 8) {
            Image(systemName: filter == .favorites ? "star" : "rectangle.stack")
                .font(.title2)
            Text(filter == .recent && projects.isEmpty ? "Nenhum projeto ainda" : "Nenhum projeto neste filtro")
                .font(.custom("Outfit-Medium", size: 15, relativeTo: .subheadline))
        }
        .foregroundStyle(CameraeColor.repeatableLightMuted)
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
                let project = try await projectStore.createProject(module: .repeatable, name: projectName)
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
}

private enum RepeatableProjectFilter: String, CaseIterable, Identifiable {
    case recent
    case inProgress
    case completed
    case favorites

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

private struct RepeatableLatestProjectCard: View {
    let project: CameraProject

    private var summary: ProjectRowSummary { ProjectRowSummary(project: project) }
    private var isCompleted: Bool { (project.summary?.mediaCount ?? 0) > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                RepeatableWarmThumbnail(
                    imageURL: project.referenceFrameURL,
                    frames: nil,
                    height: 137,
                    cornerRadius: 0
                )

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
                    .foregroundStyle(CameraeColor.repeatableLightText)
                    .lineLimit(1)

                Text(summary.subtitle)
                    .font(.custom("Outfit-Regular", size: 11, relativeTo: .caption))
                    .foregroundStyle(CameraeColor.repeatableLightMuted)
                    .lineLimit(1)

                HStack(spacing: 16) {
                    metric("camera", "\(project.summary?.sessionCount ?? 0)x")
                    metric("photo.stack", "\(project.summary?.mediaCount ?? 0)f")
                    if let bytes = project.summary?.totalKnownBytes {
                        metric("externaldrive", ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file))
                    }
                    Spacer(minLength: 2)
                    statusBadge(completed: isCompleted)
                }
                .padding(.top, 3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .background(CameraeColor.repeatableLightCard)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CameraeColor.repeatableLightBorder, lineWidth: 1)
        }
        .shadow(color: Color(red: 0.4, green: 0.18, blue: 0).opacity(0.10), radius: 24, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Último projeto aberto, \(project.name)")
    }

    private func metric(_ image: String, _ value: String) -> some View {
        Label(value, systemImage: image)
            .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
            .foregroundStyle(CameraeColor.repeatableLightMuted)
    }

    private func statusBadge(completed: Bool) -> some View {
        Text(completed ? "CONCLUÍDO" : "EM ANDAMENTO")
            .font(.custom("DMMono-Regular", size: 8, relativeTo: .caption2))
            .foregroundStyle(completed ? Color(red: 0.25, green: 0.55, blue: 0.27) : CameraeColor.repeatableLightAccent)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(
                completed
                    ? Color(red: 0.86, green: 0.96, blue: 0.85)
                    : CameraeColor.repeatableLightSurface,
                in: Capsule()
            )
    }
}

private struct RepeatableProjectCard: View {
    let project: CameraProject

    private var isCompleted: Bool { (project.summary?.mediaCount ?? 0) > 0 }
    private var frames: String { "\(project.summary?.mediaCount ?? 0)f" }

    var body: some View {
        HStack(spacing: 12) {
            RepeatableWarmThumbnail(
                imageURL: project.referenceFrameURL,
                frames: frames,
                height: 60,
                cornerRadius: 12
            )
            .frame(width: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.custom("Outfit-SemiBold", size: 14, relativeTo: .subheadline))
                    .foregroundStyle(CameraeColor.repeatableLightText)
                    .lineLimit(1)

                Text(ProjectRowSummary(project: project).subtitle)
                    .font(.custom("Outfit-Regular", size: 10, relativeTo: .caption2))
                    .foregroundStyle(CameraeColor.repeatableLightMuted)
                    .lineLimit(1)

                HStack {
                    Text(isCompleted ? "CONCLUÍDO" : "EM ANDAMENTO")
                        .foregroundStyle(isCompleted ? Color.green : CameraeColor.repeatableLightAccent)
                    Spacer()
                    Text(project.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(CameraeColor.repeatableLightMuted)
                }
                .font(.custom("DMMono-Regular", size: 8, relativeTo: .caption2))
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CameraeColor.repeatableLightMuted)
        }
        .padding(12)
        .frame(minHeight: 88)
        .background(CameraeColor.repeatableLightCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CameraeColor.repeatableLightBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Abrir projeto \(project.name)")
    }
}

private struct RepeatableWarmThumbnail: View {
    let imageURL: URL?
    let frames: String?
    let height: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(red: 0.24, green: 0.03, blue: 0), CameraeColor.repeatableLightAccent, Color(red: 1, green: 0.62, blue: 0.22)],
                startPoint: .leading,
                endPoint: .trailing
            )

            if imageURL != nil {
                ReferenceThumbnail(
                    imageURL: imageURL,
                    systemImage: "sun.max.fill",
                    width: nil,
                    height: height,
                    maxPixelSize: 900
                )
                .overlay(CameraeColor.repeatableLightAccent.opacity(0.12))
            }

            if let frames {
                Text(frames)
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

private struct RepeatableEmptyHero: View {
    let createAction: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(CameraeColor.repeatableLightAccent)
            Text("Comece seu primeiro projeto")
                .font(.custom("Outfit-SemiBold", size: 17, relativeTo: .headline))
                .foregroundStyle(CameraeColor.repeatableLightText)
            Button("Novo projeto", systemImage: "plus", action: createAction)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 230)
        .background(CameraeColor.repeatableLightCard)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CameraeColor.repeatableLightBorder, lineWidth: 1)
        }
    }
}

private struct RepeatableTitleLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(CameraeColor.repeatableLightAccent, in: Circle())
            configuration.title
        }
    }
}

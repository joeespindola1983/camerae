import SwiftUI

struct CameraeNextRootView: View {
    @StateObject private var projectStore = ProjectStore()
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            CameraeNextHomeView(path: $path)
                .navigationDestination(for: CameraModule.self) { module in
                    CameraeNextProjectListView(module: module, path: $path)
                }
                .navigationDestination(for: CameraProject.self) { project in
                    CameraeNextProjectRuntimeView(project: project, path: $path)
                }
        }
        .environmentObject(projectStore)
        .onAppear { AppOrientationLock.shared.restorePortrait() }
    }
}

struct CameraeNextHomeView: View {
    @EnvironmentObject private var projectStore: ProjectStore
    @Binding var path: NavigationPath

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("HomeBackgroundPortrait")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: CameraeColor.canvas.opacity(0.08), location: 0),
                                .init(color: CameraeColor.canvas.opacity(0.05), location: 0.20),
                                .init(color: CameraeColor.canvas.opacity(0.29), location: 0.52),
                                .init(color: CameraeColor.canvas.opacity(0.52), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .ignoresSafeArea()

                VStack(spacing: 11) {
                    Image("CameraeBrandSymbol")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 95, height: 95)
                        .clipped()
                    Image("CameraeBrandWordmark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 300, height: 60)
                }
                .position(x: proxy.size.width / 2, y: max(proxy.safeAreaInsets.top + 150, proxy.size.height * 0.28))

                VStack(spacing: 12) {
                    HStack(spacing: 40) {
                        workflowButton(.repeatable, compact: false)
                        workflowButton(.astrophotography, compact: false)
                    }
                    workflowButton(.edit, compact: true)
                }
                .position(x: proxy.size.width / 2, y: proxy.size.height - max(130, proxy.safeAreaInsets.bottom + 110))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .onAppear {
            AppOrientationLock.shared.restorePortrait()
            projectStore.reload()
        }
    }

    private func workflowButton(_ module: CameraModule, compact: Bool) -> some View {
        Button { path.append(module) } label: {
            VStack(spacing: compact ? 8 : 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(module.designTheme.accent.opacity(compact ? 1 : 0.95))
                    .frame(width: compact ? 32 : 52, height: compact ? 32 : 52)
                    .overlay {
                        Image(systemName: module.systemImage)
                            .font(.system(size: compact ? 14 : 22, weight: .medium))
                            .foregroundStyle(.white)
                    }
                Text(module.title)
                    .font(.custom("Outfit-Regular", size: compact ? 10 : 14, relativeTo: .caption))
                    .foregroundStyle(CameraeColor.textPrimary.opacity(0.7))
            }
            .frame(width: compact ? 111 : 120, height: compact ? 79 : 121)
            .background(CameraeColor.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(CameraeColor.borderStrong.opacity(0.5), lineWidth: 1)
            }
            .accessibilityIdentifier(CameraeAccessibility.openModule(module))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CameraeL10n.openModule(module.title))
        .accessibilityValue(CameraeL10n.projectCount(projectStore.projects(for: module).count))
    }
}

struct CameraeNextProjectListView: View {
    @EnvironmentObject private var projectStore: ProjectStore
    let module: CameraModule
    @Binding var path: NavigationPath

    @State private var isCreatingProject = false
    @State private var projectName = ""
    @State private var errorMessage: String?

    var body: some View {
        if module == .repeatable || module == .astrophotography {
            CameraeNextProjectCatalogView(module: module, path: $path)
        } else {
            editorList
        }
    }

    private var editorList: some View {
        let theme = CameraeNextTheme(workflow: .editor)
        return ZStack {
            theme.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(projectStore.activeProjects(for: .edit)) { project in
                        NavigationLink(value: project) {
                            CameraeNextCard(theme: theme) {
                                HStack(spacing: 14) {
                                    Image(systemName: "film.stack")
                                        .font(.title2)
                                        .foregroundStyle(theme.accent)
                                        .frame(width: 52, height: 52)
                                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(project.name)
                                            .font(.custom("Outfit-SemiBold", size: 16, relativeTo: .headline))
                                            .foregroundStyle(theme.text)
                                        Text(ProjectRowSummary(project: project).detail ?? CameraeL10n.moduleEdit)
                                            .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                                            .foregroundStyle(theme.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(theme.muted)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if projectStore.activeProjects(for: .edit).isEmpty {
                        ContentUnavailableView(
                            "Nenhuma montagem",
                            systemImage: "film.stack",
                            description: Text(CameraeL10n.newProjectMessage(for: .edit))
                        )
                        .foregroundStyle(theme.text)
                        .padding(.top, 80)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle(CameraeL10n.moduleEdit)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isCreatingProject = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderedProminent)
            }
        }
        .tint(theme.accent)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isCreatingProject) {
            CameraeNextNewProjectSheet(
                module: .edit,
                name: $projectName,
                defaultName: projectStore.defaultProjectName(for: .edit)
            ) {
                Task {
                    do {
                        let project = try await projectStore.createProject(module: .edit, name: projectName)
                        isCreatingProject = false
                        path.append(project)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .alert(CameraeL10n.error, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button(CameraeL10n.okay, role: .cancel) {} } message: { Text(errorMessage ?? "") }
        .onAppear { projectStore.reload() }
    }
}

struct CameraeNextProjectRuntimeView: View {
    @EnvironmentObject private var projectStore: ProjectStore
    let project: CameraProject
    @Binding var path: NavigationPath

    @State private var captureConfiguration: CameraeNextCaptureConfiguration?
    @State private var isPresentingCapture = false
    @State private var isPresentingSessions = false
    @State private var videoSettings = WorkflowVideoSettings.repeatableDefault
    @State private var completedCapture: CameraeNextCompletedCapture?
    @State private var repeatableWorkspace = CameraeNextRepeatableProjectWorkspaceState()
    @State private var referenceRefreshID = 0

    var body: some View {
        Group {
            if project.module == .edit {
                CameraeNextEditProjectView(project: project)
            } else if project.module == .repeatable {
                VStack(spacing: 0) {
                    CameraeNextProjectTabs(
                        selection: $repeatableWorkspace.section,
                        theme: .init(workflow: .repeatable)
                    )

                    if repeatableWorkspace.section == .configuration {
                        workflowConfiguration(isEmbeddedInProjectWorkspace: true)
                    } else {
                        CameraeNextSessionCatalogView(
                            project: project,
                            onStartNew: { repeatableWorkspace.startNewCapture() },
                            isEmbedded: true,
                            isFinalizingCapture: repeatableWorkspace.isFinalizingCapture,
                            onCatalogLoaded: {
                                guard repeatableWorkspace.isFinalizingCapture else { return }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                    repeatableWorkspace.catalogDidReload()
                                }
                            }
                        )
                    }
                }
                .background(CameraeNextTheme(workflow: .repeatable).background.ignoresSafeArea())
            } else {
                workflowConfiguration(isEmbeddedInProjectWorkspace: false)
            }
        }
        .task { await projectStore.markOpened(project) }
        .fullScreenCover(isPresented: $isPresentingCapture, onDismiss: {
            CameraeCaptureDiagnostics.event("R72 captureCover.dismissed")
            referenceRefreshID += 1
        }) {
            let _ = CameraeCaptureDiagnostics.event(
                "R01.5 captureCover.builder",
                "hasConfiguration=\(captureConfiguration != nil)"
            )
            Group {
                if let captureConfiguration {
                    NavigationStack {
                        if project.module == .repeatable {
                            let _ = CameraeCaptureDiagnostics.event("R01.6 repeatableDestination.builder")
                            RepeatableCameraView(
                                project: project,
                                videoSettings: $videoSettings,
                                nextConfiguration: captureConfiguration,
                                onClose: {
                                    CameraeCaptureDiagnostics.event("R70 capture.closeRequested", "source=repeatable")
                                    isPresentingCapture = false
                                },
                                onCompletedTimelapse: {
                                    presentCompletion(module: .repeatable, session: nil)
                                }
                            )
                        } else {
                            let _ = CameraeCaptureDiagnostics.event("R01.6 astroDestination.builder")
                            CameraView(
                                project: project,
                                nextConfiguration: captureConfiguration,
                                onClose: {
                                    CameraeCaptureDiagnostics.event("R70 capture.closeRequested", "source=astro")
                                    isPresentingCapture = false
                                },
                                onCompletedSession: { session in
                                    presentCompletion(module: .astrophotography, session: session)
                                }
                            )
                        }
                    }
                } else {
                    CameraeCaptureDiagnosticFallback(
                        message: "A configuração da captura não chegou ao destino."
                    )
                }
            }
            .interactiveDismissDisabled()
        }
        .onChange(of: captureConfiguration) { _, configuration in
            CameraeCaptureDiagnostics.event(
                "R01.4 configuration.changed",
                "isNil=\(configuration == nil)"
            )
        }
        .onChange(of: isPresentingCapture) { _, isPresented in
            CameraeCaptureDiagnostics.event(
                "R01.4 presentation.changed",
                "isPresented=\(isPresented)"
            )
        }
        .fullScreenCover(item: $completedCapture) { capture in
            CameraeNextCaptureCompletionView(
                capture: capture,
                onDone: { completedCapture = nil },
                onOpenSessions: {
                    completedCapture = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        isPresentingSessions = true
                    }
                }
            )
        }
        .sheet(isPresented: $isPresentingSessions) {
            CameraeNextSessionCatalogView(project: project) {
                isPresentingSessions = false
            }
        }
    }

    private func workflowConfiguration(isEmbeddedInProjectWorkspace: Bool) -> some View {
        CameraeNextWorkflowConfigurationView(
            project: project,
            onStart: { configuration in
                CameraeCaptureDiagnostics.event(
                    "R01 configuration.startTapped",
                    "module=\(configuration.module) kind=\(configuration.repeatableKind) lens=\(configuration.cameraLens.rawValue)"
                )
                captureConfiguration = configuration
                CameraeCaptureDiagnostics.event("R01.1 configuration.stateStored")
                videoSettings = configuration.videoSettings
                CameraeCaptureDiagnostics.event(
                    "R01.2 videoSettings.stateStored",
                    "summary=\(configuration.videoSettings.summary)"
                )
                isPresentingCapture = true
                CameraeCaptureDiagnostics.event("R01.3 capturePresentation.requested")
            },
            onShowSessions: {
                if project.module == .repeatable {
                    repeatableWorkspace.showCaptures()
                } else {
                    isPresentingSessions = true
                }
            },
            isEmbeddedInProjectWorkspace: isEmbeddedInProjectWorkspace,
            referenceRefreshID: referenceRefreshID
        )
    }

    private func presentCompletion(module: CameraModule, session: TimelapseSession?) {
        CameraeCaptureDiagnostics.event("R71 capture.completed", "module=\(module)")
        isPresentingCapture = false
        if CameraeNextCaptureCompletionRoute(module: module) == .projectCaptures {
            repeatableWorkspace.captureDidFinish()
            projectStore.reload()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            completedCapture = .init(module: module, session: session)
            projectStore.reload()
        }
    }
}

private struct CameraeCaptureDiagnosticFallback: View {
    let message: String

    var body: some View {
        ContentUnavailableView(
            "Falha ao abrir a captura",
            systemImage: "exclamationmark.camera",
            description: Text(message)
        )
        .onAppear {
            CameraeCaptureDiagnostics.error("R95 captureCover.missingConfiguration", message)
        }
    }
}

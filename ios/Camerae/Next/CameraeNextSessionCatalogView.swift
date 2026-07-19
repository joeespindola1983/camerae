import SwiftUI

struct CameraeNextSessionCatalogModel: Equatable {
    let sessions: [TimelapseSessionSummary]

    init(summaries: [TimelapseSessionSummary]) {
        sessions = summaries
            .filter { $0.frameCount > 0 }
            .sorted { $0.session.createdAt > $1.session.createdAt }
    }

    var totalFrames: Int { sessions.reduce(0) { $0 + $1.frameCount } }
}

struct CameraeNextSessionCatalogPresentation: Equatable, Sendable {
    let title: String
    let emptyTitle: String
    let emptyMessage: String

    init(module: CameraModule) {
        if module == .astrophotography {
            title = "Sessões Astro"
            emptyTitle = "Nenhuma sessão Astro"
            emptyMessage = "As sessões com imagens aparecerão aqui para processamento."
        } else {
            title = "Capturas Repeatable"
            emptyTitle = "Nenhuma captura"
            emptyMessage = "As capturas com pelo menos uma imagem aparecerão aqui."
        }
    }
}

struct CameraeNextSessionCatalogView: View {
    let project: CameraProject
    let onStartNew: () -> Void

    @State private var summaries: [TimelapseSessionSummary] = []
    @State private var selectedSession: TimelapseSessionSummary?
    @State private var pendingDeletion: TimelapseSession?
    @State private var renderingSessionID: UUID?
    @State private var shareItem: CameraeNextSessionShareItem?
    @State private var errorMessage: String?
    @State private var videoSettings = WorkflowVideoSettings.repeatableDefault

    private var store: TimelapseSessionStore { .init(project: project) }
    private var theme: CameraeNextTheme { .init(workflow: project.module.designTheme) }
    private var presentation: CameraeNextSessionCatalogPresentation { .init(module: project.module) }
    private var catalog: CameraeNextSessionCatalogModel { .init(summaries: summaries) }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.background.ignoresSafeArea()

                if catalog.sessions.isEmpty {
                    ContentUnavailableView(
                        presentation.emptyTitle,
                        systemImage: "photo.stack",
                        description: Text(presentation.emptyMessage)
                    )
                    .foregroundStyle(theme.text)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(catalog.sessions) { summary in
                                sessionRow(summary)
                            }
                        }
                        .frame(maxWidth: 620)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(presentation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.background.opacity(0.96), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onStartNew) {
                        Label("Nova captura", systemImage: "plus")
                    }
                }
            }
        }
        .tint(theme.accent)
        .preferredColorScheme(theme.colorScheme)
        .task { await reload() }
        .fullScreenCover(item: $selectedSession) { summary in
            if project.module == .astrophotography {
                NavigationStack {
                    CameraeNextAstroProcessingView(session: summary.session) {
                        selectedSession = nil
                        Task { await reload() }
                    }
                }
            } else {
                NavigationStack {
                    RepeatableCameraView(
                        project: project,
                        referenceURL: summary.referenceFrameURL,
                        openedSession: summary.session,
                        videoSettings: $videoSettings,
                        nextConfiguration: .repeatableDefault,
                        onClose: {
                            selectedSession = nil
                            Task { await reload() }
                        },
                        onCompletedTimelapse: {
                            selectedSession = nil
                            Task { await reload() }
                        },
                        onDeletedOpenedTimelapse: {
                            selectedSession = nil
                            Task { await reload() }
                        }
                    )
                }
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .alert("Excluir esta captura?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )) {
            Button("Excluir", role: .destructive) { deletePendingSession() }
            Button("Cancelar", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("As imagens e os arquivos gerados desta captura serão removidos.")
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

    private func sessionRow(_ summary: TimelapseSessionSummary) -> some View {
        Button { selectedSession = summary } label: {
            CameraeNextCard(theme: theme) {
                HStack(spacing: 14) {
                    ReferenceThumbnail(
                        imageURL: summary.referenceFrameURL,
                        systemImage: project.module == .astrophotography ? "sparkles" : "camera.viewfinder",
                        width: 74,
                        height: 64
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(summary.session.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.custom("Outfit-SemiBold", size: 15, relativeTo: .headline))
                            .foregroundStyle(theme.text)
                        Text("\(summary.frameCount) imagens")
                            .font(.custom("DMMono-Regular", size: 11, relativeTo: .caption))
                            .foregroundStyle(theme.accent)
                        if summary.hasRenderedOutput {
                            Label("Resultado disponível", systemImage: "checkmark.circle")
                                .font(.custom("Outfit-Regular", size: 11, relativeTo: .caption))
                                .foregroundStyle(theme.muted)
                        }
                    }

                    Spacer()

                    if renderingSessionID == summary.id {
                        ProgressView().tint(theme.accent)
                    } else {
                        Menu {
                            if project.module == .repeatable, summary.captureKind == .timelapse {
                                Button("Gerar MP4", systemImage: "film") {
                                    Task { await render(summary.session) }
                                }
                            }
                            if let url = summary.videoURL ?? summary.videoClipURL {
                                Button("Compartilhar", systemImage: "square.and.arrow.up") {
                                    shareItem = .init(url: url)
                                }
                            }
                            Button("Excluir", systemImage: "trash", role: .destructive) {
                                pendingDeletion = summary.session
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 40, height: 40)
                                .background(theme.surface, in: Circle())
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abrir sessão com \(summary.frameCount) imagens")
    }

    @MainActor
    private func reload() async {
        do {
            summaries = try await store.sessionSummariesFromCatalog()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePendingSession() {
        guard let session = pendingDeletion else { return }
        do {
            try store.deleteSession(session)
            pendingDeletion = nil
            Task { await reload() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func render(_ session: TimelapseSession) async {
        guard renderingSessionID == nil else { return }
        renderingSessionID = session.id
        defer { renderingSessionID = nil }
        do {
            let url = try await store.renderVideo(for: session, settings: videoSettings)
            shareItem = .init(url: url)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CameraeNextSessionShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

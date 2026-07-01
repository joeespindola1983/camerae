import SwiftUI

struct RepeatableProjectRuntimeView: View {
    let project: CameraProject
    let onDeleteProject: () throws -> Void

    @State private var mode = RepeatableProjectMode.list
    @State private var sessions: [TimelapseSessionSummary] = []
    @State private var isConfirmingProjectDelete = false
    @State private var isConfirmingSessionDelete = false
    @State private var pendingSessionDelete: TimelapseSession?
    @State private var renderingSessionID: UUID?
    @State private var shareURL: URL?
    @State private var isShowingShareSheet = false
    @State private var errorMessage: String?

    private let store: TimelapseSessionStore

    init(project: CameraProject, onDeleteProject: @escaping () throws -> Void = {}) {
        self.project = project
        self.onDeleteProject = onDeleteProject
        store = TimelapseSessionStore(project: project)
    }

    var body: some View {
        Group {
            switch mode {
            case .list:
                sessionList
            case .capture(let referenceURL, let sourceSession):
                RepeatableCameraView(
                    project: project,
                    referenceURL: referenceURL,
                    openedSession: sourceSession,
                    onCompletedTimelapse: {
                        reloadSessions()
                        mode = .list
                    },
                    onDeletedOpenedTimelapse: {
                        reloadSessions()
                        mode = .list
                    }
                )
            }
        }
        .onAppear {
            reloadSessions()
        }
        .alert("Excluir este projeto?", isPresented: $isConfirmingProjectDelete) {
            Button("Excluir projeto", role: .destructive) {
                deleteProject()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Essa acao apaga todas as imagens e nao pode ser desfeita.")
        }
        .alert("Excluir esta captura?", isPresented: $isConfirmingSessionDelete) {
            Button("Excluir captura", role: .destructive) {
                deletePendingSession()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Essa acao apaga somente os frames, o MP4 e os arquivos desta captura. O projeto Repeatable continua salvo.")
        }
        .alert("Erro", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $isShowingShareSheet) {
            if let shareURL {
                ShareSheet(items: [shareURL])
            }
        }
    }

    private var sessionList: some View {
        List {
            Section {
                Button {
                    mode = .capture(referenceURL: store.firstReferenceFrameURL(), sourceSession: nil)
                } label: {
                    Label("Criar timelapse", systemImage: "camera.viewfinder")
                }
            }

            Section("Timelapses") {
                if sessions.isEmpty {
                    Text("Nenhum timelapse ainda")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessions) { summary in
                        Button {
                            mode = .capture(referenceURL: summary.referenceFrameURL, sourceSession: summary.session)
                        } label: {
                            RepeatableSessionRow(
                                summary: summary,
                                isRendering: renderingSessionID == summary.id,
                                renderAction: {
                                    Task {
                                        await renderVideo(for: summary.session)
                                    }
                                },
                                shareAction: {
                                    shareMedia(for: summary)
                                }
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                pendingSessionDelete = summary.session
                                isConfirmingSessionDelete = true
                            } label: {
                                Label("Excluir captura", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    isConfirmingProjectDelete = true
                } label: {
                    Label("Excluir projeto", systemImage: "trash")
                }
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func reloadSessions() {
        sessions = store.sessionSummaries()
    }

    private func deletePendingSession() {
        guard let pendingSessionDelete else { return }

        do {
            try store.deleteSession(pendingSessionDelete)
            self.pendingSessionDelete = nil
            reloadSessions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteProject() {
        do {
            try onDeleteProject()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func renderVideo(for session: TimelapseSession) async {
        guard renderingSessionID == nil else { return }
        guard session.captureKind == .timelapse else {
            errorMessage = "MP4 so pode ser gerado para timelapse."
            return
        }

        renderingSessionID = session.id

        do {
            let videoURL = try await store.renderVideo(for: session, fps: 24)
            reloadSessions()
            shareVideo(videoURL)
        } catch {
            errorMessage = error.localizedDescription
        }

        renderingSessionID = nil
    }

    private func shareVideo(_ url: URL?) {
        guard let url else {
            errorMessage = "MP4 ainda nao foi gerado para este timelapse."
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "MP4 nao encontrado. Gere o video novamente."
            reloadSessions()
            return
        }

        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) > 0 else {
                errorMessage = "MP4 esta vazio. Gere o video novamente."
                reloadSessions()
                return
            }
        } catch {
            errorMessage = "Nao foi possivel validar o MP4 antes de exportar."
            return
        }

        shareURL = url
        isShowingShareSheet = true
    }

    private func shareMedia(for summary: TimelapseSessionSummary) {
        switch summary.captureKind {
        case .timelapse:
            shareVideo(summary.videoURL)
        case .video:
            shareVideoClip(summary.videoClipURL)
        case .photo:
            shareVideo(summary.referenceFrameURL)
        }
    }

    private func shareVideoClip(_ url: URL?) {
        guard let url else {
            errorMessage = "Video ainda nao foi gerado para esta captura."
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "Video nao encontrado."
            reloadSessions()
            return
        }

        shareURL = url
        isShowingShareSheet = true
    }
}

private enum RepeatableProjectMode: Equatable {
    case list
    case capture(referenceURL: URL?, sourceSession: TimelapseSession?)
}

private struct RepeatableSessionRow: View {
    let summary: TimelapseSessionSummary
    let isRendering: Bool
    let renderAction: () -> Void
    let shareAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ReferenceThumbnail(imageURL: summary.referenceFrameURL, systemImage: "photo")

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(summary.session.name)
                        .font(.headline)
                    Spacer()
                    Text("\(summary.frameCount)")
                        .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Text(summary.session.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Label(summary.captureKind.title, systemImage: summary.captureKind.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if summary.captureKind == .timelapse, summary.videoURL != nil {
                    Label("MP4 pronto", systemImage: "film")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if summary.captureKind == .video, summary.videoClipURL != nil {
                    Label("Video pronto", systemImage: "video.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                if (summary.captureKind == .timelapse && summary.videoURL != nil) ||
                    (summary.captureKind == .video && summary.videoClipURL != nil) {
                    Button {
                        shareAction()
                    } label: {
                        Label("Exportar", systemImage: "square.and.arrow.up")
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 36)
                    }
                    .buttonStyle(.bordered)
                }

                if summary.captureKind == .timelapse {
                    Button {
                        renderAction()
                    } label: {
                        if isRendering {
                            ProgressView()
                                .frame(width: 44, height: 36)
                        } else {
                            Label("MP4", systemImage: "film")
                                .labelStyle(.iconOnly)
                                .frame(width: 44, height: 36)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRendering || summary.frameCount == 0)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

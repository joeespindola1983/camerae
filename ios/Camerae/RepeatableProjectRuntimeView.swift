import AVFoundation
import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct RepeatableProjectRuntimeView: View {
    let project: CameraProject
    let onDeleteProject: () throws -> Void

    @State private var mode = RepeatableProjectMode.list
    @State private var sessions: [TimelapseSessionSummary] = []
    @State private var isConfirmingProjectDelete = false
    @State private var isConfirmingSessionDelete = false
    @State private var pendingSessionDelete: TimelapseSession?
    @State private var renderingSessionID: UUID?
    @State private var exportingOriginalFramesSessionID: UUID?
    @State private var shareURL: URL?
    @State private var isShowingShareSheet = false
    @State private var exportedArchiveURLs: [URL] = []
    @State private var isShowingExportedArchives = false
    @State private var exportProgress: OriginalFrameExportProgress?
    @State private var exportTask: Task<Void, Never>?
    @State private var videoSettings = WorkflowVideoSettings.repeatableDefault
    @State private var errorMessage: String?
    @State private var importedReferenceItem: PhotosPickerItem?
    @State private var isImportingReference = false

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
                    videoSettings: $videoSettings,
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
        .overlay {
            if exportingOriginalFramesSessionID != nil {
                BlockingProgressOverlay(
                    title: "Exportando ZIP",
                    message: "Gerando pacote com os frames originais",
                    detail: exportProgress?.detailText ?? "Preparando",
                    cancelTitle: "Parar",
                    cancelAction: {
                        exportTask?.cancel()
                    }
                )
            }
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
        .sheet(isPresented: $isShowingExportedArchives) {
            if !exportedArchiveURLs.isEmpty {
                ExportedArchivesView(urls: exportedArchiveURLs)
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

                if store.firstReferenceFrameURL() == nil {
                    PhotosPicker(
                        selection: $importedReferenceItem,
                        matching: .any(of: [.images, .videos]),
                        photoLibrary: .shared()
                    ) {
                        if isImportingReference {
                            HStack {
                                ProgressView()
                                Text("Importando referencia")
                            }
                        } else {
                            Label("Importar referencia", systemImage: "square.and.arrow.down")
                        }
                    }
                    .disabled(isImportingReference)
                    .onChange(of: importedReferenceItem) { _, item in
                        guard let item else { return }
                        Task {
                            await importReference(from: item)
                        }
                    }
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
                                isExportingOriginalFrames: exportingOriginalFramesSessionID == summary.id,
                                isBusy: renderingSessionID != nil || exportingOriginalFramesSessionID != nil,
                                renderAction: {
                                    Task {
                                        await renderVideo(for: summary.session)
                                    }
                                },
                                shareAction: {
                                    shareMedia(for: summary)
                                },
                                exportOriginalFramesAction: {
                                    startExportOriginalFrames(for: summary.session)
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

    @MainActor
    private func importReference(from item: PhotosPickerItem) async {
        guard !isImportingReference else { return }
        isImportingReference = true
        defer {
            isImportingReference = false
            importedReferenceItem = nil
        }

        do {
            guard let media = try await item.loadTransferable(type: ImportedReferenceMedia.self) else {
                throw ReferenceImportError.unreadableMedia
            }
            defer {
                try? FileManager.default.removeItem(at: media.url)
            }

            let image: UIImage
            switch media.kind {
            case .image:
                guard let importedImage = UIImage(contentsOfFile: media.url.path) else {
                    throw ReferenceImportError.unreadableImage
                }
                image = importedImage
            case .video:
                image = try await Self.referenceFrame(from: media.url)
            }

            _ = try store.importReferenceImage(image)
            reloadSessions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func referenceFrame(from url: URL) async throws -> UIImage {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        let frameSecond = durationSeconds.isFinite ? min(max(durationSeconds * 0.05, 0), 0.25) : 0
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        return try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(
                for: CMTime(seconds: frameSecond, preferredTimescale: 600)
            ) { image, _, error in
                if let image {
                    continuation.resume(returning: UIImage(cgImage: image))
                } else {
                    continuation.resume(throwing: error ?? ReferenceImportError.unreadableVideo)
                }
            }
        }
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
            let videoURL = try await store.renderVideo(for: session, settings: videoSettings)
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

    private func exportOriginalFrames(for session: TimelapseSession) async {
        guard exportingOriginalFramesSessionID == nil, renderingSessionID == nil else { return }
        exportingOriginalFramesSessionID = session.id
        exportProgress = nil

        do {
            exportedArchiveURLs = try await store.exportOriginalFramesArchivesInBackground(for: session) { progress in
                await MainActor.run {
                    exportProgress = progress
                }
            }
            isShowingExportedArchives = true
        } catch is CancellationError {
            exportedArchiveURLs = TimelapseSessionStore.existingOriginalFrameArchives(for: session)
            isShowingExportedArchives = !exportedArchiveURLs.isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }

        exportingOriginalFramesSessionID = nil
        exportProgress = nil
        exportTask = nil
    }

    private func startExportOriginalFrames(for session: TimelapseSession) {
        exportTask = Task {
            await exportOriginalFrames(for: session)
        }
    }
}

private struct ImportedReferenceMedia: Transferable {
    enum Kind: Sendable {
        case image
        case video
    }

    let url: URL
    let kind: Kind

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            try copiedMedia(from: received.file, kind: .image)
        }
        FileRepresentation(importedContentType: .movie) { received in
            try copiedMedia(from: received.file, kind: .video)
        }
    }

    private static func copiedMedia(from sourceURL: URL, kind: Kind) throws -> ImportedReferenceMedia {
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(sourceURL.pathExtension)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return ImportedReferenceMedia(url: destinationURL, kind: kind)
    }
}

private enum ReferenceImportError: LocalizedError {
    case unreadableMedia
    case unreadableImage
    case unreadableVideo

    var errorDescription: String? {
        switch self {
        case .unreadableMedia:
            return "Nao foi possivel abrir o item selecionado."
        case .unreadableImage:
            return "Nao foi possivel ler a foto selecionada."
        case .unreadableVideo:
            return "Nao foi possivel extrair uma imagem do video selecionado."
        }
    }
}

private enum RepeatableProjectMode: Equatable {
    case list
    case capture(referenceURL: URL?, sourceSession: TimelapseSession?)
}

private struct RepeatableSessionRow: View {
    let summary: TimelapseSessionSummary
    let isRendering: Bool
    let isExportingOriginalFrames: Bool
    let isBusy: Bool
    let renderAction: () -> Void
    let shareAction: () -> Void
    let exportOriginalFramesAction: () -> Void
    @State private var videoDuration: TimeInterval?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ReferenceThumbnail(imageURL: summary.referenceFrameURL, systemImage: "photo")

            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                Text(summary.session.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Label(summary.captureKind.title, systemImage: summary.captureKind.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let videoDuration {
                    Label(Self.formattedDuration(videoDuration), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if summary.captureKind != .video {
                    Label("\(summary.frameCount) frames", systemImage: "photo.stack")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if summary.captureKind == .timelapse, summary.videoURL != nil {
                    Label("MP4 pronto", systemImage: "film")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if summary.captureKind == .video, summary.videoClipURL != nil {
                    Label("Video pronto", systemImage: "video.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                actionButtons
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .task(id: summary.videoClipURL) {
            videoDuration = await loadVideoDuration(from: summary.videoClipURL)
        }
    }

    private var displayTitle: String {
        switch summary.captureKind {
        case .video: return "Clipe de video"
        case .timelapse: return "Timelapse"
        case .photo: return "Foto"
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
                Button {
                    exportOriginalFramesAction()
                } label: {
                    if isExportingOriginalFrames {
                        ProgressView()
                            .frame(width: 44, height: 36)
                    } else {
                        Label("Originais", systemImage: "photo.stack")
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 36)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isBusy || summary.frameCount == 0)

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
                    .disabled(isBusy)
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
                    .disabled(isBusy || summary.frameCount == 0)
                }
        }
    }

    private func loadVideoDuration(from url: URL?) async -> TimeInterval? {
        guard let url else { return nil }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds >= 0 ? seconds : nil
    }

    private static func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

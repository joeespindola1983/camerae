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
    @State private var shareURL: URL?
    @State private var isShowingShareSheet = false
    @State private var videoSettings = WorkflowVideoSettings.repeatableDefault
    @State private var errorMessage: String?
    @State private var importedReferenceItem: PhotosPickerItem?
    @State private var isImportingReference = false

    private let store: TimelapseSessionStore

    private var firstReferenceFrameURL: URL? {
        sessions
            .filter { $0.frameCount > 0 }
            .sorted { $0.session.createdAt < $1.session.createdAt }
            .compactMap(\.referenceFrameURL)
            .first
    }

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
                    onClose: {
                        reloadSessions()
                        mode = .list
                    },
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
                    mode = .capture(referenceURL: firstReferenceFrameURL, sourceSession: nil)
                } label: {
                    Label("Criar timelapse", systemImage: "camera.viewfinder")
                }

                if firstReferenceFrameURL == nil {
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
                        RepeatableSessionRow(
                                summary: summary,
                                isRendering: renderingSessionID == summary.id,
                                isBusy: renderingSessionID != nil,
                                renderAction: {
                                    Task {
                                        await renderVideo(for: summary.session)
                                    }
                                },
                                shareAction: {
                                    shareMedia(for: summary)
                                }
                            )
                        .onTapGesture {
                            mode = .capture(referenceURL: summary.referenceFrameURL, sourceSession: summary.session)
                        }
                        .accessibilityAddTraits(.isButton)
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
        Task {
            do {
                sessions = try await store.sessionSummariesFromCatalog()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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

struct SessionCardMetadata: Equatable {
    let title: String
    let mediaDescription: String
    let frameDescription: String
    let durationDescription: String
    let compilationDescription: String
    let isCompiled: Bool

    init(summary: TimelapseSessionSummary, duration: TimeInterval?) {
        switch summary.captureKind {
        case .video:
            title = "Clipe de vídeo"
            mediaDescription = "Vídeo"
        case .timelapse:
            title = summary.session.module == .astrophotography ? "Timelapse Astro" : "Timelapse"
            mediaDescription = "Sequência de imagens"
        case .photo:
            title = "Imagem de referencia"
            mediaDescription = "Imagem"
        }

        frameDescription = summary.frameCount == 1 ? "1 frame" : "\(summary.frameCount) frames"
        durationDescription = duration.map(Self.formattedDuration) ?? "Duração indisponível"
        isCompiled = summary.hasRenderedOutput

        if summary.captureKind == .video {
            compilationDescription = summary.videoClipURL == nil ? "Vídeo indisponível" : "Vídeo pronto"
        } else if summary.captureKind == .photo {
            compilationDescription = "Não requer compilação"
        } else {
            compilationDescription = isCompiled ? "Compilado" : "Aguardando compilação"
        }
    }

    private static func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

struct RepeatableSessionRow: View {
    let summary: TimelapseSessionSummary
    let isRendering: Bool
    let isBusy: Bool
    var showsActions = true
    let renderAction: () -> Void
    let shareAction: () -> Void
    @State private var videoDuration: TimeInterval?

    var body: some View {
        let metadata = SessionCardMetadata(
            summary: summary,
            duration: videoDuration ?? summary.captureDuration
        )

        VStack(alignment: .leading, spacing: 12) {
            ReferenceThumbnail(
                imageURL: summary.referenceFrameURL,
                systemImage: summary.session.module == .astrophotography ? "sparkles" : "photo.stack",
                width: nil,
                height: 180,
                maxPixelSize: 720
            )

            HStack(alignment: .firstTextBaseline) {
                Text(metadata.title)
                    .font(.title3.weight(.semibold))
                Spacer(minLength: 8)
                Label(
                    metadata.compilationDescription,
                    systemImage: metadata.isCompiled ? "checkmark.circle.fill" : "clock"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(metadata.isCompiled ? Color.green : Color.secondary)
            }

            Text(summary.session.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                metadataItem(metadata.mediaDescription, systemImage: summary.captureKind.systemImage)
                metadataItem(metadata.frameDescription, systemImage: "photo.stack")
                metadataItem(metadata.durationDescription, systemImage: "clock")
            }

            if showsActions {
                actionButtons
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .task(id: durationURL) {
            videoDuration = await loadVideoDuration(from: durationURL)
        }
    }

    private var durationURL: URL? {
        summary.videoClipURL ?? summary.videoURL
    }

    private func metadataItem(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            if (summary.captureKind == .timelapse && summary.videoURL != nil) ||
                (summary.captureKind == .video && summary.videoClipURL != nil) {
                Button {
                    shareAction()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 44, height: 36)
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
                .accessibilityLabel("Exportar vídeo")
            }

            if summary.captureKind == .timelapse {
                Button {
                    renderAction()
                } label: {
                    if isRendering {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label(summary.videoURL == nil ? "Compilar" : "Recompilar", systemImage: "film")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
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

}

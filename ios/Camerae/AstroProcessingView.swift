import AVKit
import ImageIO
import SwiftUI

struct AstroProcessingView: View {
    let session: TimelapseSession
    let onComplete: () -> Void
    let onDeleteProject: () throws -> Void

    @StateObject private var processor: AstroProcessingController
    @State private var stackSize = 10.0
    @State private var fps = 24.0
    @State private var processingProfile = AstroProcessingProfile.natural
    @State private var usesAutomaticStackingStart = true
    @State private var stackingStartFrame = 1.0
    @State private var isConfirmingProjectDelete = false
    @State private var previewItem: AstroClipItem?
    @State private var shareItem: AstroClipItem?
    @State private var pendingClipDelete: AstroRenderedClip?
    @State private var isConfirmingClipDelete = false
    @State private var shareErrorMessage: String?
    @State private var deleteErrorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private let minStackSize = 5
    private let maxAllowedStackSize = 30

    init(
        session: TimelapseSession,
        onComplete: @escaping () -> Void = {},
        onDeleteProject: @escaping () throws -> Void = {}
    ) {
        self.session = session
        self.onComplete = onComplete
        self.onDeleteProject = onDeleteProject
        _processor = StateObject(wrappedValue: AstroProcessingController(session: session))
    }

    private var outputFrameCount: Int {
        processor.outputFrameCount(
            stackSize: Int(stackSize),
            stackingStartFrame: effectiveStackingStartFrame
        )
    }

    private var maxStackSize: Int {
        if canUseCompositeFrames {
            return minStackSize
        }

        return max(min(processor.originalFrameCount, maxAllowedStackSize), minStackSize)
    }

    private var canUseCompositeFrames: Bool {
        processor.compositeFrameCount > 0 &&
            (processor.recommendedStackingStartFrame == nil ||
                processor.recommendedStackingStartFrame == effectiveStackingStartFrame)
    }

    private var effectiveStackingStartFrame: Int {
        if usesAutomaticStackingStart, let frame = processor.recommendedStackingStartFrame {
            return frame
        }

        return min(max(Int(stackingStartFrame), 1), max(processor.originalFrameCount, 1))
    }

    private var videoDuration: Double {
        guard fps > 0 else { return 0 }
        return Double(outputFrameCount) / fps
    }

    var body: some View {
        contentWithLifecycle
    }

    private var content: some View {
        List {
            captureSection
            stackingSection
            videoSection
            renderSection
            clipsSection
            deleteProjectSection
        }
    }

    private var contentWithLifecycle: some View {
        contentWithSheets
            .task {
                processor.reload()
                applyRecommendedStackingStartIfNeeded()
                clampStackSize()
            }
            .onChange(of: processor.originalFrameCount) {
                clampStackSize()
                clampStackingStartFrame()
            }
            .onChange(of: processor.recommendedStackingStartFrame) {
                applyRecommendedStackingStartIfNeeded()
            }
    }

    private var contentWithSheets: some View {
        contentWithAlerts
            .sheet(item: $previewItem) { item in
                AstroClipPreview(url: item.url)
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url])
            }
    }

    private var contentWithAlerts: some View {
        contentWithDialogs
            .alert("Nao foi possivel excluir", isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteErrorMessage ?? "")
            }
            .alert("Nao foi possivel compartilhar", isPresented: Binding(
                get: { shareErrorMessage != nil },
                set: { if !$0 { shareErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(shareErrorMessage ?? "")
            }
    }

    private var contentWithDialogs: some View {
        contentWithOverlay
            .confirmationDialog(
                "Excluir este projeto?",
                isPresented: $isConfirmingProjectDelete,
                titleVisibility: .visible
            ) {
                Button("Excluir projeto", role: .destructive) {
                    deleteProject()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Essa acao apaga todas as imagens e nao pode ser desfeita.")
            }
            .confirmationDialog(
                "Excluir este clipe?",
                isPresented: $isConfirmingClipDelete,
                titleVisibility: .visible
            ) {
                Button("Excluir clipe", role: .destructive) {
                    if let pendingClipDelete {
                        deleteClip(pendingClipDelete)
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Remove o MP4, os frames processados e o manifest deste render.")
            }
    }

    private var contentWithOverlay: some View {
        content
            .navigationTitle("Processo astro")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if processor.isRendering {
                    AstroProcessingOverlay(
                        status: processor.status,
                        progressText: processor.progressText
                    )
                }
            }
    }

    private var captureSection: some View {
        Section("Captura") {
            LabeledContent("Fotos originais", value: "\(processor.originalFrameCount)")
            if processor.compositeFrameCount > 0 {
                LabeledContent("Frames bons", value: "\(processor.compositeFrameCount)")
            }
            LabeledContent("Sessao", value: session.name)
        }
    }

    private var stackingSection: some View {
        Section("Stacking") {
            stackingStartControls

            if canUseCompositeFrames {
                Text("Esta sessao ja tem frames bons gerados por lote. Se o inicio automatico for mantido, o clipe reutiliza esses frames.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Imagens por stack")
                        Spacer()
                        Text("\(min(max(Int(stackSize), minStackSize), maxStackSize))")
                            .font(.system(.body, design: .monospaced, weight: .semibold))
                    }

                    if processor.originalFrameCount >= minStackSize {
                        Slider(value: $stackSize, in: Double(minStackSize)...Double(maxStackSize), step: 1)
                    } else {
                        Text("Capture pelo menos 5 fotos para escolher um tamanho de stack.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            LabeledContent("Frames processados", value: "\(outputFrameCount)")
        }
    }

    private var stackingStartControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $usesAutomaticStackingStart) {
                Text("Inicio automatico")
            }

            LabeledContent("Comecar no frame", value: "\(effectiveStackingStartFrame)")

            if usesAutomaticStackingStart {
                Text(processor.recommendedStackingStartFrame == nil
                    ? "Sem marco automatico salvo; usando o primeiro frame."
                    : "Detectado pela captura/EXIF perto de 1s.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if processor.originalFrameCount > 1 {
                Slider(
                    value: $stackingStartFrame,
                    in: 1...Double(processor.originalFrameCount),
                    step: 1
                )
            }
        }
        .onChange(of: usesAutomaticStackingStart) {
            applyRecommendedStackingStartIfNeeded()
        }
    }

    private var videoSection: some View {
        Section("Video") {
            Picker("Processamento", selection: $processingProfile) {
                ForEach(AstroProcessingProfile.allCases) { profile in
                    Text(profile.title).tag(profile)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("FPS")
                    Spacer()
                    Text("\(Int(fps))")
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                }
                Slider(value: $fps, in: 1...60, step: 1)
            }

            LabeledContent("Duracao estimada", value: String(format: "%.1fs", videoDuration))
        }
    }

    private var renderSection: some View {
        Section {
            Button {
                Task {
                    await processor.renderStacks(
                        stackSize: Int(stackSize),
                        fps: Int(fps),
                        profile: processingProfile,
                        stackingStartFrame: effectiveStackingStartFrame
                    )
                }
            } label: {
                Label(processor.isRendering ? "Processando..." : renderButtonTitle, systemImage: "sparkles")
            }
            .disabled(processor.isRendering || outputFrameCount == 0)

            if let lastVideoURL = processor.lastVideoURL {
                Button {
                    openVideo(lastVideoURL)
                } label: {
                    Label("Abrir clipe astro", systemImage: "play.rectangle")
                }
                .disabled(processor.isRendering)

                Button {
                    shareVideo(lastVideoURL)
                } label: {
                    Label("Compartilhar clipe astro", systemImage: "square.and.arrow.up")
                }
                .disabled(processor.isRendering)
            }

            if let lastRenderURL = processor.lastRenderURL {
                LabeledContent("Ultimo render", value: lastRenderURL.lastPathComponent)
                    .font(.footnote)
            }

            Button("Concluir") {
                onComplete()
                dismiss()
            }
            .disabled(processor.isRendering)
        } footer: {
            Text(processor.status)
        }
    }

    private var clipsSection: some View {
        Section("Clipes criados") {
            AstroClipList(
                clips: processor.renderedClips,
                open: openVideo,
                share: shareVideo,
                delete: { clip in
                    pendingClipDelete = clip
                    isConfirmingClipDelete = true
                }
            )
        }
    }

    private var deleteProjectSection: some View {
        Section {
            Button(role: .destructive) {
                isConfirmingProjectDelete = true
            } label: {
                Label("Excluir projeto", systemImage: "trash")
            }
            .disabled(processor.isRendering)
        } footer: {
            Text("Remove este projeto e todas as imagens, sessoes, renders e exports dentro dele.")
        }
    }

    private func clampStackSize() {
        let upper = maxStackSize
        stackSize = Double(min(max(Int(stackSize), minStackSize), upper))

        if processor.originalFrameCount >= minStackSize {
            stackSize = Double(min(10, upper))
        }
    }

    private func clampStackingStartFrame() {
        stackingStartFrame = Double(min(
            max(Int(stackingStartFrame), 1),
            max(processor.originalFrameCount, 1)
        ))
    }

    private func applyRecommendedStackingStartIfNeeded() {
        guard usesAutomaticStackingStart else {
            clampStackingStartFrame()
            return
        }

        stackingStartFrame = Double(processor.recommendedStackingStartFrame ?? 1)
        clampStackingStartFrame()
    }

    private var renderButtonTitle: String {
        processor.compositeFrameCount > 0 ? "Gerar clipe dos frames bons" : "Iniciar processo astro"
    }

    private func openVideo(_ url: URL) {
        guard validateVideo(url) else { return }
        previewItem = AstroClipItem(url: url)
    }

    private func shareVideo(_ url: URL) {
        guard validateVideo(url) else { return }
        shareItem = AstroClipItem(url: url)
    }

    private func validateVideo(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            shareErrorMessage = "Arquivo do clipe nao encontrado. Gere o processo astro novamente."
            processor.reload()
            return false
        }

        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) > 0 else {
                shareErrorMessage = "O clipe astro esta vazio. Gere o processo novamente."
                processor.reload()
                return false
            }
        } catch {
            shareErrorMessage = "Nao foi possivel validar o clipe antes de compartilhar."
            return false
        }

        return true
    }

    private func deleteProject() {
        do {
            try onDeleteProject()
            dismiss()
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }

    private func deleteClip(_ clip: AstroRenderedClip) {
        do {
            try processor.deleteClip(clip)
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }
}

private struct AstroClipItem: Identifiable {
    let url: URL

    var id: String {
        url.path
    }
}

private struct AstroClipPreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VideoPlayer(player: AVPlayer(url: url))
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(url.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("OK") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

private struct AstroClipList: View {
    let clips: [AstroRenderedClip]
    let open: (URL) -> Void
    let share: (URL) -> Void
    let delete: (AstroRenderedClip) -> Void

    var body: some View {
        if clips.isEmpty {
            Text("Nenhum clipe ainda")
                .foregroundStyle(.secondary)
        } else {
            ForEach(clips) { clip in
                AstroClipRow(
                    clip: clip,
                    open: open,
                    share: share,
                    delete: delete
                )
            }
        }
    }
}

private struct AstroClipRow: View {
    let clip: AstroRenderedClip
    let open: (URL) -> Void
    let share: (URL) -> Void
    let delete: (AstroRenderedClip) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(clip.title)
                    .font(.headline)
                Text(clip.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                open(clip.videoURL)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderless)

            Button {
                share(clip.videoURL)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
            }
            .buttonStyle(.borderless)

            Button(role: .destructive) {
                delete(clip)
            } label: {
                Image(systemName: "trash")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            open(clip.videoURL)
        }
        .swipeActions {
            Button(role: .destructive) {
                delete(clip)
            } label: {
                Label("Excluir", systemImage: "trash")
            }
        }
    }
}

private struct AstroProcessingOverlay: View {
    let status: String
    let progressText: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)

                Text("Processando")
                    .font(.headline)

                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let progressText {
                    Text(progressText)
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: 280)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(radius: 18)
        }
        .allowsHitTesting(true)
    }
}

@MainActor
final class AstroProcessingController: ObservableObject {
    @Published private(set) var originalFrameCount = 0
    @Published private(set) var compositeFrameCount = 0
    @Published private(set) var status = "Pronto para processar"
    @Published private(set) var isRendering = false
    @Published private(set) var lastRenderURL: URL?
    @Published private(set) var lastVideoURL: URL?
    @Published private(set) var renderedClips: [AstroRenderedClip] = []
    @Published private(set) var currentStack = 0
    @Published private(set) var totalStacks = 0
    @Published private(set) var recommendedStackingStartFrame: Int?

    private let session: TimelapseSession
    private let fileManager = FileManager.default

    init(session: TimelapseSession) {
        self.session = session
    }

    func reload() {
        let frames = originalFrames()
        originalFrameCount = frames.count
        compositeFrameCount = compositeFrames().count
        recommendedStackingStartFrame = recommendedStackingStartFrame(in: frames)
        renderedClips = renderClips()
        lastVideoURL = renderedClips.first?.videoURL
        lastRenderURL = renderedClips.first?.renderURL
    }

    var progressText: String? {
        guard isRendering, totalStacks > 0 else { return nil }
        return "\(currentStack)/\(totalStacks)"
    }

    func outputFrameCount(stackSize: Int, stackingStartFrame: Int) -> Int {
        let startIndex = min(max(stackingStartFrame, 1), max(originalFrameCount, 1))
        let preStackFrameCount = max(startIndex - 1, 0)

        let canUsePrecomputedFrames = compositeFrameCount > 0 &&
            (recommendedStackingStartFrame == nil || recommendedStackingStartFrame == startIndex)

        if canUsePrecomputedFrames {
            return preStackFrameCount + compositeFrameCount
        }

        let size = min(max(stackSize, 5), 30)
        let stackableFrameCount = max(originalFrameCount - preStackFrameCount, 0)
        return preStackFrameCount + (stackableFrameCount / size)
    }

    func deleteClip(_ clip: AstroRenderedClip) throws {
        guard isSafeRenderDirectory(clip.renderURL) else {
            throw AstroRenderStoreError.unsafeRenderPath
        }

        if fileManager.fileExists(atPath: clip.renderURL.path) {
            try fileManager.removeItem(at: clip.renderURL)
        }

        reload()
    }

    func renderStacks(stackSize: Int, fps: Int, profile: AstroProcessingProfile, stackingStartFrame: Int) async {
        let size = min(max(stackSize, 5), 30)
        let precomputedFrames = compositeFrames()
        let originalFrames = originalFrames()
        let startIndex = min(max(stackingStartFrame, 1), max(originalFrames.count, 1))
        let preStackFrames = Array(originalFrames.prefix(max(startIndex - 1, 0)))
        let stackSourceFrames = Array(originalFrames.dropFirst(max(startIndex - 1, 0)))
        let canUsePrecomputedFrames = !precomputedFrames.isEmpty &&
            (recommendedStackingStartFrame == nil || recommendedStackingStartFrame == startIndex)
        let frames = canUsePrecomputedFrames ? precomputedFrames : stackSourceFrames
        guard !originalFrames.isEmpty, (!frames.isEmpty || !preStackFrames.isEmpty) else {
            status = "Capture pelo menos \(size) frames para processar"
            return
        }

        isRendering = true
        status = "Preparando render"
        currentStack = 0
        totalStacks = 0

        do {
            let renderURL = try createRenderDirectory(stackSize: size, fps: fps, profile: profile)
            let groups = canUsePrecomputedFrames ? [] : frames.chunked(into: size).filter { $0.count == size }
            let expectedFrames = preStackFrames.count + (canUsePrecomputedFrames ? precomputedFrames.count : groups.count)

            totalStacks = expectedFrames
            status = canUsePrecomputedFrames
                ? "Gerando clipe com \(precomputedFrames.count) frames bons"
                : "Processando \(groups.count) stacks (\(profile.title))"
            let profileTitle = profile.title
            let progress: @Sendable (Int, Int) async -> Void = { [weak self, profileTitle] current, total in
                await self?.updateRenderProgress(
                    current: current,
                    total: total,
                    profileTitle: profileTitle
                )
            }
            let result: AstroRenderResult
            if canUsePrecomputedFrames {
                result = try await AstroRenderWorker.renderPrecomputedFrames(
                    precomputedFrames,
                    preStackFrames: preStackFrames,
                    renderURL: renderURL,
                    fps: fps,
                    progress: progress
                )
            } else {
                result = try await AstroRenderWorker.render(
                    groups: groups,
                    preStackFrames: preStackFrames,
                    renderURL: renderURL,
                    fps: fps,
                    profile: profile,
                    progress: progress
                )
            }

            try writeRenderManifest(
                renderURL: renderURL,
                stackSize: size,
                fps: fps,
                profile: profile,
                stackingStartFrame: startIndex,
                outputFrames: result.outputFrames,
                retainedSourceFrames: result.retainedSourceFrames,
                videoURL: result.videoURL
            )
            lastRenderURL = renderURL
            lastVideoURL = result.videoURL
            status = "Clipe astro pronto: \(result.outputFrames) frames"
        } catch {
            status = "Falha no processo: \(error.localizedDescription)"
        }

        isRendering = false
        currentStack = 0
        totalStacks = 0
        reload()
    }

    private func updateRenderProgress(current: Int, total: Int, profileTitle: String) {
        currentStack = current
        totalStacks = total
        status = "Stack \(current)/\(total) (\(profileTitle))"
    }

    private func originalFrames() -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: session.directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return []
        }

        return files
            .filter { url in
                url.lastPathComponent.hasPrefix("frame_") &&
                url.pathExtension.lowercased() == "jpg" &&
                ((try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func compositeFrames() -> [URL] {
        let directoryURL = session.directoryURL.appendingPathComponent("Astro Frames", isDirectory: true)
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return []
        }

        return files
            .filter { url in
                url.lastPathComponent.hasPrefix("astro_frame_") &&
                url.pathExtension.lowercased() == "jpg" &&
                ((try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func recommendedStackingStartFrame(in frames: [URL]) -> Int? {
        if let frame = storedStackingStartFrame() {
            return min(max(frame, 1), max(frames.count, 1))
        }

        return frames.enumerated().first { _, frameURL in
            exposureSeconds(in: frameURL) >= 0.8
        }.map { index, _ in
            index + 1
        }
    }

    private func storedStackingStartFrame() -> Int? {
        let metadataURL = session.directoryURL.appendingPathComponent("astro_capture.json")
        guard
            let data = try? Data(contentsOf: metadataURL),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return object["stackingStartFrame"] as? Int
    }

    private func exposureSeconds(in frameURL: URL) -> Double {
        guard
            let source = CGImageSourceCreateWithURL(frameURL as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
            let exposure = exif[kCGImagePropertyExifExposureTime] as? Double
        else {
            return 0
        }

        return exposure
    }

    private func createRenderDirectory(stackSize: Int, fps: Int, profile: AstroProcessingProfile) throws -> URL {
        let rendersURL = session.directoryURL.appendingPathComponent("Astro Renders", isDirectory: true)
        try fileManager.createDirectory(at: rendersURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"

        let name = "stack_\(stackSize)_fps_\(fps)_\(profile.rawValue)_\(formatter.string(from: Date()))"
        let renderURL = rendersURL.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: renderURL, withIntermediateDirectories: true)
        return renderURL
    }

    private func renderClips() -> [AstroRenderedClip] {
        let rendersURL = session.directoryURL.appendingPathComponent("Astro Renders", isDirectory: true)
        guard let renderDirectories = try? fileManager.contentsOfDirectory(
            at: rendersURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey]
        ) else {
            return []
        }

        return renderDirectories.compactMap { renderURL -> AstroRenderedClip? in
            let isDirectory = (try? renderURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            guard isDirectory else { return nil }

            let videoURL = renderURL.appendingPathComponent("astro.mp4")
            guard fileManager.fileExists(atPath: videoURL.path) else { return nil }

            let modifiedAt = (try? renderURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let videoBytes = (try? videoURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let manifest = renderManifest(at: renderURL)

            return AstroRenderedClip(
                renderURL: renderURL,
                videoURL: videoURL,
                modifiedAt: modifiedAt,
                profile: manifest["processingProfile"] as? String,
                outputFrames: manifest["outputFrameCount"] as? Int,
                fps: manifest["fps"] as? Int,
                stackSize: manifest["stackSize"] as? Int,
                videoBytes: videoBytes
            )
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func renderManifest(at renderURL: URL) -> [String: Any] {
        let manifestURL = renderURL.appendingPathComponent("render.json")
        guard
            let data = try? Data(contentsOf: manifestURL),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }

        return object
    }

    private func isSafeRenderDirectory(_ renderURL: URL) -> Bool {
        let rendersURL = session.directoryURL.appendingPathComponent("Astro Renders", isDirectory: true)
        let renderPath = renderURL.standardizedFileURL.path
        let rendersPath = rendersURL.standardizedFileURL.path

        guard renderPath.hasPrefix(rendersPath + "/") else {
            return false
        }

        guard renderURL.lastPathComponent.hasPrefix("stack_") else {
            return false
        }

        return true
    }

    private func writeRenderManifest(
        renderURL: URL,
        stackSize: Int,
        fps: Int,
        profile: AstroProcessingProfile,
        stackingStartFrame: Int,
        outputFrames: Int,
        retainedSourceFrames: Int,
        videoURL: URL
    ) throws {
        var manifest: [String: Any] = [
            "sourceSessionId": session.id.uuidString,
            "sourceFrameCount": originalFrameCount,
            "stackingStartFrame": stackingStartFrame,
            "stackSize": stackSize,
            "fps": fps,
            "processingProfile": profile.rawValue,
            "retainedSourceFrames": retainedSourceFrames,
            "outputFrameCount": outputFrames,
            "estimatedVideoDuration": fps > 0 ? Double(outputFrames) / Double(fps) : 0,
            "videoFile": videoURL.lastPathComponent
        ]

        if let size = try? videoURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            manifest["videoBytes"] = size
        }

        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: renderURL.appendingPathComponent("render.json"), options: [.atomic])
    }
}

private struct AstroRenderResult {
    let outputFrames: Int
    let retainedSourceFrames: Int
    let videoURL: URL
}

struct AstroRenderedClip: Identifiable {
    let renderURL: URL
    let videoURL: URL
    let modifiedAt: Date
    let profile: String?
    let outputFrames: Int?
    let fps: Int?
    let stackSize: Int?
    let videoBytes: Int

    var id: String {
        videoURL.path
    }

    var title: String {
        profileTitle.map { "Clipe \($0)" } ?? "Clipe astro"
    }

    var subtitle: String {
        var parts = [Self.dateFormatter.string(from: modifiedAt)]

        if let outputFrames {
            parts.append("\(outputFrames) frames")
        }

        if let fps {
            parts.append("\(fps) fps")
        }

        if let stackSize {
            parts.append("stack \(stackSize)")
        }

        if videoBytes > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(videoBytes), countStyle: .file))
        }

        return parts.joined(separator: " · ")
    }

    private var profileTitle: String? {
        guard let profile else { return nil }
        return AstroProcessingProfile(rawValue: profile)?.title ?? profile
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

enum AstroRenderStoreError: LocalizedError {
    case unsafeRenderPath

    var errorDescription: String? {
        switch self {
        case .unsafeRenderPath:
            return "caminho de render invalido"
        }
    }
}

private enum AstroRenderWorker {
    static func render(
        groups: [[URL]],
        preStackFrames: [URL],
        renderURL: URL,
        fps: Int,
        profile: AstroProcessingProfile,
        progress: @escaping @Sendable (Int, Int) async -> Void
    ) async throws -> AstroRenderResult {
        try await Task.detached(priority: .userInitiated) {
            let stacker = ExposureStacker()
            var outputFrameURLs: [URL] = []
            outputFrameURLs.reserveCapacity(preStackFrames.count + groups.count)
            var retainedSourceFrames = preStackFrames.count

            for (index, frameURL) in preStackFrames.enumerated() {
                try Task.checkCancellation()
                let outputURL = renderURL.appendingPathComponent(String(format: "stack_%06d.jpg", index + 1))
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                try FileManager.default.copyItem(at: frameURL, to: outputURL)
                outputFrameURLs.append(outputURL)
                await progress(outputFrameURLs.count, preStackFrames.count + groups.count)
            }

            for group in groups {
                try Task.checkCancellation()
                let preferredFrames = stacker.preferredFrames(group, maxDimension: 1920, profile: profile)
                retainedSourceFrames += preferredFrames.count

                let data = try autoreleasepool {
                    try stacker.averageJPEGFiles(
                        preferredFrames,
                        maxDimension: 1920,
                        profile: profile
                    )
                }
                let outputURL = renderURL.appendingPathComponent(String(format: "stack_%06d.jpg", outputFrameURLs.count + 1))
                try data.write(to: outputURL, options: [.atomic])
                outputFrameURLs.append(outputURL)
                await progress(outputFrameURLs.count, preStackFrames.count + groups.count)
            }

            let videoURL = renderURL.appendingPathComponent("astro.mp4")
            await progress(outputFrameURLs.count, outputFrameURLs.count)
            try await TimelapseVideoRenderer().render(frames: outputFrameURLs, outputURL: videoURL, fps: fps)
            return AstroRenderResult(
                outputFrames: outputFrameURLs.count,
                retainedSourceFrames: retainedSourceFrames,
                videoURL: videoURL
            )
        }.value
    }

    static func renderPrecomputedFrames(
        _ frames: [URL],
        preStackFrames: [URL],
        renderURL: URL,
        fps: Int,
        progress: @escaping @Sendable (Int, Int) async -> Void
    ) async throws -> AstroRenderResult {
        try await Task.detached(priority: .userInitiated) {
            var outputFrameURLs: [URL] = []
            outputFrameURLs.reserveCapacity(preStackFrames.count + frames.count)
            let totalFrames = preStackFrames.count + frames.count

            for frameURL in preStackFrames + frames {
                try Task.checkCancellation()

                let outputURL = renderURL.appendingPathComponent(String(format: "stack_%06d.jpg", outputFrameURLs.count + 1))
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                try FileManager.default.copyItem(at: frameURL, to: outputURL)
                outputFrameURLs.append(outputURL)
                await progress(outputFrameURLs.count, totalFrames)
            }

            let videoURL = renderURL.appendingPathComponent("astro.mp4")
            await progress(outputFrameURLs.count, outputFrameURLs.count)
            try await TimelapseVideoRenderer().render(frames: outputFrameURLs, outputURL: videoURL, fps: fps)
            return AstroRenderResult(
                outputFrames: outputFrameURLs.count,
                retainedSourceFrames: totalFrames,
                videoURL: videoURL
            )
        }.value
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        let chunkSize = Swift.max(size, 1)
        return stride(from: 0, to: count, by: chunkSize).map {
            Array(self[$0..<Swift.min($0 + chunkSize, count)])
        }
    }
}

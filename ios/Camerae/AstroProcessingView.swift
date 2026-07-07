import AVKit
import ImageIO
import SwiftUI

private enum AstroProcessTab: String, CaseIterable, Identifiable {
    case capture
    case create
    case video
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture:
            return "Captura"
        case .create:
            return "Criar"
        case .video:
            return "Video"
        case .files:
            return "Arquivos"
        }
    }

    var systemImage: String {
        switch self {
        case .capture:
            return "camera"
        case .create:
            return "sparkles"
        case .video:
            return "play.rectangle"
        case .files:
            return "externaldrive"
        }
    }
}

struct AstroProcessingView: View {
    let session: TimelapseSession
    let onComplete: () -> Void
    let onDeleteProject: () throws -> Void

    @StateObject private var processor: AstroProcessingController
    @State private var stackSize = 10.0
    @State private var fps = 24.0
    @State private var processingSettings = AstroImageProcessingSettings.defaults(for: .natural)
    @State private var usesAutomaticStackingStart = true
    @State private var usesPrecomputedAstroFrames = false
    @State private var rejectsBlurredFrames = false
    @State private var preservesTimelineDuration = true
    @State private var stackingStartFrame = 1.0
    @State private var isConfirmingProjectDelete = false
    @State private var previewItem: AstroClipItem?
    @State private var shareItem: AstroShareItem?
    @State private var isShowingImageLab = false
    @State private var isShowingFrameCuration = false
    @State private var exportedArchiveURLs: [URL] = []
    @State private var isShowingExportedArchives = false
    @State private var exportTask: Task<Void, Never>?
    @State private var pendingClipDelete: AstroRenderedClip?
    @State private var isConfirmingClipDelete = false
    @State private var shareErrorMessage: String?
    @State private var deleteErrorMessage: String?
    @State private var selectedTab = AstroProcessTab.capture
    @Environment(\.dismiss) private var dismiss

    private let minStackSize = 2
    private let maxAllowedStackSize = 120

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
            stackingStartFrame: effectiveStackingStartFrame,
            usesPrecomputedFrames: usesPrecomputedAstroFrames,
            preservesTimelineDuration: preservesTimelineDuration
        )
    }

    private var maxStackSize: Int {
        return max(min(processor.originalFrameCount, maxAllowedStackSize), minStackSize)
    }

    private var canUseCompositeFrames: Bool {
        processor.compositeFrameCount > 0 &&
            processor.rejectedOriginalFrameCount == 0 &&
            usesPrecomputedAstroFrames &&
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
        VStack(spacing: 0) {
            Picker("Area", selection: $selectedTab) {
                ForEach(AstroProcessTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.regularMaterial)

            List {
                switch selectedTab {
                case .capture:
                    captureSection
                    clipsSection
                case .create:
                    stackingSection
                    imageSettingsSection
                    latestProcessedFrameSection
                case .video:
                    videoSection
                case .files:
                    storageSection
                    maintenanceSection
                    deleteProjectSection
                }
            }
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
                ShareSheet(items: item.urls)
            }
            .sheet(isPresented: $isShowingExportedArchives) {
                if !exportedArchiveURLs.isEmpty {
                    ExportedArchivesView(urls: exportedArchiveURLs)
                }
            }
            .sheet(isPresented: $isShowingImageLab) {
                AstroImageLabView(
                    processor: processor,
                    initialStackSize: Int(stackSize),
                    initialStackingStartFrame: effectiveStackingStartFrame,
                    initialSettings: processingSettings
                ) { selectedStackSize, selectedSettings in
                    stackSize = Double(selectedStackSize)
                    processingSettings = selectedSettings
                }
            }
            .sheet(isPresented: $isShowingFrameCuration) {
                AstroFrameCurationView(processor: processor)
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
                    BlockingProgressOverlay(
                        title: "Processando",
                        message: processor.status,
                        detail: processor.progressText
                    )
                } else if processor.isExportingOriginalFrames {
                    BlockingProgressOverlay(
                        title: "Exportando ZIP",
                        message: processor.status,
                        detail: processor.originalFrameExportProgress?.detailText ?? "Preparando",
                        cancelTitle: "Parar",
                        cancelAction: {
                            exportTask?.cancel()
                        }
                    )
                }
            }
    }

    private var captureSection: some View {
        Section("Captura") {
            LabeledContent("Fotos originais", value: "\(processor.totalOriginalFrameCount)")
            if processor.rejectedOriginalFrameCount > 0 {
                LabeledContent("Ignoradas", value: "\(processor.rejectedOriginalFrameCount)")
                LabeledContent("Ativas", value: "\(processor.originalFrameCount)")
            }
            if processor.compositeFrameCount > 0 {
                LabeledContent("Frames bons", value: "\(processor.compositeFrameCount)")
            }
            LabeledContent("Sessao", value: session.name)

            Button {
                isShowingFrameCuration = true
            } label: {
                Label("Revisar frames", systemImage: "rectangle.grid.3x2")
            }
            .disabled(processor.isRendering || processor.isExportingOriginalFrames || processor.totalOriginalFrameCount == 0)
        }
    }

    private var stackingSection: some View {
        Section("Stacking e frames") {
            stackingStartControls
            precomputedFrameControls

            if canUseCompositeFrames {
                Text("Esta sessao tem frames bons gerados por lote. Eles serao reutilizados sem reprocessar os originais.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(canUseCompositeFrames ? "Frames por frame pronto" : "Imagens por lote")
                    Spacer()
                    Text("\(min(max(Int(stackSize), minStackSize), maxStackSize))")
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                }

                if processor.originalFrameCount >= minStackSize {
                    Slider(value: $stackSize, in: Double(minStackSize)...Double(maxStackSize), step: 1)
                } else {
                    Text("Capture pelo menos 2 fotos para escolher o tamanho do lote.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                isShowingFrameCuration = true
            } label: {
                Label("Revisar frames", systemImage: "rectangle.grid.3x2")
            }
            .disabled(processor.isRendering || processor.isExportingOriginalFrames || processor.totalOriginalFrameCount == 0)

            LabeledContent("Frames processados", value: "\(outputFrameCount)")
        }
    }

    private var imageSettingsSection: some View {
        Section("Imagem de referencia") {
            Picker("Backend", selection: Binding(
                get: { processingSettings.stackingBackend },
                set: { updateProcessingBackend($0) }
            )) {
                ForEach(AstroStackingBackend.allCases) { backend in
                    Text(backend.title).tag(backend)
                }
            }
            .pickerStyle(.segmented)

            LabeledContent("Ruido", value: processingSettings.appliesDenoise ? processingSettings.denoiseBackend.title : "Off")

            Button {
                isShowingImageLab = true
            } label: {
                Label("Editar preview e ajustes", systemImage: "slider.horizontal.3")
            }
            .disabled(processor.isRendering || processor.isExportingOriginalFrames || processor.originalFrameCount == 0)
        }
    }

    private var latestProcessedFrameSection: some View {
        Section("Ultimo frame processado") {
            if let clip = processor.renderedClips.first,
               let frameURL = clip.processedFrameURL {
                AstroProcessedFramePreview(frameURL: frameURL)

                Text(clip.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ContentUnavailableView("Nenhum frame processado", systemImage: "photo")
            }
        }
    }

    private var precomputedFrameControls: some View {
        Group {
            if processor.compositeFrameCount > 0 {
                Toggle(isOn: $usesPrecomputedAstroFrames) {
                    Text("Usar frames bons prontos")
                }

                if !usesPrecomputedAstroFrames {
                    Text("Desligado: o app reprocessa as fotos originais e permite gerar outro clipe com outro numero de stack.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
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
        Section(content: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("FPS")
                    Spacer()
                    Text("\(Int(fps))")
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                }
                Slider(value: $fps, in: 1...60, step: 1)
            }

            Toggle(isOn: $preservesTimelineDuration) {
                Text("Preservar duracao")
            }

            LabeledContent("Duracao estimada", value: String(format: "%.1fs", videoDuration))

            Button {
                Task {
                    await processor.renderStacks(
                        stackSize: Int(stackSize),
                        fps: Int(fps),
                        settings: processingSettings,
                        stackingStartFrame: effectiveStackingStartFrame,
                        usesPrecomputedFrames: usesPrecomputedAstroFrames,
                        rejectsBlurredFrames: false,
                        preservesTimelineDuration: preservesTimelineDuration
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
        }, header: {
            Text("Editar e criar video")
        }, footer: {
            Text(processor.status)
        })
    }

    private var storageSection: some View {
        let summary = processor.storageSummary
        return Section("Arquivos criados") {
            LabeledContent("Frames capturados", value: ByteCountFormatter.string(fromByteCount: Int64(summary.originalBytes), countStyle: .file))
            LabeledContent("Frames processados", value: ByteCountFormatter.string(fromByteCount: Int64(summary.processedFrameBytes), countStyle: .file))
            LabeledContent("Videos criados", value: ByteCountFormatter.string(fromByteCount: Int64(summary.videoBytes), countStyle: .file))
            LabeledContent("Cache", value: ByteCountFormatter.string(fromByteCount: Int64(summary.cacheBytes), countStyle: .file))
            LabeledContent("Total", value: ByteCountFormatter.string(fromByteCount: Int64(summary.totalBytes), countStyle: .file))
        }
    }

    private var maintenanceSection: some View {
        Section(content: {
            Button(role: .destructive) {
                clearProcessingCache()
            } label: {
                Label("Limpar cache processado", systemImage: "trash")
            }
            .disabled(processor.isRendering || processor.isExportingOriginalFrames || !processor.storageSummary.hasProcessingCache)

            Button {
                exportTask = Task {
                    await exportOriginalFrames()
                    exportTask = nil
                }
            } label: {
                Label(
                    processor.isExportingOriginalFrames ? "Exportando..." : "Exportar frames originais",
                    systemImage: "photo.stack"
                )
            }
            .disabled(processor.isRendering || processor.isExportingOriginalFrames || processor.originalFrameCount == 0)

            Button("Concluir") {
                onComplete()
                dismiss()
            }
            .disabled(processor.isRendering || processor.isExportingOriginalFrames)
        }, header: {
            Text("Manutencao")
        }, footer: {
            Text("Exportar originais fica separado porque pode demorar bastante. Limpar cache remove previews e frames bons pre-processados, mas nao apaga fotos originais nem clipes renderizados.")
        })
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

    private func updateProcessingBackend(_ backend: AstroStackingBackend) {
        processingSettings.stackingBackend = backend
        switch backend {
        case .coreImage:
            processingSettings.alignsStars = false
        case .openCV:
            processingSettings.alignsStars = processingSettings.profile.alignsStars
        }
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
        shareItem = AstroShareItem(urls: [url])
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

    private func exportOriginalFrames() async {
        do {
            exportedArchiveURLs = try await processor.exportOriginalFramesArchives()
            isShowingExportedArchives = !exportedArchiveURLs.isEmpty
        } catch {
            shareErrorMessage = error.localizedDescription
        }
    }

    private func clearProcessingCache() {
        do {
            try processor.clearProcessingCache()
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

private struct AstroShareItem: Identifiable {
    let urls: [URL]

    var id: String {
        urls.map(\.path).joined(separator: "|")
    }
}

struct AstroOriginalFrameItem: Identifiable, Equatable {
    let index: Int
    let url: URL
    let isRejected: Bool

    var id: String { url.path }
    var fileName: String { url.lastPathComponent }
}

private struct AstroFrameCurationView: View {
    @ObservedObject var processor: AstroProcessingController
    @State private var selectedItem: AstroOriginalFrameItem?
    @State private var thumbnailSize = AstroFrameThumbnailSize.small
    @Environment(\.dismiss) private var dismiss

    private var items: [AstroOriginalFrameItem] {
        processor.originalFrameItems()
    }

    var body: some View {
        NavigationStack {
            AstroFrameCurationGrid(
                items: items,
                thumbnailSize: thumbnailSize,
                select: { selectedItem = $0 },
                toggleRejected: { item in
                    processor.setOriginalFrameRejected(item, isRejected: !item.isRejected)
                }
            )
            .navigationTitle("Revisar frames")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fechar") {
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Picker("Tamanho", selection: $thumbnailSize) {
                        ForEach(AstroFrameThumbnailSize.allCases) { size in
                            Image(systemName: size.systemImage).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 92)

                    Button {
                        processor.setAllOriginalFramesRejected(false)
                    } label: {
                        Label("Restaurar todos", systemImage: "checkmark.rectangle.stack")
                    }
                    .disabled(processor.rejectedOriginalFrameCount == 0)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Label("\(processor.originalFrameCount) ativos", systemImage: "checkmark.circle")
                    Spacer()
                    Label("\(processor.rejectedOriginalFrameCount) rejeitados", systemImage: "xmark.circle")
                }
                .font(.footnote)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial)
            }
            .fullScreenCover(item: $selectedItem) { item in
                AstroFrameDetailView(
                    initialItem: item,
                    items: items,
                    processor: processor
                )
            }
            .onAppear {
                processor.reload()
            }
        }
    }
}

private struct AstroFrameCurationGrid: View {
    let items: [AstroOriginalFrameItem]
    let thumbnailSize: AstroFrameThumbnailSize
    let select: (AstroOriginalFrameItem) -> Void
    let toggleRejected: (AstroOriginalFrameItem) -> Void

    private let spacing: CGFloat = 10

    private var rows: [[AstroOriginalFrameItem]] {
        stride(from: 0, to: items.count, by: thumbnailSize.columnCount).map { index in
            Array(items[index..<min(index + thumbnailSize.columnCount, items.count)])
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = thumbnailSize.cellWidth(availableWidth: proxy.size.width, spacing: spacing)

            ScrollView {
                VStack(spacing: spacing) {
                    ForEach(rows, id: \.rowID) { row in
                        AstroFrameCurationRow(
                            row: row,
                            thumbnailSize: thumbnailSize,
                            width: width,
                            spacing: spacing,
                            select: select,
                            toggleRejected: toggleRejected
                        )
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }
}

private struct AstroFrameCurationRow: View {
    let row: [AstroOriginalFrameItem]
    let thumbnailSize: AstroFrameThumbnailSize
    let width: CGFloat
    let spacing: CGFloat
    let select: (AstroOriginalFrameItem) -> Void
    let toggleRejected: (AstroOriginalFrameItem) -> Void

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(row) { item in
                AstroFrameThumbnailCell(
                    item: item,
                    size: thumbnailSize,
                    width: width,
                    toggleRejected: {
                        toggleRejected(item)
                    }
                )
                .onTapGesture {
                    select(item)
                }
            }

            ForEach(0..<max(thumbnailSize.columnCount - row.count, 0), id: \.self) { _ in
                Color.clear
                    .frame(width: width, height: 1)
            }
        }
    }
}

private extension Array where Element == AstroOriginalFrameItem {
    var rowID: String {
        map(\.id).joined(separator: "|")
    }
}

private enum AstroFrameThumbnailSize: String, CaseIterable, Identifiable {
    case small
    case large

    var id: String { rawValue }

    var columnCount: Int {
        switch self {
        case .small:
            return 3
        case .large:
            return 1
        }
    }

    var systemImage: String {
        switch self {
        case .small:
            return "square.grid.3x2"
        case .large:
            return "rectangle"
        }
    }

    var thumbnailPixelSize: Int {
        switch self {
        case .small:
            return 360
        case .large:
            return 900
        }
    }

    func cellWidth(availableWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        let horizontalPadding: CGFloat = 20
        let totalSpacing = CGFloat(max(columnCount - 1, 0)) * spacing
        return floor((availableWidth - horizontalPadding - totalSpacing) / CGFloat(columnCount))
    }
}

private struct AstroFrameThumbnailCell: View {
    let item: AstroOriginalFrameItem
    let size: AstroFrameThumbnailSize
    let width: CGFloat
    let toggleRejected: () -> Void
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .bottomLeading) {
                Rectangle()
                    .fill(.quaternary)

                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView()
                }

                Text("#\(item.index)")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.white)
                    .padding(5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                if item.isRejected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.black.opacity(0.48))
                    Image(systemName: "xmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                }
            }

            Button {
                toggleRejected()
            } label: {
                Image(systemName: item.isRejected ? "arrow.uturn.backward.circle.fill" : "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(item.isRejected ? .green : .red)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .frame(width: width, height: width * 4 / 3)
        .clipped()
        .contentShape(Rectangle())
        .task(id: "\(item.id)-\(size.rawValue)") {
            thumbnail = await AstroFrameThumbnailLoader.thumbnail(for: item.url, maxPixelSize: size.thumbnailPixelSize)
        }
    }
}

private struct AstroFrameDetailView: View {
    let initialItem: AstroOriginalFrameItem
    let items: [AstroOriginalFrameItem]
    @ObservedObject var processor: AstroProcessingController
    @State private var selectedID: String
    @Environment(\.dismiss) private var dismiss

    init(
        initialItem: AstroOriginalFrameItem,
        items: [AstroOriginalFrameItem],
        processor: AstroProcessingController
    ) {
        self.initialItem = initialItem
        self.items = items
        self.processor = processor
        _selectedID = State(initialValue: initialItem.id)
    }

    private var currentItem: AstroOriginalFrameItem {
        items.first { $0.id == selectedID } ?? initialItem
    }

    private var isRejected: Bool {
        processor.rejectedOriginalFrameNames.contains(currentItem.fileName)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedID) {
                ForEach(items) { item in
                    ZStack {
                        Color.black.ignoresSafeArea()
                        AstroCachedZoomableFrameView(url: item.url)
                    }
                    .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .background(.black)
            .navigationTitle("#\(currentItem.index)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Fechar", systemImage: "xmark")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        processor.setOriginalFrameRejected(currentItem, isRejected: !isRejected)
                    } label: {
                        Label(isRejected ? "Restaurar" : "Rejeitar", systemImage: isRejected ? "arrow.uturn.backward.circle" : "xmark.circle")
                    }
                }
            }
        }
    }
}

private struct AstroCachedZoomableFrameView: View {
    let url: URL
    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                AstroZoomableImageView(image: image)
                    .ignoresSafeArea(edges: .bottom)
            } else if didFail {
                ContentUnavailableView("Frame indisponivel", systemImage: "photo")
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .task(id: url.path) {
            didFail = false
            image = await ThumbnailCache.thumbnail(for: url, maxPixelSize: 1800)
            didFail = image == nil
        }
    }
}

private struct AstroZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .black
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 10
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scrollView

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = recognizer.location(in: imageView)
                let zoomScale = min(scrollView.maximumZoomScale, 3)
                let width = scrollView.bounds.width / zoomScale
                let height = scrollView.bounds.height / zoomScale
                scrollView.zoom(to: CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height), animated: true)
            }
        }
    }
}

private enum AstroFrameThumbnailLoader {
    static func thumbnail(for url: URL, maxPixelSize: Int) async -> UIImage? {
        await ThumbnailCache.thumbnail(for: url, maxPixelSize: maxPixelSize)
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

private struct AstroProcessedFramePreview: View {
    let frameURL: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.quaternary)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            Text(frameURL.lastPathComponent)
                .font(.caption2.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(.white)
                .padding(8)
        }
        .task(id: frameURL.path) {
            image = await ThumbnailCache.thumbnail(for: frameURL, maxPixelSize: 1400)
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
            ReferenceThumbnail(imageURL: clip.thumbnailURL, systemImage: "play.rectangle")

            VStack(alignment: .leading, spacing: 4) {
                Text(clip.title)
                    .font(.headline)

                Text(clip.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let technicalSummary = clip.technicalSummary {
                    Text(technicalSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let adjustmentSummary = clip.adjustmentSummary {
                    Text(adjustmentSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
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

struct AstroStorageSummary: Equatable {
    var originalBytes: UInt64 = 0
    var processedFrameBytes: UInt64 = 0
    var videoBytes: UInt64 = 0
    var cacheBytes: UInt64 = 0
    var hasProcessingCache = false

    var totalBytes: UInt64 {
        originalBytes + processedFrameBytes + videoBytes + cacheBytes
    }
}

@MainActor
final class AstroProcessingController: ObservableObject {
    @Published private(set) var totalOriginalFrameCount = 0
    @Published private(set) var originalFrameCount = 0
    @Published private(set) var compositeFrameCount = 0
    @Published private(set) var status = "Pronto para processar"
    @Published private(set) var isRendering = false
    @Published private(set) var isExportingOriginalFrames = false
    @Published private(set) var originalFrameExportProgress: OriginalFrameExportProgress?
    @Published private(set) var lastRenderURL: URL?
    @Published private(set) var lastVideoURL: URL?
    @Published private(set) var renderedClips: [AstroRenderedClip] = []
    @Published private(set) var currentStack = 0
    @Published private(set) var totalStacks = 0
    @Published private(set) var currentVideoFrame = 0
    @Published private(set) var totalVideoFrames = 0
    @Published private(set) var recommendedStackingStartFrame: Int?
    @Published private(set) var rejectedOriginalFrameNames: Set<String> = []
    @Published private(set) var storageSummary = AstroStorageSummary()

    var rejectedOriginalFrameCount: Int {
        rejectedOriginalFrameNames.count
    }

    private let session: TimelapseSession
    private let fileManager = FileManager.default

    init(session: TimelapseSession) {
        self.session = session
    }

    func reload() {
        rejectedOriginalFrameNames = loadRejectedOriginalFrameNames()
        totalOriginalFrameCount = allOriginalFrames().count
        let frames = originalFrames()
        originalFrameCount = frames.count
        compositeFrameCount = compositeFrames().count
        recommendedStackingStartFrame = recommendedStackingStartFrame(in: frames)
        renderedClips = renderClips()
        lastVideoURL = renderedClips.first?.videoURL
        lastRenderURL = renderedClips.first?.renderURL
        storageSummary = calculateStorageSummary()
    }

    var progressText: String? {
        guard isRendering else { return nil }

        if totalVideoFrames > 0 {
            let percent = Int((Double(currentVideoFrame) / Double(totalVideoFrames) * 100).rounded())
            return "Video \(min(max(percent, 0), 100))% (\(currentVideoFrame)/\(totalVideoFrames))"
        }

        var parts: [String] = []
        if totalStacks > 0 {
            parts.append("Stack \(currentStack)/\(totalStacks)")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    func originalFrameItems() -> [AstroOriginalFrameItem] {
        allOriginalFrames().enumerated().map { index, url in
            AstroOriginalFrameItem(
                index: index + 1,
                url: url,
                isRejected: rejectedOriginalFrameNames.contains(url.lastPathComponent)
            )
        }
    }

    func setOriginalFrameRejected(_ item: AstroOriginalFrameItem, isRejected: Bool) {
        if isRejected {
            rejectedOriginalFrameNames.insert(item.fileName)
        } else {
            rejectedOriginalFrameNames.remove(item.fileName)
        }

        saveRejectedOriginalFrameNames()
        reload()
    }

    func setAllOriginalFramesRejected(_ isRejected: Bool) {
        if isRejected {
            rejectedOriginalFrameNames = Set(allOriginalFrames().map(\.lastPathComponent))
        } else {
            rejectedOriginalFrameNames = []
        }

        saveRejectedOriginalFrameNames()
        reload()
    }

    func outputFrameCount(
        stackSize: Int,
        stackingStartFrame: Int,
        usesPrecomputedFrames: Bool,
        preservesTimelineDuration: Bool
    ) -> Int {
        let startIndex = min(max(stackingStartFrame, 1), max(originalFrameCount, 1))
        let preStackFrameCount = max(startIndex - 1, 0)
        let size = Self.clampedStackSize(stackSize)

        let canUsePrecomputedFrames = usesPrecomputedFrames &&
            rejectedOriginalFrameCount == 0 &&
            compositeFrameCount > 0 &&
            (recommendedStackingStartFrame == nil || recommendedStackingStartFrame == startIndex)

        if canUsePrecomputedFrames {
            let renderedFrames = preservesTimelineDuration ? compositeFrameCount * size : compositeFrameCount
            return preStackFrameCount + renderedFrames
        }

        let stackableFrameCount = max(originalFrameCount - preStackFrameCount, 0)
        let fullGroupCount = stackableFrameCount / size
        let remainderFrameCount = stackableFrameCount % size
        let stackGroupCount = fullGroupCount + (remainderFrameCount > 0 ? 1 : 0)
        let renderedStackFrames = preservesTimelineDuration ? stackableFrameCount : stackGroupCount
        return preStackFrameCount + renderedStackFrames
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

    func clearProcessingCache() throws {
        guard !isRendering, !isExportingOriginalFrames else {
            throw AstroRenderStoreError.renderAlreadyRunning
        }

        let cacheDirectories = [
            session.directoryURL.appendingPathComponent("Preview Frames", isDirectory: true),
            session.directoryURL.appendingPathComponent("Astro Frames", isDirectory: true),
            session.directoryURL.appendingPathComponent(ThumbnailCache.directoryName, isDirectory: true)
        ]

        for directory in cacheDirectories where fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }

        status = "Cache processado limpo"
        reload()
    }

    func exportOriginalFramesArchives() async throws -> [URL] {
        guard !isRendering, !isExportingOriginalFrames else {
            throw AstroRenderStoreError.renderAlreadyRunning
        }

        isExportingOriginalFrames = true
        originalFrameExportProgress = nil
        status = "Gerando ZIP com \(originalFrameCount) frames originais"

        do {
            let urls = try await TimelapseSessionStore.exportOriginalFramesArchivesInBackground(for: session) { [weak self] progress in
                await self?.updateOriginalFrameExportProgress(progress)
            }
            status = urls.count == 1
                ? "ZIP de originais pronto"
                : "ZIP de originais pronto (\(urls.count) partes)"
            isExportingOriginalFrames = false
            originalFrameExportProgress = nil
            return urls
        } catch is CancellationError {
            let urls = TimelapseSessionStore.existingOriginalFrameArchives(for: session)
            status = urls.isEmpty
                ? "Export cancelado"
                : "Export cancelado (\(urls.count) lotes prontos)"
            isExportingOriginalFrames = false
            originalFrameExportProgress = nil
            return urls
        } catch {
            status = "Falha no ZIP: \(error.localizedDescription)"
            isExportingOriginalFrames = false
            originalFrameExportProgress = nil
            throw error
        }
    }

    private func updateOriginalFrameExportProgress(_ progress: OriginalFrameExportProgress) {
        originalFrameExportProgress = progress
        status = progress.detailText
    }

    func renderStacks(
        stackSize: Int,
        fps: Int,
        settings: AstroImageProcessingSettings,
        stackingStartFrame: Int,
        usesPrecomputedFrames: Bool,
        rejectsBlurredFrames: Bool,
        preservesTimelineDuration: Bool
    ) async {
        let profile = settings.profile
        let size = Self.clampedStackSize(stackSize)
        let precomputedFrames = compositeFrames()
        let originalFrames = originalFrames()
        let startIndex = min(max(stackingStartFrame, 1), max(originalFrames.count, 1))
        let preStackFrames = Array(originalFrames.prefix(max(startIndex - 1, 0)))
        let stackSourceFrames = Array(originalFrames.dropFirst(max(startIndex - 1, 0)))
        let canReusePrecomputedFramesWithSettings = settings == .defaults(for: profile)
        let canUsePrecomputedFrames = usesPrecomputedFrames &&
            rejectedOriginalFrameCount == 0 &&
            canReusePrecomputedFramesWithSettings &&
            !precomputedFrames.isEmpty &&
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
        currentVideoFrame = 0
        totalVideoFrames = 0

        do {
            let renderURL = try createRenderDirectory(stackSize: size, fps: fps, profile: profile)
            let groups = canUsePrecomputedFrames ? [] : frames.chunked(into: size)
            let expectedFrames = outputFrameCount(
                stackSize: size,
                stackingStartFrame: startIndex,
                usesPrecomputedFrames: usesPrecomputedFrames,
                preservesTimelineDuration: preservesTimelineDuration
            )

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
            let videoProgress: @Sendable (Int, Int) async -> Void = { [weak self] current, total in
                await self?.updateVideoRenderProgress(current: current, total: total)
            }
            let result: AstroRenderResult
            if canUsePrecomputedFrames {
                result = try await AstroRenderWorker.renderPrecomputedFrames(
                    precomputedFrames,
                    preStackFrames: preStackFrames,
                    repeatCount: preservesTimelineDuration ? size : 1,
                    renderURL: renderURL,
                    fps: fps,
                    progress: progress,
                    videoProgress: videoProgress
                )
            } else {
                result = try await AstroRenderWorker.render(
                    groups: groups,
                    preStackFrames: preStackFrames,
                    renderURL: renderURL,
                    fps: fps,
                    settings: settings,
                    rejectsBlurredFrames: rejectsBlurredFrames,
                    preservesTimelineDuration: preservesTimelineDuration,
                    progress: progress,
                    videoProgress: videoProgress
                )
            }

            try writeRenderManifest(
                renderURL: renderURL,
                stackSize: size,
                fps: fps,
                profile: profile,
                stackingStartFrame: startIndex,
                usedPrecomputedFrames: canUsePrecomputedFrames,
                rejectsBlurredFrames: rejectsBlurredFrames && !canUsePrecomputedFrames,
                preservesTimelineDuration: preservesTimelineDuration,
                denoiseApplied: settings.appliesDenoise,
                denoiseBackend: settings.denoiseBackend,
                denoiseNoiseLevel: settings.noiseLevel,
                denoiseSharpness: settings.sharpness,
                processingSettings: settings,
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
        currentVideoFrame = 0
        totalVideoFrames = 0
        reload()
    }

    private func updateRenderProgress(current: Int, total: Int, profileTitle: String) {
        currentStack = current
        totalStacks = total
        status = "Stack \(current)/\(total) (\(profileTitle))"
    }

    private func updateVideoRenderProgress(current: Int, total: Int) {
        currentVideoFrame = current
        totalVideoFrames = total
        let percent = total > 0 ? Int((Double(current) / Double(total) * 100).rounded()) : 0
        status = "Criando video \(min(max(percent, 0), 100))%"
    }

    func previewReferenceFrameCount(stackSize: Int, stackingStartFrame: Int) -> Int {
        let frames = originalFrames()
        guard !frames.isEmpty else { return 0 }

        let startIndex = min(max(stackingStartFrame, 1), frames.count)
        let availableCount = max(frames.count - (startIndex - 1), 0)
        return min(Self.clampedStackSize(stackSize), availableCount)
    }

    func referencePreviewFrameURL(stackingStartFrame: Int) -> URL? {
        let frames = originalFrames()
        guard !frames.isEmpty else { return nil }

        let startIndex = min(max(stackingStartFrame, 1), frames.count)
        return frames[startIndex - 1]
    }

    func normalizedReferencePreviewFrameURL(stackingStartFrame: Int) async throws -> URL? {
        guard let referenceURL = referencePreviewFrameURL(stackingStartFrame: stackingStartFrame) else {
            return nil
        }

        let previewDirectory = session.directoryURL.appendingPathComponent("Preview Frames", isDirectory: true)
        try fileManager.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        let outputURL = previewDirectory.appendingPathComponent("reference_original_\(UUID().uuidString).jpg")

        return try await Task.detached(priority: .userInitiated) {
            guard let image = CIImage(contentsOf: referenceURL)?.normalizedForStacking() else {
                return referenceURL
            }

            let context = CIContext(options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
                .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
            ])
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            guard let data = context.jpegRepresentation(
                of: image,
                colorSpace: colorSpace,
                options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.95]
            ) else {
                return referenceURL
            }

            try data.write(to: outputURL, options: [.atomic])
            return outputURL
        }.value
    }

    func renderReferencePreview(
        stackSize: Int,
        stackingStartFrame: Int,
        settings: AstroImageProcessingSettings
    ) async throws -> URL {
        guard !isRendering, !isExportingOriginalFrames else {
            throw AstroRenderStoreError.renderAlreadyRunning
        }

        let frames = originalFrames()
        guard !frames.isEmpty else {
            throw AstroRenderStoreError.noPreviewFrames
        }

        let startIndex = min(max(stackingStartFrame, 1), frames.count)
        let size = Self.clampedStackSize(stackSize)
        let previewFrames = Array(frames.dropFirst(startIndex - 1).prefix(size))
        guard !previewFrames.isEmpty else {
            throw AstroRenderStoreError.noPreviewFrames
        }

        let previewDirectory = session.directoryURL.appendingPathComponent("Preview Frames", isDirectory: true)
        try fileManager.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        let outputURL = previewDirectory.appendingPathComponent("reference_preview_\(UUID().uuidString).jpg")

        return try await Task.detached(priority: .userInitiated) {
            let data = try autoreleasepool {
                try ExposureStacker().averageJPEGFiles(
                    previewFrames,
                    maxDimension: 1920,
                    settings: settings
                )
            }
            try data.write(to: outputURL, options: [.atomic])
            return outputURL
        }.value
    }

    private static func clampedStackSize(_ value: Int) -> Int {
        min(max(value, 2), 120)
    }

    private func originalFrames() -> [URL] {
        let rejected = rejectedOriginalFrameNames
        return allOriginalFrames().filter { !rejected.contains($0.lastPathComponent) }
    }

    private func allOriginalFrames() -> [URL] {
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

    private var rejectedOriginalFramesURL: URL {
        session.directoryURL.appendingPathComponent("rejected_original_frames.json")
    }

    private func loadRejectedOriginalFrameNames() -> Set<String> {
        guard
            let data = try? Data(contentsOf: rejectedOriginalFramesURL),
            let names = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }

        let existingNames = Set(allOriginalFrames().map(\.lastPathComponent))
        return Set(names).intersection(existingNames)
    }

    private func saveRejectedOriginalFrameNames() {
        let names = rejectedOriginalFrameNames.sorted()
        guard let data = try? JSONEncoder().encode(names) else { return }
        try? data.write(to: rejectedOriginalFramesURL, options: [.atomic])
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
                thumbnailURL: renderThumbnailURL(in: renderURL),
                processedFrameURL: renderProcessedFrameURL(in: renderURL),
                modifiedAt: modifiedAt,
                profile: manifest["processingProfile"] as? String,
                stackingBackend: manifest["stackingBackend"] as? String,
                alignsStars: manifest["alignsStars"] as? Bool,
                usedPrecomputedFrames: manifest["usedPrecomputedFrames"] as? Bool,
                preservesTimelineDuration: manifest["preservesTimelineDuration"] as? Bool,
                denoiseApplied: manifest["denoiseApplied"] as? Bool,
                denoiseBackend: manifest["denoiseBackend"] as? String,
                denoiseNoiseLevel: Self.manifestFloat(manifest["denoiseNoiseLevel"]),
                denoiseSharpness: Self.manifestFloat(manifest["denoiseSharpness"]),
                gamma: Self.manifestFloat(manifest["gamma"]),
                contrast: Self.manifestFloat(manifest["contrast"]),
                brightness: Self.manifestFloat(manifest["brightness"]),
                saturation: Self.manifestFloat(manifest["saturation"]),
                shadowAmount: Self.manifestFloat(manifest["shadowAmount"]),
                highlightAmount: Self.manifestFloat(manifest["highlightAmount"]),
                vibrance: Self.manifestFloat(manifest["vibrance"]),
                unsharpAmount: Self.manifestFloat(manifest["unsharpAmount"]),
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

    private func renderThumbnailURL(in renderURL: URL) -> URL? {
        renderFrameURLs(in: renderURL).first
    }

    private func renderProcessedFrameURL(in renderURL: URL) -> URL? {
        renderFrameURLs(in: renderURL).last
    }

    private func renderFrameURLs(in renderURL: URL) -> [URL] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: renderURL,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return []
        }

        return urls
            .filter { url in
                url.pathExtension.lowercased() == "jpg" &&
                    url.lastPathComponent.hasPrefix("stack_")
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func manifestFloat(_ value: Any?) -> Float? {
        if let value = value as? Float {
            return value
        }
        if let value = value as? Double {
            return Float(value)
        }
        if let value = value as? NSNumber {
            return value.floatValue
        }
        return nil
    }

    private func calculateStorageSummary() -> AstroStorageSummary {
        let originalBytes = allOriginalFrames().reduce(UInt64(0)) { total, url in
            total + fileSize(url)
        }

        let astroFramesURL = session.directoryURL.appendingPathComponent("Astro Frames", isDirectory: true)
        let previewFramesURL = session.directoryURL.appendingPathComponent("Preview Frames", isDirectory: true)
        let thumbnailCacheURL = session.directoryURL.appendingPathComponent(ThumbnailCache.directoryName, isDirectory: true)
        let rendersURL = session.directoryURL.appendingPathComponent("Astro Renders", isDirectory: true)

        let intermediateFrameBytes = directorySize(astroFramesURL)
        let previewBytes = directorySize(previewFramesURL)
        let thumbnailBytes = directorySize(thumbnailCacheURL)
        var processedRenderFrameBytes: UInt64 = 0
        var videoBytes: UInt64 = 0

        for renderURL in renderDirectories(in: rendersURL) {
            videoBytes += fileSize(renderURL.appendingPathComponent("astro.mp4"))
            processedRenderFrameBytes += jpgFileBytes(in: renderURL)
        }

        return AstroStorageSummary(
            originalBytes: originalBytes,
            processedFrameBytes: intermediateFrameBytes + processedRenderFrameBytes,
            videoBytes: videoBytes,
            cacheBytes: previewBytes + thumbnailBytes,
            hasProcessingCache: intermediateFrameBytes > 0 || previewBytes > 0 || thumbnailBytes > 0
        )
    }

    private func renderDirectories(in rendersURL: URL) -> [URL] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: rendersURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return []
        }

        return urls.filter {
            ((try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true)
        }
    }

    private func jpgFileBytes(in directory: URL) -> UInt64 {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return 0
        }

        return urls
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .reduce(UInt64(0)) { total, url in total + fileSize(url) }
    }

    private func directorySize(_ directory: URL) -> UInt64 {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else {
            return 0
        }

        var total: UInt64 = 0
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            total += fileSize(url)
        }
        return total
    }

    private func fileSize(_ url: URL) -> UInt64 {
        UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
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
        usedPrecomputedFrames: Bool,
        rejectsBlurredFrames: Bool,
        preservesTimelineDuration: Bool,
        denoiseApplied: Bool,
        denoiseBackend: AstroDenoiseBackend,
        denoiseNoiseLevel: Float,
        denoiseSharpness: Float,
        processingSettings: AstroImageProcessingSettings,
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
            "stackingBackend": processingSettings.stackingBackend.rawValue,
            "alignsStars": processingSettings.alignsStars,
            "usedPrecomputedFrames": usedPrecomputedFrames,
            "rejectsBlurredFrames": rejectsBlurredFrames,
            "preservesTimelineDuration": preservesTimelineDuration,
            "denoiseApplied": denoiseApplied,
            "denoiseBackend": denoiseBackend.rawValue,
            "denoiseNoiseLevel": denoiseNoiseLevel,
            "denoiseSharpness": denoiseSharpness,
            "gamma": processingSettings.gamma,
            "contrast": processingSettings.contrast,
            "brightness": processingSettings.brightness,
            "saturation": processingSettings.saturation,
            "shadowAmount": processingSettings.shadowAmount,
            "highlightAmount": processingSettings.highlightAmount,
            "vibrance": processingSettings.vibrance,
            "unsharpAmount": processingSettings.unsharpAmount,
            "unsharpRadius": processingSettings.unsharpRadius,
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
    let thumbnailURL: URL?
    let processedFrameURL: URL?
    let modifiedAt: Date
    let profile: String?
    let stackingBackend: String?
    let alignsStars: Bool?
    let usedPrecomputedFrames: Bool?
    let preservesTimelineDuration: Bool?
    let denoiseApplied: Bool?
    let denoiseBackend: String?
    let denoiseNoiseLevel: Float?
    let denoiseSharpness: Float?
    let gamma: Float?
    let contrast: Float?
    let brightness: Float?
    let saturation: Float?
    let shadowAmount: Float?
    let highlightAmount: Float?
    let vibrance: Float?
    let unsharpAmount: Float?
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

    var technicalSummary: String? {
        var parts: [String] = []

        if let backendTitle {
            parts.append(backendTitle)
        }

        if let alignsStars {
            parts.append(alignsStars ? "alinhamento on" : "alinhamento off")
        }

        if let denoiseApplied {
            if denoiseApplied {
                parts.append("ruido \(denoiseBackendTitle ?? "on")")
            } else {
                parts.append("ruido off")
            }
        }

        if let usedPrecomputedFrames {
            parts.append(usedPrecomputedFrames ? "frames bons" : "originais")
        }

        if let preservesTimelineDuration {
            parts.append(preservesTimelineDuration ? "duracao preservada" : "compactado")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var adjustmentSummary: String? {
        var parts: [String] = []
        appendValue("ruido", denoiseNoiseLevel, to: &parts, format: "%.3f")
        appendValue("nitidez", denoiseSharpness, to: &parts, format: "%.2f")
        appendValue("gamma", gamma, to: &parts, format: "%.2f")
        appendValue("contraste", contrast, to: &parts, format: "%.2f")
        appendValue("brilho", brightness, to: &parts, format: "%.3f")
        appendValue("sat", saturation, to: &parts, format: "%.2f")
        appendValue("sombras", shadowAmount, to: &parts, format: "%.2f")
        appendValue("highlights", highlightAmount, to: &parts, format: "%.2f")
        appendValue("vibrance", vibrance, to: &parts, format: "%.2f")
        appendValue("unsharp", unsharpAmount, to: &parts, format: "%.2f")
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var profileTitle: String? {
        guard let profile else { return nil }
        return AstroProcessingProfile(rawValue: profile)?.title ?? profile
    }

    private var backendTitle: String? {
        guard let stackingBackend else { return nil }
        return AstroStackingBackend(rawValue: stackingBackend)?.title ?? stackingBackend
    }

    private var denoiseBackendTitle: String? {
        guard let denoiseBackend else { return nil }
        return AstroDenoiseBackend(rawValue: denoiseBackend)?.title ?? denoiseBackend
    }

    private func appendValue(_ label: String, _ value: Float?, to parts: inout [String], format: String) {
        guard let value else { return }
        parts.append("\(label) \(String(format: format, value))")
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
    case renderAlreadyRunning
    case noPreviewFrames

    var errorDescription: String? {
        switch self {
        case .unsafeRenderPath:
            return "caminho de render invalido"
        case .renderAlreadyRunning:
            return "aguarde o processo atual terminar"
        case .noPreviewFrames:
            return "nao ha frames originais suficientes para gerar o preview"
        }
    }
}

private enum AstroRenderWorker {
    static func render(
        groups: [[URL]],
        preStackFrames: [URL],
        renderURL: URL,
        fps: Int,
        settings: AstroImageProcessingSettings,
        rejectsBlurredFrames: Bool,
        preservesTimelineDuration: Bool,
        progress: @escaping @Sendable (Int, Int) async -> Void,
        videoProgress: @escaping @Sendable (Int, Int) async -> Void
    ) async throws -> AstroRenderResult {
        try await Task.detached(priority: .userInitiated) {
            let stacker = ExposureStacker()
            let profile = settings.profile
            var savedFrameURLs: [URL] = []
            var videoFrameURLs: [URL] = []
            let totalVideoFrames = preStackFrames.count + groups.reduce(0) { $0 + (preservesTimelineDuration ? $1.count : 1) }
            savedFrameURLs.reserveCapacity(preStackFrames.count + groups.count)
            videoFrameURLs.reserveCapacity(totalVideoFrames)
            var retainedSourceFrames = preStackFrames.count

            for (index, frameURL) in preStackFrames.enumerated() {
                try Task.checkCancellation()
                let outputURL = renderURL.appendingPathComponent(String(format: "stack_%06d.jpg", index + 1))
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                try FileManager.default.copyItem(at: frameURL, to: outputURL)
                savedFrameURLs.append(outputURL)
                videoFrameURLs.append(outputURL)
                await progress(videoFrameURLs.count, totalVideoFrames)
            }

            for group in groups {
                try Task.checkCancellation()
                let preferredFrames = rejectsBlurredFrames
                    ? stacker.preferredFrames(group, maxDimension: 1920, profile: profile)
                    : group
                retainedSourceFrames += preferredFrames.count

                let data = try autoreleasepool {
                    try stacker.averageJPEGFiles(
                        preferredFrames,
                        maxDimension: 1920,
                        settings: settings
                    )
                }
                let outputURL = renderURL.appendingPathComponent(String(format: "stack_%06d.jpg", savedFrameURLs.count + 1))
                try data.write(to: outputURL, options: [.atomic])
                savedFrameURLs.append(outputURL)
                let repeatCount = preservesTimelineDuration ? group.count : 1
                videoFrameURLs.append(contentsOf: Array(repeating: outputURL, count: max(repeatCount, 1)))
                await progress(videoFrameURLs.count, totalVideoFrames)
            }

            let videoURL = renderURL.appendingPathComponent("astro.mp4")
            await progress(videoFrameURLs.count, videoFrameURLs.count)
            await videoProgress(0, videoFrameURLs.count)
            try await TimelapseVideoRenderer().render(
                frames: videoFrameURLs,
                outputURL: videoURL,
                fps: fps,
                progress: videoProgress
            )
            return AstroRenderResult(
                outputFrames: videoFrameURLs.count,
                retainedSourceFrames: retainedSourceFrames,
                videoURL: videoURL
            )
        }.value
    }

    static func renderPrecomputedFrames(
        _ frames: [URL],
        preStackFrames: [URL],
        repeatCount: Int,
        renderURL: URL,
        fps: Int,
        progress: @escaping @Sendable (Int, Int) async -> Void,
        videoProgress: @escaping @Sendable (Int, Int) async -> Void
    ) async throws -> AstroRenderResult {
        try await Task.detached(priority: .userInitiated) {
            var savedFrameURLs: [URL] = []
            var videoFrameURLs: [URL] = []
            let totalVideoFrames = preStackFrames.count + (frames.count * max(repeatCount, 1))
            savedFrameURLs.reserveCapacity(preStackFrames.count + frames.count)
            videoFrameURLs.reserveCapacity(totalVideoFrames)

            for frameURL in preStackFrames {
                try Task.checkCancellation()

                let outputURL = renderURL.appendingPathComponent(String(format: "stack_%06d.jpg", savedFrameURLs.count + 1))
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                try FileManager.default.copyItem(at: frameURL, to: outputURL)
                savedFrameURLs.append(outputURL)
                videoFrameURLs.append(outputURL)
                await progress(videoFrameURLs.count, totalVideoFrames)
            }

            for frameURL in frames {
                try Task.checkCancellation()

                let outputURL = renderURL.appendingPathComponent(String(format: "stack_%06d.jpg", savedFrameURLs.count + 1))
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                try FileManager.default.copyItem(at: frameURL, to: outputURL)
                savedFrameURLs.append(outputURL)
                videoFrameURLs.append(contentsOf: Array(repeating: outputURL, count: max(repeatCount, 1)))
                await progress(videoFrameURLs.count, totalVideoFrames)
            }

            let videoURL = renderURL.appendingPathComponent("astro.mp4")
            await progress(videoFrameURLs.count, videoFrameURLs.count)
            await videoProgress(0, videoFrameURLs.count)
            try await TimelapseVideoRenderer().render(
                frames: videoFrameURLs,
                outputURL: videoURL,
                fps: fps,
                progress: videoProgress
            )
            return AstroRenderResult(
                outputFrames: videoFrameURLs.count,
                retainedSourceFrames: preStackFrames.count + frames.count,
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

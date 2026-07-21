import AVKit
import SwiftUI

struct CameraeNextCaptureCompletionPresentation: Equatable, Sendable {
    let title: String
    let message: String
    let primaryActionTitle: String
    let offersProcessing: Bool
    let accentTheme: CameraeWorkflowTheme

    init(module: CameraModule) {
        if module == .astrophotography {
            title = "Sessão concluída"
            message = "As imagens foram salvas. Agora você pode revisar, empilhar e finalizar o resultado Astro."
            primaryActionTitle = "Processar imagens"
            offersProcessing = true
            accentTheme = .astro
        } else {
            title = "Captura concluída"
            message = "O material foi salvo no projeto e já está disponível na lista de sessões."
            primaryActionTitle = "Voltar ao projeto"
            offersProcessing = false
            accentTheme = .repeatable
        }
    }
}

struct CameraeNextCompletedCapture: Identifiable, Equatable {
    let id = UUID()
    let module: CameraModule
    let session: TimelapseSession?
}

struct CameraeNextCaptureCompletionView: View {
    let capture: CameraeNextCompletedCapture
    let onDone: () -> Void
    let onOpenSessions: () -> Void

    @State private var isPresentingProcessing = false

    private var presentation: CameraeNextCaptureCompletionPresentation {
        .init(module: capture.module)
    }
    private var theme: CameraeNextTheme { .init(workflow: presentation.accentTheme) }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(theme.accent.opacity(0.16))
                        .frame(width: 132, height: 132)
                    Circle()
                        .stroke(theme.accent.opacity(0.34), lineWidth: 1)
                        .frame(width: 104, height: 104)
                    Image(systemName: presentation.offersProcessing ? "sparkles" : "checkmark")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(theme.accent)
                }

                VStack(spacing: 10) {
                    Text(presentation.title)
                        .font(.custom("Outfit-SemiBold", size: 26, relativeTo: .title2))
                        .foregroundStyle(theme.text)
                    Text(presentation.message)
                        .font(.custom("Outfit-Regular", size: 15, relativeTo: .body))
                        .foregroundStyle(theme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 330)
                }

                if let session = capture.session {
                    CameraeNextCard(theme: theme) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                CameraeNextSectionLabel(title: "Sessão", theme: theme)
                                Text(session.name)
                                    .font(.custom("Outfit-SemiBold", size: 15, relativeTo: .headline))
                                    .foregroundStyle(theme.text)
                                Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                                    .foregroundStyle(theme.muted)
                            }
                            Spacer()
                            Image(systemName: "photo.stack")
                                .font(.title2)
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .frame(maxWidth: 358)
                }

                Spacer()

                VStack(spacing: 10) {
                    CameraeNextActionButton(
                        title: presentation.primaryActionTitle,
                        systemImage: presentation.offersProcessing ? "wand.and.stars" : "arrow.left",
                        theme: theme,
                        isDisabled: presentation.offersProcessing && capture.session == nil
                    ) {
                        if presentation.offersProcessing {
                            isPresentingProcessing = true
                        } else {
                            onDone()
                        }
                    }

                    CameraeNextActionButton(
                        title: "Ver sessões",
                        systemImage: "rectangle.stack",
                        theme: theme,
                        style: .secondary,
                        action: onOpenSessions
                    )
                }
                .frame(maxWidth: 358)
            }
            .padding(16)
        }
        .preferredColorScheme(theme.colorScheme)
        .onAppear { AppOrientationLock.shared.restorePortrait() }
        .fullScreenCover(isPresented: $isPresentingProcessing) {
            if let session = capture.session {
                NavigationStack {
                    CameraeNextAstroProcessingView(session: session) {
                        isPresentingProcessing = false
                        onDone()
                    }
                }
            }
        }
    }
}

enum CameraeNextAstroProcessingArea: String, CaseIterable, Equatable, Identifiable, Sendable {
    case capture
    case create
    case video
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture: "Captura"
        case .create: "Criar"
        case .video: "Vídeo"
        case .files: "Arquivos"
        }
    }
}

enum CameraeNextAstroProcessingStage: Equatable, Sendable {
    case stacking
    case video
}

enum CameraeNextAstroProcessingPhase: Equatable, Sendable {
    case ready
    case processing(
        currentStack: Int,
        totalStacks: Int,
        currentVideoFrame: Int,
        totalVideoFrames: Int
    )
    case completed(duration: Double)
}

struct CameraeNextAstroResultMetric: Equatable, Sendable {
    let label: String
    let value: String
}

struct CameraeNextAstroProcessingPresentation: Equatable, Sendable {
    let totalOriginalFrames: Int
    let activeOriginalFrames: Int
    let outputFrames: Int
    let stackingStartFrame: Int
    let stackSize: Int
    let videoSettings: WorkflowVideoSettings
    let phase: CameraeNextAstroProcessingPhase

    var selectedArea: CameraeNextAstroProcessingArea {
        if case .completed = phase { return .video }
        return .create
    }

    var sourceCountText: String {
        let rejected = max(totalOriginalFrames - activeOriginalFrames, 0)
        if rejected == 0 { return "\(activeOriginalFrames) ativas" }
        return "\(activeOriginalFrames) ativas • \(rejected) ignoradas"
    }

    var stackingStartText: String {
        "Início automático • frame \(stackingStartFrame)"
    }

    var primaryActionTitle: String {
        if case .completed = phase { return "Abrir clipe astro" }
        return "Iniciar processo astro"
    }

    var processingStage: CameraeNextAstroProcessingStage? {
        guard case let .processing(_, _, _, totalVideoFrames) = phase else { return nil }
        return totalVideoFrames > 0 ? .video : .stacking
    }

    var processingDetail: String? {
        guard case let .processing(currentStack, totalStacks, currentVideoFrame, totalVideoFrames) = phase else {
            return nil
        }
        if totalVideoFrames > 0 {
            let percent = Int((Double(currentVideoFrame) / Double(max(totalVideoFrames, 1)) * 100).rounded())
            return "Vídeo \(min(max(percent, 0), 100))%"
        }
        return "Stack \(currentStack)/\(totalStacks)"
    }

    var progressFraction: Double {
        guard case let .processing(currentStack, totalStacks, currentVideoFrame, totalVideoFrames) = phase else {
            return 0
        }
        if totalVideoFrames > 0 {
            return min(max(Double(currentVideoFrame) / Double(max(totalVideoFrames, 1)), 0), 1)
        }
        return min(max(Double(currentStack) / Double(max(totalStacks, 1)), 0), 1)
    }

    var duration: Double {
        if case let .completed(value) = phase { return value }
        guard videoSettings.fps > 0 else { return 0 }
        return Double(outputFrames) / Double(videoSettings.fps)
    }

    var durationText: String {
        String(format: "%.1f", duration).replacingOccurrences(of: ".", with: ",") + " s"
    }

    var outputSummary: String {
        "\(videoSettings.resolution.label) • \(videoSettings.fps) fps • HEVC"
    }

    var resultMetrics: [CameraeNextAstroResultMetric] {
        [
            .init(label: "stacks", value: "\(stackCount)"),
            .init(label: "frames", value: "\(outputFrames)"),
            .init(label: "duração", value: durationText)
        ]
    }

    private var stackCount: Int {
        let stackableFrames = max(activeOriginalFrames - max(stackingStartFrame - 1, 0), 0)
        guard stackableFrames > 0 else { return 0 }
        return Int(ceil(Double(stackableFrames) / Double(max(stackSize, 1))))
    }
}

struct CameraeNextAstroProcessingView: View {
    let session: TimelapseSession
    let onClose: () -> Void

    @StateObject private var processor: AstroProcessingController
    @State private var selectedArea = CameraeNextAstroProcessingArea.create
    @State private var stackSize = 10.0
    @State private var stackingStartFrame = 1.0
    @State private var usesAutomaticStackingStart = true
    @State private var usesPrecomputedFrames = false
    @State private var preservesTimelineDuration = true
    @State private var videoSettings = WorkflowVideoSettings.astroDefault
    @State private var processingSettings: AstroImageProcessingSettings
    @State private var isShowingFrameCuration = false
    @State private var isShowingImageLab = false
    @State private var isShowingVideoSettings = false
    @State private var videoItem: CameraeNextAstroVideoItem?
    @State private var shareItem: CameraeNextAstroShareItem?
    @State private var renderTask: Task<Void, Never>?
    @State private var exportTask: Task<Void, Never>?
    @State private var errorMessage: String?

    private let theme = CameraeNextTheme(workflow: .astro)
    private let minimumStackSize = 2
    private let maximumStackSize = 120

    init(session: TimelapseSession, onClose: @escaping () -> Void) {
        self.session = session
        self.onClose = onClose
        _processor = StateObject(wrappedValue: AstroProcessingController(session: session))
        var settings = AstroImageProcessingSettings.defaults(for: .natural)
        settings.stackingBackend = .openCV
        settings.alignsStars = true
        _processingSettings = State(initialValue: settings)
    }

    private var effectiveStackingStartFrame: Int {
        if usesAutomaticStackingStart, let recommended = processor.recommendedStackingStartFrame {
            return recommended
        }
        return min(max(Int(stackingStartFrame), 1), max(processor.originalFrameCount, 1))
    }

    private var maximumSelectableStackSize: Int {
        max(min(processor.originalFrameCount, maximumStackSize), minimumStackSize)
    }

    private var outputFrameCount: Int {
        processor.outputFrameCount(
            stackSize: Int(stackSize),
            stackingStartFrame: effectiveStackingStartFrame,
            usesPrecomputedFrames: usesPrecomputedFrames,
            preservesTimelineDuration: preservesTimelineDuration
        )
    }

    private var completedClip: AstroRenderedClip? { processor.renderedClips.first }

    private var completedDuration: Double {
        guard let completedClip else { return Double(outputFrameCount) / Double(max(videoSettings.fps, 1)) }
        return Double(completedClip.outputFrames ?? outputFrameCount) / Double(max(completedClip.fps ?? videoSettings.fps, 1))
    }

    private var phase: CameraeNextAstroProcessingPhase {
        if processor.isRendering {
            return .processing(
                currentStack: processor.currentStack,
                totalStacks: processor.totalStacks,
                currentVideoFrame: processor.currentVideoFrame,
                totalVideoFrames: processor.totalVideoFrames
            )
        }
        if completedClip != nil { return .completed(duration: completedDuration) }
        return .ready
    }

    private var presentation: CameraeNextAstroProcessingPresentation {
        .init(
            totalOriginalFrames: processor.totalOriginalFrameCount,
            activeOriginalFrames: processor.originalFrameCount,
            outputFrames: completedClip?.outputFrames ?? outputFrameCount,
            stackingStartFrame: effectiveStackingStartFrame,
            stackSize: Int(stackSize),
            videoSettings: videoSettings,
            phase: phase
        )
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: 8) {
                CameraeNextAstroProcessTabs(selection: $selectedArea, theme: theme)

                ScrollView {
                    VStack(spacing: 8) {
                        selectedContent
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 16)

            if processor.isRendering {
                CameraeNextAstroProcessingOverlay(
                    presentation: presentation,
                    theme: theme,
                    cancel: cancelRender
                )
            } else if processor.isExportingOriginalFrames {
                CameraeNextOperationOverlay(
                    state: .processing(
                        title: "Exportando ZIP",
                        detail: processor.originalFrameExportProgress?.detailText,
                        canCancel: true
                    ),
                    theme: theme,
                    onCancel: { exportTask?.cancel() }
                )
            }
        }
        .navigationTitle("Processar astro")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Voltar")
            }
        }
        .toolbarBackground(theme.background, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            primaryAction
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(theme.background)
        }
        .tint(theme.accent)
        .preferredColorScheme(theme.colorScheme)
        .task {
            processor.reload()
            processor.reloadStorageSummary()
        }
        .onChange(of: processor.originalFrameCount) { clampControls() }
        .onChange(of: processor.recommendedStackingStartFrame) { applyRecommendedStart() }
        .onChange(of: processor.lastVideoURL) { _, url in
            if url != nil { selectedArea = .video }
        }
        .sheet(isPresented: $isShowingFrameCuration) {
            AstroFrameCurationView(processor: processor)
                .preferredColorScheme(.dark)
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
        .sheet(isPresented: $isShowingVideoSettings) {
            NavigationStack {
                Form {
                    WorkflowVideoSettingsView(settings: $videoSettings)
                    Toggle("Preservar duração", isOn: $preservesTimelineDuration)
                }
                .navigationTitle("Vídeo de saída")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Concluir") { isShowingVideoSettings = false }
                    }
                }
            }
            .presentationDetents([.medium])
            .preferredColorScheme(.dark)
        }
        .fullScreenCover(item: $videoItem) { item in
            CameraeNextAstroVideoPlayer(url: item.url) { videoItem = nil }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: item.urls)
        }
        .alert("Não foi possível concluir", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedArea {
        case .capture:
            sourceSummaryCard
            capturesCard
        case .create:
            sourceSummaryCard
            stackingCard
            imageProcessingCard
            outputCard
        case .video:
            if completedClip != nil {
                resultSummaryCard
                completedProcessingCard
                imageProcessingCard
                outputCard
            } else {
                sourceSummaryCard
                outputCard
                CameraeNextCard(theme: theme) {
                    ContentUnavailableView(
                        "Nenhum clipe criado",
                        systemImage: "play.rectangle",
                        description: Text("Revise os ajustes e inicie o processo Astro.")
                    )
                    .foregroundStyle(theme.muted)
                }
            }
        case .files:
            storageCard
            maintenanceCard
        }
    }

    private var sourceSummaryCard: some View {
        CameraeNextCard(theme: theme) {
            HStack(spacing: 12) {
                ReferenceThumbnail(
                    imageURL: processor.referencePreviewFrameURL(stackingStartFrame: effectiveStackingStartFrame),
                    systemImage: "sparkles",
                    width: 84,
                    height: 88,
                    maxPixelSize: 360
                )

                VStack(alignment: .leading, spacing: 3) {
                    CameraeNextSectionLabel(title: "Frames de origem", theme: theme)
                    Text(session.name)
                        .font(.custom("Outfit-SemiBold", size: 16, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Text(presentation.sourceCountText)
                        .font(.custom("Outfit-Regular", size: 11, relativeTo: .caption))
                        .foregroundStyle(theme.muted)
                        .lineLimit(1)
                    Text(presentation.stackingStartText)
                        .font(.custom("Outfit-Regular", size: 11, relativeTo: .caption))
                        .foregroundStyle(theme.accent)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("Revisar") { isShowingFrameCuration = true }
                    .font(.custom("Outfit-Medium", size: 11, relativeTo: .caption))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .disabled(processor.totalOriginalFrameCount == 0)
            }
        }
    }

    private var stackingCard: some View {
        CameraeNextCard(theme: theme) {
            VStack(spacing: 7) {
                CameraeNextSectionLabel(title: "Stacking e frames", theme: theme)

                CameraeNextSettingRow(
                    title: "Início automático",
                    helper: processor.recommendedStackingStartFrame == nil
                        ? "Sem marco salvo; usando o primeiro frame"
                        : "Detectado próximo de 1s",
                    theme: theme
                ) {
                    Toggle("", isOn: $usesAutomaticStackingStart)
                        .labelsHidden()
                }

                HStack {
                    Text("Começar no frame")
                        .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                        .foregroundStyle(theme.text)
                    Spacer()
                    Text("\(effectiveStackingStartFrame)")
                        .font(.custom("Outfit-SemiBold", size: 12, relativeTo: .caption))
                        .foregroundStyle(theme.accent)
                }

                if !usesAutomaticStackingStart, processor.originalFrameCount > 1 {
                    Slider(
                        value: $stackingStartFrame,
                        in: 1...Double(processor.originalFrameCount),
                        step: 1
                    )
                    .tint(theme.accent)
                }

                VStack(spacing: 6) {
                    HStack {
                        Text("Imagens por lote")
                            .font(.custom("Outfit-SemiBold", size: 12, relativeTo: .caption))
                            .foregroundStyle(theme.text)
                        Spacer()
                        Text("\(Int(stackSize))")
                            .font(.custom("DMMono-Regular", size: 12, relativeTo: .caption))
                            .foregroundStyle(theme.accent)
                    }
                    Slider(
                        value: $stackSize,
                        in: Double(minimumStackSize)...Double(maximumSelectableStackSize),
                        step: 1
                    )
                    .tint(theme.accent)
                    .disabled(processor.originalFrameCount < minimumStackSize)
                }
            }
        }
    }

    private var imageProcessingCard: some View {
        CameraeNextCard(theme: theme) {
            VStack(spacing: 7) {
                CameraeNextSectionLabel(title: "Processamento de imagem", theme: theme)

                HStack(spacing: 3) {
                    ForEach(AstroStackingBackend.allCases) { backend in
                        Button {
                            updateBackend(backend)
                        } label: {
                            Text(backend.title)
                                .font(.custom("Outfit-Medium", size: 12, relativeTo: .caption))
                                .foregroundStyle(processingSettings.stackingBackend == backend ? Color.white : theme.muted)
                                .frame(maxWidth: .infinity)
                                .frame(height: 28)
                                .background(
                                    processingSettings.stackingBackend == backend ? theme.accent : theme.surface,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(theme.surface, in: Capsule())
                .overlay { Capsule().stroke(theme.border, lineWidth: 1) }

                HStack {
                    Text(imageProcessingSummary)
                        .font(.custom("Outfit-Regular", size: 11, relativeTo: .caption))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Spacer()
                    Button(completedClip == nil ? "Editar" : "Detalhes") {
                        isShowingImageLab = true
                    }
                    .font(.custom("Outfit-SemiBold", size: 11, relativeTo: .caption))
                }
            }
        }
    }

    private var outputCard: some View {
        CameraeNextCard(theme: theme) {
            VStack(spacing: 6) {
                HStack {
                    CameraeNextSectionLabel(title: "Vídeo de saída", theme: theme)
                    Button(completedClip == nil ? "Ajustar" : "Enviar") {
                        if let url = completedClip?.videoURL {
                            shareItem = .init(urls: [url])
                        } else {
                            isShowingVideoSettings = true
                        }
                    }
                    .font(.custom("Outfit-SemiBold", size: 11, relativeTo: .caption))
                }
                HStack {
                    Text(presentation.outputSummary)
                        .font(.custom("Outfit-SemiBold", size: 13, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(presentation.durationText)
                            .font(.custom("Outfit-SemiBold", size: 13, relativeTo: .subheadline))
                            .foregroundStyle(theme.accent)
                        Text("estimado")
                            .font(.custom("Outfit-Regular", size: 9, relativeTo: .caption2))
                            .foregroundStyle(theme.muted)
                    }
                }
            }
        }
    }

    private var resultSummaryCard: some View {
        CameraeNextCard(theme: theme) {
            HStack(spacing: 12) {
                ReferenceThumbnail(
                    imageURL: completedClip?.thumbnailURL,
                    systemImage: "sparkles",
                    width: 84,
                    height: 88,
                    maxPixelSize: 360
                )
                VStack(alignment: .leading, spacing: 3) {
                    CameraeNextSectionLabel(title: "Resultado final", theme: theme)
                    Text("Clipe astro pronto")
                        .font(.custom("Outfit-SemiBold", size: 16, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                    Text("\(presentation.outputFrames) frames • \(presentation.durationText)")
                        .font(.custom("Outfit-Regular", size: 11, relativeTo: .caption))
                        .foregroundStyle(theme.muted)
                    Text(presentation.outputSummary)
                        .font(.custom("Outfit-Regular", size: 11, relativeTo: .caption))
                        .foregroundStyle(theme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("Enviar") {
                    if let url = completedClip?.videoURL { shareItem = .init(urls: [url]) }
                }
                .font(.custom("Outfit-Medium", size: 11, relativeTo: .caption))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
    }

    private var completedProcessingCard: some View {
        CameraeNextCard(theme: theme) {
            VStack(spacing: 8) {
                CameraeNextSectionLabel(title: "Processamento concluído", theme: theme)
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Clipe criado com sucesso")
                            .font(.custom("Outfit-SemiBold", size: 13, relativeTo: .subheadline))
                            .foregroundStyle(theme.text)
                        Text("Alinhamento e redução de ruído aplicados")
                            .font(.custom("Outfit-Regular", size: 10, relativeTo: .caption2))
                            .foregroundStyle(theme.muted)
                    }
                    Spacer()
                }
                HStack(spacing: 6) {
                    ForEach(presentation.resultMetrics, id: \.label) { metric in
                        VStack(spacing: 2) {
                            Text(metric.value)
                                .font(.custom("Outfit-SemiBold", size: 15, relativeTo: .subheadline))
                                .foregroundStyle(theme.accent)
                            Text(metric.label)
                                .font(.custom("Outfit-Regular", size: 9, relativeTo: .caption2))
                                .foregroundStyle(theme.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 66)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    private var capturesCard: some View {
        CameraeNextCard(theme: theme) {
            VStack(spacing: 10) {
                CameraeNextSectionLabel(title: "Clipes criados", theme: theme)
                if processor.renderedClips.isEmpty {
                    Text("Nenhum clipe ainda")
                        .font(.custom("Outfit-Regular", size: 13, relativeTo: .footnote))
                        .foregroundStyle(theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(processor.renderedClips) { clip in
                        CameraeNextAstroClipRow(
                            clip: clip,
                            theme: theme,
                            open: { openVideo(clip.videoURL) },
                            share: { shareItem = .init(urls: [clip.videoURL]) },
                            delete: { deleteClip(clip) }
                        )
                    }
                }
            }
        }
    }

    private var storageCard: some View {
        CameraeNextCard(theme: theme) {
            VStack(spacing: 10) {
                CameraeNextSectionLabel(title: "Arquivos criados", theme: theme)
                storageRow("Frames capturados", bytes: processor.storageSummary.originalBytes)
                storageRow("Frames processados", bytes: processor.storageSummary.processedFrameBytes)
                storageRow("Vídeos criados", bytes: processor.storageSummary.videoBytes)
                storageRow("Cache", bytes: processor.storageSummary.cacheBytes)
                Divider().overlay(theme.border)
                storageRow("Total", bytes: processor.storageSummary.totalBytes, emphasized: true)
            }
        }
        .onAppear { processor.reloadStorageSummary() }
    }

    private var maintenanceCard: some View {
        CameraeNextCard(theme: theme) {
            VStack(spacing: 10) {
                CameraeNextSectionLabel(title: "Manutenção", theme: theme)
                CameraeNextActionButton(
                    title: processor.isExportingOriginalFrames ? "Exportando..." : "Exportar frames originais",
                    systemImage: "photo.stack",
                    theme: theme,
                    style: .secondary,
                    isDisabled: processor.originalFrameCount == 0,
                    action: exportOriginalFrames
                )
                CameraeNextActionButton(
                    title: "Limpar cache processado",
                    systemImage: "trash",
                    theme: theme,
                    style: .quiet,
                    isDisabled: !processor.storageSummary.hasProcessingCache,
                    action: clearCache
                )
            }
        }
    }

    private var primaryAction: some View {
        CameraeNextActionButton(
            title: selectedArea == .files ? "Concluir" : presentation.primaryActionTitle,
            systemImage: selectedArea == .files ? "checkmark" : (completedClip == nil ? "sparkles" : "play.fill"),
            theme: theme,
            isBusy: processor.isRendering,
            isDisabled: selectedArea != .files && completedClip == nil && outputFrameCount == 0
        ) {
            if selectedArea == .files {
                onClose()
            } else if let url = completedClip?.videoURL {
                openVideo(url)
            } else {
                startRender()
            }
        }
    }

    private var imageProcessingSummary: String {
        let alignment = processingSettings.alignsStars ? "Alinhar estrelas" : "Sem alinhamento"
        let denoise = processingSettings.appliesDenoise ? "Ruído \(processingSettings.denoiseBackend.title)" : "Ruído natural"
        return "\(alignment) • \(denoise)"
    }

    private func updateBackend(_ backend: AstroStackingBackend) {
        processingSettings.stackingBackend = backend
        processingSettings.alignsStars = backend == .openCV && processingSettings.profile.alignsStars
    }

    private func clampControls() {
        stackSize = Double(min(max(Int(stackSize), minimumStackSize), maximumSelectableStackSize))
        stackingStartFrame = Double(min(max(Int(stackingStartFrame), 1), max(processor.originalFrameCount, 1)))
        applyRecommendedStart()
    }

    private func applyRecommendedStart() {
        guard usesAutomaticStackingStart else { return }
        stackingStartFrame = Double(processor.recommendedStackingStartFrame ?? 1)
    }

    private func startRender() {
        guard renderTask == nil else { return }
        renderTask = Task {
            await processor.renderStacks(
                stackSize: Int(stackSize),
                videoSettings: videoSettings,
                settings: processingSettings,
                stackingStartFrame: effectiveStackingStartFrame,
                usesPrecomputedFrames: usesPrecomputedFrames,
                rejectsBlurredFrames: false,
                preservesTimelineDuration: preservesTimelineDuration
            )
            renderTask = nil
            if processor.lastVideoURL != nil { selectedArea = .video }
        }
    }

    private func cancelRender() {
        renderTask?.cancel()
        renderTask = nil
    }

    private func openVideo(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "O arquivo do clipe não foi encontrado. Gere o processo Astro novamente."
            processor.reload()
            return
        }
        videoItem = .init(url: url)
    }

    private func deleteClip(_ clip: AstroRenderedClip) {
        do {
            try processor.deleteClip(clip)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportOriginalFrames() {
        guard exportTask == nil else { return }
        exportTask = Task {
            do {
                let urls = try await processor.exportOriginalFramesArchives()
                if !urls.isEmpty { shareItem = .init(urls: urls) }
            } catch {
                errorMessage = error.localizedDescription
            }
            exportTask = nil
        }
    }

    private func clearCache() {
        do {
            try processor.clearProcessingCache()
            processor.reloadStorageSummary()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func storageRow(_ title: String, bytes: UInt64, emphasized: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
        }
        .font(.custom(emphasized ? "Outfit-SemiBold" : "Outfit-Regular", size: 13, relativeTo: .footnote))
        .foregroundStyle(emphasized ? theme.text : theme.muted)
    }
}

private struct CameraeNextAstroProcessTabs: View {
    @Binding var selection: CameraeNextAstroProcessingArea
    let theme: CameraeNextTheme

    var body: some View {
        HStack(spacing: 3) {
            ForEach(CameraeNextAstroProcessingArea.allCases) { area in
                Button {
                    selection = area
                } label: {
                    Text(area.title)
                        .font(.custom("Outfit-Medium", size: 12, relativeTo: .caption))
                        .foregroundStyle(selection == area ? Color.white : theme.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(selection == area ? theme.accent : theme.surface, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == area ? .isSelected : [])
            }
        }
        .padding(3)
        .background(theme.surface, in: Capsule())
        .overlay { Capsule().stroke(theme.border, lineWidth: 1) }
    }
}

private struct CameraeNextAstroProcessingOverlay: View {
    let presentation: CameraeNextAstroProcessingPresentation
    let theme: CameraeNextTheme
    let cancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
            CameraeNextCard(theme: theme) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(theme.surface)
                        Circle()
                            .stroke(theme.accent, lineWidth: 3)
                        Image(systemName: "sparkles")
                            .foregroundStyle(theme.accent)
                    }
                    .frame(width: 48, height: 48)

                    Text(presentation.processingStage == .video ? "Criando vídeo" : "Processando stacks")
                        .font(.custom("Outfit-SemiBold", size: 18, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                    Text("Mantenha o Camerae aberto até a operação terminar.")
                        .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                        .foregroundStyle(theme.muted)
                        .multilineTextAlignment(.center)
                    Text(presentation.processingDetail ?? "Preparando render")
                        .font(.custom("DMMono-Regular", size: 11, relativeTo: .caption))
                        .foregroundStyle(theme.accent)

                    ProgressView(value: presentation.progressFraction)
                        .tint(theme.accent)

                    HStack {
                        Text("STACKING")
                            .foregroundStyle(presentation.processingStage == .stacking ? theme.accent : theme.muted)
                        Spacer()
                        Text("VÍDEO")
                            .foregroundStyle(presentation.processingStage == .video ? theme.accent : theme.muted)
                    }
                    .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))

                    CameraeNextActionButton(
                        title: "Cancelar",
                        systemImage: nil,
                        theme: theme,
                        style: .secondary,
                        action: cancel
                    )
                    .frame(height: 44)
                }
            }
            .frame(maxWidth: 326)
            .padding(32)
        }
    }
}

private struct CameraeNextAstroClipRow: View {
    let clip: AstroRenderedClip
    let theme: CameraeNextTheme
    let open: () -> Void
    let share: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ReferenceThumbnail(imageURL: clip.thumbnailURL, systemImage: "play.rectangle", width: 72, height: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(clip.title)
                    .font(.custom("Outfit-SemiBold", size: 13, relativeTo: .footnote))
                    .foregroundStyle(theme.text)
                Text(clip.subtitle)
                    .font(.custom("Outfit-Regular", size: 10, relativeTo: .caption2))
                    .foregroundStyle(theme.muted)
                    .lineLimit(2)
            }
            Spacer()
            Button(action: open) { Image(systemName: "play.circle.fill") }
            Button(action: share) { Image(systemName: "square.and.arrow.up") }
            Button(role: .destructive, action: delete) { Image(systemName: "trash") }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }
}

private struct CameraeNextAstroVideoItem: Identifiable {
    let url: URL
    var id: String { url.path }
}

private struct CameraeNextAstroShareItem: Identifiable {
    let urls: [URL]
    var id: String { urls.map(\.path).joined(separator: "|") }
}

private struct CameraeNextAstroVideoPlayer: View {
    let url: URL
    let close: () -> Void
    @State private var player: AVPlayer
    @State private var isSharing = false

    init(url: URL, close: @escaping () -> Void) {
        self.url = url
        self.close = close
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player).ignoresSafeArea()
            HStack {
                Button(action: close) { Image(systemName: "xmark") }
                Spacer()
                Text("Clipe astro")
                    .font(.custom("Outfit-SemiBold", size: 15, relativeTo: .headline))
                Spacer()
                Button { isSharing = true } label: { Image(systemName: "square.and.arrow.up") }
            }
            .foregroundStyle(.white)
            .padding(16)
        }
        .statusBarHidden(true)
        .onAppear { player.play() }
        .onDisappear { player.pause() }
        .sheet(isPresented: $isSharing) { ShareSheet(items: [url]) }
    }
}

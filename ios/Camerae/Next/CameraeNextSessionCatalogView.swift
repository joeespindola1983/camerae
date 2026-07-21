import AVKit
import SwiftUI

enum CameraeNextProjectSection: String, CaseIterable, Equatable, Sendable {
    case configuration
    case captures

    var title: String {
        switch self {
        case .configuration: "Configurar"
        case .captures: "Capturas"
        }
    }
}

struct CameraeNextRepeatableProjectWorkspaceState: Equatable, Sendable {
    var section: CameraeNextProjectSection = .configuration
    var isFinalizingCapture = false

    mutating func showCaptures() {
        section = .captures
    }

    mutating func startNewCapture() {
        section = .configuration
    }

    mutating func captureDidFinish() {
        section = .captures
        isFinalizingCapture = true
    }

    mutating func catalogDidReload() {
        isFinalizingCapture = false
    }
}

enum CameraeNextCaptureCompletionRoute: Equatable, Sendable {
    case projectCaptures
    case completionScreen

    init(module: CameraModule) {
        self = module == .repeatable ? .projectCaptures : .completionScreen
    }
}

enum CameraeNextSessionOpenRoute: Equatable, Sendable {
    case video(URL)
    case generateVideo
    case astroProcessing

    init(summary: TimelapseSessionSummary) {
        if summary.session.module == .astrophotography {
            self = .astroProcessing
        } else if let url = summary.videoClipURL ?? summary.videoURL {
            self = .video(url)
        } else {
            self = .generateVideo
        }
    }
}

enum CameraeNextSessionTrailingAction: Equatable, Sendable {
    case share(URL)
    case videoMenu(URL)
    case menu
}

struct CameraeNextSessionCardPresentation: Equatable, Sendable {
    let statusText: String
    let trailingAction: CameraeNextSessionTrailingAction

    init(summary: TimelapseSessionSummary) {
        if summary.session.module == .astrophotography {
            statusText = "ABRIR PROCESSAMENTO"
            trailingAction = .menu
        } else if summary.captureKind == .video,
                  let url = summary.videoClipURL ?? summary.videoURL {
            statusText = "TOQUE PARA REPRODUZIR"
            trailingAction = .videoMenu(url)
        } else if let url = summary.videoClipURL ?? summary.videoURL {
            statusText = "TOQUE PARA REPRODUZIR"
            trailingAction = .share(url)
        } else {
            statusText = "MP4 AINDA NÃO GERADO"
            trailingAction = .menu
        }
    }
}

struct CameraeNextGenerateVideoPrompt: Equatable, Sendable {
    let title = "Configurar geração do MP4?"
    let message = "Antes de gerar, você poderá configurar o alinhamento com o frame de referência ou continuar sem correção."
    let primaryActionTitle = "Configurar MP4"
    let secondaryActionTitle = "Agora não"
}

struct CameraeNextProcessVideoAlignmentPrompt: Equatable, Sendable {
    let title = "Processar alinhamento do vídeo?"
    let message = "Use o frame de referência do projeto para reenquadrar este clipe antes de gerar o MP4 alinhado."
    let primaryActionTitle = "Processar alinhamento"
    let secondaryActionTitle = "Agora não"
}

struct CameraeNextProjectTabs: View {
    @Binding var selection: CameraeNextProjectSection
    let theme: CameraeNextTheme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CameraeNextProjectSection.allCases, id: \.self) { section in
                Button {
                    selection = section
                } label: {
                    Text(section.title)
                        .font(.custom("Outfit-Regular", size: 14, relativeTo: .subheadline))
                        .foregroundStyle(selection == section ? Color.white : theme.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(selection == section ? theme.accent : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(height: 50)
        .background(theme.surface, in: Capsule())
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

struct CameraeNextSessionCatalogModel: Equatable {
    let sessions: [TimelapseSessionSummary]
    let referenceFrameURL: URL?

    init(summaries: [TimelapseSessionSummary]) {
        let populated = summaries.filter { $0.frameCount > 0 }
        let explicitReference = populated
            .filter { $0.captureKind == .photo }
            .sorted { $0.session.createdAt > $1.session.createdAt }
            .compactMap(\.referenceFrameURL)
            .first
        let automaticReference = populated
            .filter { $0.captureKind != .photo }
            .sorted { $0.session.createdAt < $1.session.createdAt }
            .compactMap(\.referenceFrameURL)
            .first

        referenceFrameURL = explicitReference ?? automaticReference
        sessions = populated
            .filter { $0.captureKind != .photo }
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
    var isEmbedded = false
    var isFinalizingCapture = false
    var onCatalogLoaded: () -> Void = {}

    @State private var summaries: [TimelapseSessionSummary] = []
    @State private var selectedAstroSession: TimelapseSessionSummary?
    @State private var selectedVideo: CameraeNextSessionVideoItem?
    @State private var pendingDeletion: TimelapseSession?
    @State private var renderingSessionID: UUID?
    @State private var shareItem: CameraeNextSessionShareItem?
    @State private var errorMessage: String?
    @State private var pendingVideoGeneration: TimelapseSessionSummary?
    @State private var pendingVideoAlignmentConfirmation: TimelapseSessionSummary?
    @State private var pendingAlignmentSetup: TimelapseSessionSummary?
    @State private var videoSettings = WorkflowVideoSettings.repeatableDefault

    private var store: TimelapseSessionStore { .init(project: project) }
    private var theme: CameraeNextTheme { .init(workflow: project.module.designTheme) }
    private var presentation: CameraeNextSessionCatalogPresentation { .init(module: project.module) }
    private var catalog: CameraeNextSessionCatalogModel { .init(summaries: summaries) }

    var body: some View {
        Group {
            if isEmbedded {
                embeddedCatalog
            } else {
                NavigationStack {
                    standaloneCatalog
                }
            }
        }
        .tint(theme.accent)
        .preferredColorScheme(theme.colorScheme)
        .task { await reload() }
        .fullScreenCover(item: $selectedAstroSession) { summary in
            NavigationStack {
                CameraeNextAstroProcessingView(session: summary.session) {
                    selectedAstroSession = nil
                    Task { await reload() }
                }
            }
        }
        .fullScreenCover(item: $selectedVideo) { item in
            CameraeNextSessionVideoPlayerView(url: item.url, title: item.title) {
                selectedVideo = nil
            }
        }
        .sheet(item: $pendingVideoGeneration) { summary in
            CameraeNextGenerateVideoSheet(theme: theme) {
                pendingVideoGeneration = nil
                presentAlignmentSetup(afterDismissing: summary)
            } onCancel: {
                pendingVideoGeneration = nil
            }
            .presentationDetents([.height(350)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
            .presentationBackground(theme.card)
        }
        .sheet(item: $pendingVideoAlignmentConfirmation) { summary in
            CameraeNextProcessVideoAlignmentSheet(theme: theme) {
                pendingVideoAlignmentConfirmation = nil
                presentAlignmentSetup(afterDismissing: summary)
            } onCancel: {
                pendingVideoAlignmentConfirmation = nil
            }
            .presentationDetents([.height(350)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
            .presentationBackground(theme.card)
        }
        .fullScreenCover(item: $pendingAlignmentSetup) { summary in
            CameraeNextRepeatableAlignmentSetupView(
                captureKind: summary.captureKind,
                settings: alignmentSettings(for: summary.captureKind)
            ) { settings in
                saveAlignmentSettings(settings, for: summary)
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

    private var standaloneCatalog: some View {
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
                sessionList(showsHeader: false)
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

    private var embeddedCatalog: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            sessionList(showsHeader: true)
        }
        .safeAreaInset(edge: .bottom) {
            CameraeNextActionButton(
                title: "Nova captura",
                systemImage: nil,
                theme: theme,
                action: onStartNew
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(theme.background.opacity(0.96))
        }
    }

    private func sessionList(showsHeader: Bool) -> some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if showsHeader {
                    captureListHeader
                }

                if let referenceFrameURL = catalog.referenceFrameURL {
                    referenceRow(referenceFrameURL)
                }

                if isFinalizingCapture {
                    finalizingCard
                }

                if catalog.sessions.isEmpty && !isFinalizingCapture {
                    emptyCaptures
                } else {
                    ForEach(catalog.sessions) { summary in
                        sessionRow(summary)
                    }
                }
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var captureListHeader: some View {
        HStack {
            Text("CAPTURAS")
                .foregroundStyle(theme.muted)
            Spacer()
            Text("\(catalog.sessions.count + (isFinalizingCapture ? 1 : 0)) SESSÕES")
                .foregroundStyle(theme.accent)
        }
        .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
        .tracking(2.7)
        .frame(height: 24)
    }

    private var emptyCaptures: some View {
        VStack(spacing: 10) {
            Text("0ƒ")
                .font(.custom("DMMono-Regular", size: 14, relativeTo: .body))
                .foregroundStyle(theme.accent)
                .frame(width: 72, height: 72)
                .background(theme.surface, in: Circle())

            Text("Nenhuma captura ainda")
                .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3))
                .foregroundStyle(theme.text)

            Text("Sua primeira sessão aparecerá aqui assim que uma imagem for salva.")
                .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                .foregroundStyle(theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 286)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
    }

    private var finalizingCard: some View {
        CameraeNextCard(theme: theme) {
            HStack(spacing: 12) {
                Text("•••")
                    .font(.custom("DMMono-Regular", size: 11, relativeTo: .caption))
                    .foregroundStyle(.white)
                    .frame(width: 78, height: 92)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.24, green: 0.03, blue: 0), theme.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Finalizando captura")
                        .font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
                        .foregroundStyle(theme.text)
                    Text("Salvando as imagens no projeto")
                        .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                        .foregroundStyle(theme.muted)
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(theme.accent)
                    Text("VOCÊ PODE CONTINUAR NAVEGANDO")
                        .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
                        .tracking(2.2)
                        .foregroundStyle(theme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: CameraeRadius.large, style: .continuous)
                .stroke(theme.accent, lineWidth: 1)
        }
    }

    private func referenceRow(_ imageURL: URL) -> some View {
        CameraeNextCard(theme: theme) {
            HStack(spacing: 12) {
                ReferenceThumbnail(
                    imageURL: imageURL,
                    systemImage: "photo",
                    width: 78,
                    height: 92
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Imagem de referência")
                        .font(.custom("Outfit-SemiBold", size: 14, relativeTo: .body))
                        .foregroundStyle(theme.text)
                    Text("REFERÊNCIA DO PROJETO")
                        .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
                        .tracking(2.2)
                        .foregroundStyle(theme.accent)
                    Text("Usada para alinhamento das próximas capturas")
                        .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                        .foregroundStyle(theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Imagem de referência do projeto")
    }

    private func sessionRow(_ summary: TimelapseSessionSummary) -> some View {
        let cardPresentation = CameraeNextSessionCardPresentation(summary: summary)
        return CameraeNextCard(theme: theme) {
            HStack(spacing: 12) {
                Button { open(summary) } label: {
                    HStack(spacing: 12) {
                    ReferenceThumbnail(
                        imageURL: summary.referenceFrameURL,
                        systemImage: project.module == .astrophotography ? "sparkles" : "camera.viewfinder",
                        width: 78,
                        height: 92
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(summary.session.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
                            .foregroundStyle(theme.text)
                        Text("\(summary.frameCount) imagens")
                            .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
                            .tracking(2.2)
                            .foregroundStyle(theme.accent)
                        Text(cardPresentation.statusText)
                            .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
                            .tracking(1.8)
                            .foregroundStyle(theme.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if renderingSessionID == summary.id {
                    ProgressView()
                        .tint(theme.accent)
                        .frame(width: 44, height: 44)
                } else {
                    trailingAction(cardPresentation.trailingAction, summary: summary)
                }
            }
        }
        .accessibilityLabel(sessionAccessibilityLabel(summary))
        .contextMenu {
            Button("Excluir", systemImage: "trash", role: .destructive) {
                pendingDeletion = summary.session
            }
        }
    }

    @ViewBuilder
    private func trailingAction(
        _ action: CameraeNextSessionTrailingAction,
        summary: TimelapseSessionSummary
    ) -> some View {
        switch action {
        case let .share(url):
            Button {
                shareItem = .init(url: url)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(theme.text)
                    .frame(width: 44, height: 44)
                    .background(theme.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Compartilhar vídeo")
        case let .videoMenu(url):
            Menu {
                Button("Processar alinhamento", systemImage: "viewfinder") {
                    guard catalog.referenceFrameURL != nil else {
                        errorMessage = "Adicione uma imagem de referência ao projeto antes de processar o alinhamento."
                        return
                    }
                    pendingVideoAlignmentConfirmation = summary
                }
                Button("Compartilhar", systemImage: "square.and.arrow.up") {
                    shareItem = .init(url: url)
                }
                Button("Excluir", systemImage: "trash", role: .destructive) {
                    pendingDeletion = summary.session
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(theme.text)
                    .frame(width: 44, height: 44)
                    .background(theme.surface, in: Circle())
            }
            .accessibilityLabel("Ações do vídeo")
        case .menu:
            Menu {
                if project.module == .repeatable, summary.captureKind == .timelapse {
                    Button("Gerar MP4", systemImage: "film") {
                        pendingVideoGeneration = summary
                    }
                }
                Button("Excluir", systemImage: "trash", role: .destructive) {
                    pendingDeletion = summary.session
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(theme.text)
                    .frame(width: 44, height: 44)
                    .background(theme.surface, in: Circle())
            }
            .accessibilityLabel("Ações da captura")
        }
    }

    private func open(_ summary: TimelapseSessionSummary) {
        switch CameraeNextSessionOpenRoute(summary: summary) {
        case let .video(url):
            selectedVideo = .init(url: url, title: playerTitle(summary))
        case .generateVideo:
            pendingVideoGeneration = summary
        case .astroProcessing:
            selectedAstroSession = summary
        }
    }

    private func playerTitle(_ summary: TimelapseSessionSummary) -> String {
        summary.captureKind == .video ? "Vídeo" : "Timelapse"
    }

    private var alignmentSettingsStore: CameraeNextRepeatableAlignmentSettingsStore {
        .init(projectDirectoryURL: project.directoryURL)
    }

    private func alignmentSettings(
        for captureKind: RepeatableCaptureKind
    ) -> CameraeNextRepeatableAlignmentSettings {
        do {
            return try alignmentSettingsStore.load(for: captureKind)
        } catch {
            return captureKind == .video ? .videoDefault : .timelapseDefault
        }
    }

    private func presentAlignmentSetup(afterDismissing summary: TimelapseSessionSummary) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            pendingAlignmentSetup = summary
        }
    }

    private func saveAlignmentSettings(
        _ settings: CameraeNextRepeatableAlignmentSettings,
        for summary: TimelapseSessionSummary
    ) {
        do {
            try alignmentSettingsStore.save(settings, for: summary.captureKind)
            pendingAlignmentSetup = nil
            if summary.captureKind == .timelapse {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    Task { await render(summary.session) }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sessionAccessibilityLabel(_ summary: TimelapseSessionSummary) -> String {
        switch CameraeNextSessionOpenRoute(summary: summary) {
        case .video:
            "Reproduzir vídeo da captura com \(summary.frameCount) imagens"
        case .generateVideo:
            "Gerar vídeo da captura com \(summary.frameCount) imagens"
        case .astroProcessing:
            "Abrir processamento Astro com \(summary.frameCount) imagens"
        }
    }

    @MainActor
    private func reload() async {
        do {
            summaries = try await store.sessionSummariesFromCatalog()
        } catch {
            errorMessage = error.localizedDescription
        }
        onCatalogLoaded()
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
            _ = try await store.renderVideo(for: session, settings: videoSettings)
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

private struct CameraeNextSessionVideoItem: Identifiable {
    let url: URL
    let title: String
    var id: String { url.absoluteString }
}

private struct CameraeNextSessionVideoPlayerView: View {
    let url: URL
    let title: String
    let onClose: () -> Void
    @State private var player: AVPlayer
    @State private var isSharing = false

    init(url: URL, title: String, onClose: @escaping () -> Void) {
        self.url = url
        self.title = title
        self.onClose = onClose
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            VideoPlayer(player: player)
                .ignoresSafeArea()

            HStack(spacing: 10) {
                playerToolbarButton("xmark", accessibilityLabel: "Fechar vídeo", action: onClose)

                Text(title)
                    .font(.custom("Outfit-SemiBold", size: 15, relativeTo: .headline))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)

                playerToolbarButton(
                    "square.and.arrow.up",
                    accessibilityLabel: "Compartilhar vídeo"
                ) {
                    isSharing = true
                }
            }
            .padding(16)
        }
        .statusBarHidden(true)
        .onAppear { player.play() }
        .onDisappear { player.pause() }
        .interactiveDismissDisabled()
        .sheet(isPresented: $isSharing) {
            ShareSheet(items: [url])
        }
    }

    private func playerToolbarButton(
        _ systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.13), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct CameraeNextGenerateVideoSheet: View {
    let theme: CameraeNextTheme
    let onGenerate: () -> Void
    let onCancel: () -> Void

    private let prompt = CameraeNextGenerateVideoPrompt()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "film")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(theme.accent, in: Circle())

            Text(prompt.title)
                .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3))
                .foregroundStyle(theme.text)

            Text(prompt.message)
                .font(.custom("Outfit-Regular", size: 13, relativeTo: .footnote))
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            CameraeNextActionButton(
                title: prompt.primaryActionTitle,
                systemImage: nil,
                theme: theme,
                action: onGenerate
            )

            CameraeNextActionButton(
                title: prompt.secondaryActionTitle,
                systemImage: nil,
                theme: theme,
                style: .secondary,
                action: onCancel
            )
        }
        .padding(20)
        .preferredColorScheme(theme.colorScheme)
    }
}

private struct CameraeNextProcessVideoAlignmentSheet: View {
    let theme: CameraeNextTheme
    let onProcess: () -> Void
    let onCancel: () -> Void

    private let prompt = CameraeNextProcessVideoAlignmentPrompt()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "viewfinder")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(theme.accent, in: Circle())

            Text(prompt.title)
                .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3))
                .foregroundStyle(theme.text)

            Text(prompt.message)
                .font(.custom("Outfit-Regular", size: 13, relativeTo: .footnote))
                .foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            CameraeNextActionButton(
                title: prompt.primaryActionTitle,
                systemImage: nil,
                theme: theme,
                action: onProcess
            )

            CameraeNextActionButton(
                title: prompt.secondaryActionTitle,
                systemImage: nil,
                theme: theme,
                style: .secondary,
                action: onCancel
            )
        }
        .padding(20)
        .preferredColorScheme(theme.colorScheme)
    }
}

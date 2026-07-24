import AVKit
import CameraeCore
import CameraeMedia
import SwiftUI

struct CameraeNextEditProjectView: View {
    @EnvironmentObject private var projectStore: ProjectStore
    @StateObject private var model: EditProjectViewModel
    @StateObject private var playback = EditPlaybackCoordinator()
    @StateObject private var alignment = CameraeNextAlignmentViewModel()

    @State private var isPresentingMediaPicker = false
    @State private var isPresentingAlignment = false
    @State private var isPresentingExport = false
    @State private var alignmentConfirmedForExport = false

    private let theme = CameraeNextTheme(workflow: .editor)

    init(project: CameraProject) {
        _model = StateObject(wrappedValue: EditProjectViewModel(project: project))
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 14) {
                    previewCard
                    canvasCard
                    timelineSection
                    actionSection
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(model.project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.background.opacity(0.96), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { isPresentingMediaPicker = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Adicionar mídia")

                Button { isPresentingExport = true } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(!model.canExport)
                .accessibilityLabel("Exportar vídeo")
            }
        }
        .tint(theme.accent)
        .preferredColorScheme(.dark)
        .task { await model.load() }
        .task(id: playbackSignature) { preparePlayback() }
        .task(id: alignmentSignature) { prepareAlignment() }
        .refreshable { await model.refreshMedia() }
        .sheet(isPresented: $isPresentingMediaPicker) {
            EditMediaPickerView(model: model) {
                projectStore.reload()
                prepareAlignment()
            }
        }
        .sheet(isPresented: $isPresentingAlignment) {
            if let document = model.document {
                NavigationStack {
                    CameraeNextAlignmentView(
                        model: alignment,
                        document: document,
                        assets: model.resolvedAssetsForExport,
                        projectReferenceURL: alignmentReferenceURL,
                        onUseAlignment: { alignmentConfirmedForExport = true },
                        onContinueWithoutAlignment: { alignmentConfirmedForExport = false }
                    )
                }
            }
        }
        .sheet(isPresented: $isPresentingExport) {
            if let document = model.document {
                CameraeNextEditExportView(
                    project: model.project,
                    document: document,
                    assets: model.resolvedAssetsForExport,
                    spatialAlignment: alignmentConfirmedForExport ? alignment.exportPlan : nil
                )
            }
        }
        .alert("Erro", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onDisappear { playback.tearDown() }
    }

    private var previewCard: some View {
        CameraeNextCard(theme: theme) {
            VStack(spacing: 12) {
                ZStack {
                    Color.black
                    if let player = playback.player, !playback.items.isEmpty {
                        VideoPlayer(player: player)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "play.rectangle")
                                .font(.system(size: 38, weight: .light))
                            Text(previewMessage)
                                .font(.custom("Outfit-Regular", size: 13, relativeTo: .subheadline))
                        }
                        .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .aspectRatio(model.document?.canvas == .portrait9x16 ? 9.0 / 16.0 : 16.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if !playback.items.isEmpty {
                    HStack(spacing: 28) {
                        Button { playback.restart() } label: {
                            Image(systemName: "backward.end.fill")
                        }
                        Button { playback.isPlaying ? playback.pause() : playback.play() } label: {
                            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title3)
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var canvasCard: some View {
        CameraeNextCard(theme: theme) {
            CameraeNextSettingRow(title: "Formato", helper: "Canvas da exportação", theme: theme) {
                Picker("Formato", selection: Binding(
                    get: { model.document?.canvas ?? .landscape16x9 },
                    set: { canvas in Task { await model.setCanvas(canvas) } }
                )) {
                    Text("16:9").tag(EditCanvas.landscape16x9)
                    Text("9:16").tag(EditCanvas.portrait9x16)
                }
                .pickerStyle(.segmented)
                .frame(width: 132)
            }
        }
    }

    @ViewBuilder
    private var timelineSection: some View {
        VStack(spacing: 8) {
            HStack {
                CameraeNextSectionLabel(title: "Sequência", theme: theme)
                Spacer()
                Text("\(model.document?.items.count ?? 0) CLIPES")
                    .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
                    .tracking(1.3)
                    .foregroundStyle(theme.accent)
            }

            if let items = model.document?.items, !items.isEmpty {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    timelineRow(item, index: index, count: items.count)
                }
            } else if model.isLoading {
                ProgressView("Carregando montagem")
                    .tint(theme.accent)
                    .foregroundStyle(theme.text)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                CameraeNextCard(theme: theme) {
                    ContentUnavailableView(
                        "Sequência vazia",
                        systemImage: "film.stack",
                        description: Text("Adicione vídeos produzidos no Camerae.")
                    )
                    .foregroundStyle(theme.text)
                }
            }
        }
    }

    private func timelineRow(_ item: EditTimelineItem, index: Int, count: Int) -> some View {
        let resolved = model.resolvedAsset(for: item)
        return CameraeNextCard(theme: theme) {
            HStack(spacing: 12) {
                Text("\(index + 1)")
                    .font(.custom("DMMono-Regular", size: 11, relativeTo: .caption))
                    .foregroundStyle(theme.muted)
                    .frame(width: 22)

                ReferenceThumbnail(
                    imageURL: resolved?.url,
                    systemImage: resolved == nil ? "exclamationmark.triangle" : "film",
                    width: 76,
                    height: 52
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(resolved?.descriptor.projectName ?? "Mídia indisponível")
                        .font(.custom("Outfit-SemiBold", size: 14, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Text(resolved.map { mediaDescription($0.descriptor) } ?? item.asset.relativePath)
                        .font(.custom("Outfit-Regular", size: 11, relativeTo: .caption))
                        .foregroundStyle(resolved == nil ? Color.red : theme.muted)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                Menu {
                    Button("Mover para cima", systemImage: "arrow.up") {
                        Task { await model.moveItem(from: index, to: max(0, index - 1)) }
                    }
                    .disabled(index == 0)
                    Button("Mover para baixo", systemImage: "arrow.down") {
                        Task { await model.moveItem(from: index, to: min(count - 1, index + 1)) }
                    }
                    .disabled(index == count - 1)
                    Button("Remover", systemImage: "trash", role: .destructive) {
                        Task { await model.removeItem(at: index) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 34, height: 34)
                        .background(theme.surface, in: Circle())
                }
            }
        }
    }

    private var actionSection: some View {
        VStack(spacing: 10) {
            CameraeNextActionButton(
                title: alignmentButtonTitle,
                systemImage: "viewfinder",
                theme: theme,
                style: .secondary,
                isDisabled: !model.canExport
            ) {
                prepareAlignment()
                isPresentingAlignment = true
            }

            CameraeNextActionButton(
                title: alignmentConfirmedForExport ? "Exportar com alinhamento" : "Exportar MP4",
                systemImage: "square.and.arrow.up",
                theme: theme,
                isDisabled: !model.canExport
            ) {
                isPresentingExport = true
            }
        }
    }

    private var alignmentButtonTitle: String {
        switch alignment.snapshot.status {
        case .applied: "Alinhamento aplicado"
        case .review: "Revisar alinhamento"
        case .stale: "Atualizar alinhamento"
        default: "Alinhar imagens"
        }
    }

    private var playbackSignature: String {
        (model.document?.items ?? []).map { item in
            "\(item.id.uuidString):\(model.resolvedAsset(for: item)?.url.path ?? "missing")"
        }.joined(separator: "|")
    }

    private var alignmentSignature: String {
        [
            (model.document?.items ?? []).map(\.id.uuidString).joined(separator: "|"),
            alignmentReferenceURL?.standardizedFileURL.path ?? "no-reference"
        ].joined(separator: "|")
    }

    private var alignmentReferenceURL: URL? {
        guard let sourceProjectID = model.document?.items.first?.asset.projectID else {
            return nil
        }
        return projectStore.projects.first(where: { $0.id == sourceProjectID })?.referenceFrameURL
    }

    private var previewMessage: String {
        let items = model.document?.items ?? []
        if items.isEmpty { return "Adicione clipes para reproduzir" }
        if items.contains(where: { model.resolvedAsset(for: $0) == nil }) {
            return "Há mídias indisponíveis na sequência"
        }
        return "Preparando preview"
    }

    private func preparePlayback() {
        let timeline = model.document?.items ?? []
        let items = timeline.compactMap { item -> EditPlaybackItem? in
            guard let resolved = model.resolvedAsset(for: item) else { return nil }
            return EditPlaybackItem(id: item.id, url: resolved.url)
        }
        guard items.count == timeline.count else {
            playback.tearDown()
            return
        }
        playback.prepare(items: items)
    }

    private func prepareAlignment() {
        guard let document = model.document else { return }
        alignment.prepare(
            document: document,
            assets: model.resolvedAssetsForExport,
            projectReferenceURL: alignmentReferenceURL
        )
        if alignment.snapshot.status == .stale {
            alignmentConfirmedForExport = false
        }
    }

    private func mediaDescription(_ asset: MediaAssetDescriptor) -> String {
        let type = asset.reference.kind == .repeatableVideo ? "Vídeo" : "Timelapse"
        return "\(type) • \(asset.duration.formatted(.number.precision(.fractionLength(1)))) s"
    }
}

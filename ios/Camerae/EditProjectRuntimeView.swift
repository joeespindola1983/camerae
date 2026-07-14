import CameraeCore
import AVKit
import SwiftUI

struct EditProjectRuntimeView: View {
    @EnvironmentObject private var projectStore: ProjectStore
    @StateObject private var model: EditProjectViewModel
    @StateObject private var playback = EditPlaybackCoordinator()
    @State private var isPresentingMediaPicker = false
    @State private var isPresentingExport = false

    init(project: CameraProject) {
        _model = StateObject(wrappedValue: EditProjectViewModel(project: project))
    }

    var body: some View {
        List {
            Section {
                previewPlaceholder
                canvasPicker
            }

            Section("Sequência") {
                if let items = model.document?.items, !items.isEmpty {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        timelineRow(item, index: index)
                    }
                    .onMove { offsets, destination in
                        Task {
                            await model.moveItems(from: offsets, to: destination)
                            projectStore.reload()
                        }
                    }
                    .onDelete { offsets in
                        Task {
                            await model.removeItems(at: offsets)
                            projectStore.reload()
                        }
                    }
                } else if model.isLoading {
                    HStack {
                        ProgressView()
                        Text("Carregando montagem")
                    }
                } else {
                    ContentUnavailableView(
                        "Sequência vazia",
                        systemImage: "film.stack",
                        description: Text("Adicione vídeos produzidos no Camerae.")
                    )
                }
            }

            Section {
                Button {
                    isPresentingMediaPicker = true
                } label: {
                    Label("Adicionar mídia", systemImage: "plus.rectangle.on.rectangle")
                }
                .disabled(model.isLoading || model.isSaving)

                Button { isPresentingExport = true } label: {
                    Label("Exportar MP4", systemImage: "square.and.arrow.up")
                }
                .disabled(!model.canExport || model.isSaving)
            }
        }
        .navigationTitle(model.project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
        .task {
            await model.load()
        }
        .task(id: playbackSignature) {
            preparePlayback()
        }
        .refreshable {
            await model.refreshMedia()
        }
        .sheet(isPresented: $isPresentingMediaPicker) {
            EditMediaPickerView(model: model) {
                projectStore.reload()
            }
        }
        .sheet(isPresented: $isPresentingExport) {
            if let document = model.document {
                EditExportView(
                    project: model.project,
                    document: document,
                    assets: model.resolvedAssetsForExport
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
        .onDisappear {
            playback.tearDown()
        }
    }

    private var previewPlaceholder: some View {
        VStack(spacing: 10) {
            ZStack {
                Color.black
                if let player = playback.player, !playback.items.isEmpty {
                    VideoPlayer(player: player)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "play.rectangle")
                            .font(.system(size: 38, weight: .light))
                        Text(previewMessage)
                            .font(.subheadline)
                    }
                    .foregroundStyle(.white.opacity(0.72))
                }
            }
            .aspectRatio(model.document?.canvas == .portrait9x16 ? 9.0 / 16.0 : 16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !playback.items.isEmpty {
                HStack(spacing: 28) {
                    Button {
                        playback.restart()
                    } label: {
                        Image(systemName: "backward.end.fill")
                    }
                    Button {
                        playback.isPlaying ? playback.pause() : playback.play()
                    } label: {
                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                    }
                    .accessibilityLabel(playback.isPlaying ? "Pausar sequência" : "Reproduzir sequência")
                }
                .buttonStyle(.borderless)
            }
        }
        .accessibilityLabel("Preview da sequência")
    }

    private var canvasPicker: some View {
        Picker("Formato", selection: Binding(
            get: { model.document?.canvas ?? .landscape16x9 },
            set: { canvas in Task { await model.setCanvas(canvas) } }
        )) {
            Text("Horizontal").tag(EditCanvas.landscape16x9)
            Text("Vertical").tag(EditCanvas.portrait9x16)
        }
        .pickerStyle(.segmented)
    }

    private func timelineRow(_ item: EditTimelineItem, index: Int) -> some View {
        let resolved = model.resolvedAsset(for: item)
        return HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            ReferenceThumbnail(
                imageURL: resolved?.url,
                systemImage: resolved == nil ? "exclamationmark.triangle" : "film",
                width: 76,
                height: 52
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(resolved?.descriptor.projectName ?? "Mídia indisponível")
                    .font(.headline)
                    .lineLimit(1)
                Text(resolved.map { mediaDescription($0.descriptor) } ?? item.asset.relativePath)
                    .font(.caption)
                    .foregroundStyle(resolved == nil ? .red : .secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityIdentifier("edit-timeline-item-\(index)")
        .listRowBackground(playback.highlightedItemID == item.id ? Color.accentColor.opacity(0.14) : nil)
    }

    private func mediaDescription(_ asset: MediaAssetDescriptor) -> String {
        let type = asset.reference.kind == .repeatableVideo ? "Vídeo" : "Timelapse"
        return "\(type) • \(asset.duration.formatted(.number.precision(.fractionLength(1)))) s"
    }

    private var playbackSignature: String {
        (model.document?.items ?? []).map { item in
            "\(item.id.uuidString):\(model.resolvedAsset(for: item)?.url.path ?? "missing")"
        }.joined(separator: "|")
    }

    private var previewMessage: String {
        let items = model.document?.items ?? []
        if items.isEmpty { return "Adicione clips para reproduzir" }
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
}

private struct EditMediaPickerView: View {
    @ObservedObject var model: EditProjectViewModel
    let onAdded: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Filtros") {
                    Picker("Origem", selection: originBinding) {
                        ForEach(EditOriginChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Tipo", selection: kindBinding) {
                        ForEach(EditKindChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }

                    if !model.sourceProjects.isEmpty {
                        Picker("Projeto", selection: projectBinding) {
                            Text("Todos").tag(UUID?.none)
                            ForEach(model.sourceProjects, id: \.id) { project in
                                Text(project.name).tag(Optional(project.id))
                            }
                        }
                    }
                }

                Section("Mídias") {
                    if model.filteredAssets.isEmpty {
                        Text("Nenhuma mídia pronta encontrada para estes filtros.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.filteredAssets, id: \.reference.id) { asset in
                            mediaRow(asset)
                        }
                    }
                }
            }
            .navigationTitle("Adicionar mídia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Adicionar (\(model.selectedAssetIDs.count))") {
                        Task {
                            await model.addSelection()
                            onAdded()
                            dismiss()
                        }
                    }
                    .disabled(model.selectedAssetIDs.isEmpty || model.isSaving)
                }
            }
        }
    }

    private func mediaRow(_ asset: MediaAssetDescriptor) -> some View {
        let selected = model.selectedAssetIDs.contains(asset.reference.id)
        let resolved = model.resolvedLibraryAsset(id: asset.reference.id)
        return Button {
            model.toggleSelection(asset.reference.id)
        } label: {
            HStack(spacing: 12) {
                ReferenceThumbnail(
                    imageURL: resolved?.url,
                    systemImage: "film",
                    width: 92,
                    height: 58
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(asset.projectName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(asset.sourceModule == .astrophotography ? "Astro" : "Repeatable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(asset.duration.formatted(.number.precision(.fractionLength(1)))) s")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("edit-media-\(asset.reference.id.rawValue)")
    }

    private var originBinding: Binding<EditOriginChoice> {
        Binding(
            get: { EditOriginChoice(filter: model.filter.origin) },
            set: { model.filter.origin = $0.filter }
        )
    }

    private var kindBinding: Binding<EditKindChoice> {
        Binding(
            get: { EditKindChoice(filter: model.filter.kind) },
            set: { model.filter.kind = $0.filter }
        )
    }

    private var projectBinding: Binding<UUID?> {
        Binding(
            get: { model.filter.projectID },
            set: { model.filter.projectID = $0 }
        )
    }
}

private enum EditOriginChoice: String, CaseIterable, Identifiable {
    case all
    case repeatable
    case astro

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "Todos"
        case .repeatable: return "Repeatable"
        case .astro: return "Astro"
        }
    }
    var filter: MediaOriginFilter {
        switch self {
        case .all: return .all
        case .repeatable: return .module(.repeatable)
        case .astro: return .module(.astrophotography)
        }
    }
    init(filter: MediaOriginFilter) {
        switch filter {
        case .module(.repeatable): self = .repeatable
        case .module(.astrophotography): self = .astro
        default: self = .all
        }
    }
}

private enum EditKindChoice: String, CaseIterable, Identifiable {
    case all
    case timelapse
    case video

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "Todos"
        case .timelapse: return "Timelapse"
        case .video: return "Vídeo"
        }
    }
    var filter: MediaKindFilter {
        switch self {
        case .all: return .all
        case .timelapse: return .timelapse
        case .video: return .recordedVideo
        }
    }
    init(filter: MediaKindFilter) {
        switch filter {
        case .all: self = .all
        case .timelapse: self = .timelapse
        case .recordedVideo: self = .video
        }
    }
}

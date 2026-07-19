import CameraeCore
import CameraeMedia
import SwiftUI

struct CameraeNextEditExportPresentation: Equatable, Sendable {
    let resolution: String
    let clipCount: String
    let duration: String
    let alignment: String

    init(canvas: EditCanvas, clipCount: Int, duration: TimeInterval, usesAlignment: Bool) {
        resolution = canvas == .portrait9x16 ? "1080 × 1920" : "1920 × 1080"
        self.clipCount = "\(clipCount)"
        let seconds = max(Int(duration), 0)
        self.duration = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        alignment = usesAlignment ? "Aplicado" : "Desligado"
    }
}

struct CameraeNextEditExportView: View {
    let document: EditProjectDocument
    let assets: [MediaAssetID: ResolvedMediaAsset]
    let spatialAlignment: EditSpatialAlignmentPlan?

    @StateObject private var model: EditExportViewModel
    @Environment(\.dismiss) private var dismiss

    private let theme = CameraeNextTheme(workflow: .editor)

    init(
        project: CameraProject,
        document: EditProjectDocument,
        assets: [MediaAssetID: ResolvedMediaAsset],
        spatialAlignment: EditSpatialAlignmentPlan? = nil
    ) {
        self.document = document
        self.assets = assets
        self.spatialAlignment = spatialAlignment
        _model = StateObject(wrappedValue: EditExportViewModel(project: project))
    }

    private var presentation: CameraeNextEditExportPresentation {
        .init(
            canvas: document.canvas,
            clipCount: document.items.count,
            duration: assets.values.reduce(0) { $0 + $1.descriptor.duration },
            usesAlignment: spatialAlignment != nil
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        outputHero
                        outputDetails

                        if let outputURL = model.outputURL {
                            CameraeNextCard(theme: theme) {
                                VStack(spacing: 14) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 34))
                                        .foregroundStyle(theme.accent)
                                    Text("MP4 exportado com sucesso")
                                        .font(.custom("Outfit-SemiBold", size: 16, relativeTo: .headline))
                                        .foregroundStyle(theme.text)
                                    ShareLink(item: outputURL) {
                                        Label("Compartilhar vídeo", systemImage: "square.and.arrow.up")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(theme.accent)
                                }
                            }
                        } else {
                            CameraeNextActionButton(
                                title: "Exportar MP4",
                                systemImage: "film",
                                theme: theme,
                                isDisabled: model.isExporting
                            ) {
                                Task {
                                    await model.export(
                                        document: document,
                                        assets: assets,
                                        spatialAlignment: spatialAlignment
                                    )
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 520)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                }

                CameraeNextOperationOverlay(
                    state: model.isExporting
                        ? .processing(
                            title: "Exportando vídeo",
                            detail: model.progress.formatted(.percent.precision(.fractionLength(0))),
                            canCancel: true
                        )
                        : .idle,
                    theme: theme,
                    onCancel: model.cancel
                )
            }
            .navigationTitle("Exportar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.background.opacity(0.96), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                        .disabled(model.isExporting)
                }
            }
            .alert("Não foi possível exportar", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
        .tint(theme.accent)
        .preferredColorScheme(.dark)
    }

    private var outputHero: some View {
        CameraeNextCard(theme: theme) {
            HStack(spacing: 16) {
                Image(systemName: "film.stack")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .frame(width: 58, height: 58)
                    .background(theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Vídeo final")
                        .font(.custom("Outfit-SemiBold", size: 19, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                    Text("MP4 · 30 fps · \(presentation.resolution)")
                        .font(.custom("DMMono-Regular", size: 11, relativeTo: .caption))
                        .foregroundStyle(theme.muted)
                }
                Spacer()
            }
        }
    }

    private var outputDetails: some View {
        CameraeNextCard(theme: theme) {
            VStack(spacing: 0) {
                detailRow("Resolução", presentation.resolution)
                detailRow("Clipes", presentation.clipCount)
                detailRow("Duração", presentation.duration)
                detailRow("Alinhamento", presentation.alignment, isLast: true)
            }
        }
    }

    private func detailRow(_ title: String, _ value: String, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .foregroundStyle(theme.muted)
                Spacer()
                Text(value)
                    .font(.custom("DMMono-Regular", size: 12, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
            }
            .font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
            .padding(.vertical, 12)
            if !isLast { Divider().overlay(theme.border) }
        }
    }
}

import CameraeCore
import CameraeMedia
import SwiftUI

struct EditExportView: View {
    let document: EditProjectDocument
    let assets: [MediaAssetID: ResolvedMediaAsset]
    let spatialAlignment: EditSpatialAlignmentPlan?
    @StateObject private var model: EditExportViewModel
    @Environment(\.dismiss) private var dismiss

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

    var body: some View {
        NavigationStack {
            Form {
                Section("Arquivo final") {
                    LabeledContent("Formato", value: "MP4")
                    LabeledContent("Resolução", value: document.canvas == .portrait9x16 ? "1080 × 1920" : "1920 × 1080")
                    LabeledContent("Quadros", value: "30 fps")
                    LabeledContent("Clipes", value: "\(document.items.count)")
                    LabeledContent("Duração", value: durationDescription)
                    LabeledContent("Alinhamento", value: spatialAlignment == nil ? "Desligado" : "Aplicado")
                }

                if model.isExporting {
                    Section("Exportando") {
                        ProgressView(value: model.progress)
                        Text(model.progress.formatted(.percent.precision(.fractionLength(0))))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button("Cancelar exportação", role: .cancel) { model.cancel() }
                    }
                } else if let outputURL = model.outputURL {
                    Section("Pronto") {
                        Label("MP4 exportado com sucesso", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        ShareLink(item: outputURL) {
                            Label("Compartilhar vídeo", systemImage: "square.and.arrow.up")
                        }
                    }
                } else {
                    Section {
                        Button {
                            Task {
                                await model.export(
                                    document: document,
                                    assets: assets,
                                    spatialAlignment: spatialAlignment
                                )
                            }
                        } label: {
                            Label("Exportar MP4", systemImage: "film")
                        }
                    } footer: {
                        Text(spatialAlignment == nil
                            ? "Os clipes serão unidos na ordem da sequência, sem alinhamento espacial."
                            : "O plano de alinhamento e o crop comum serão aplicados à exportação.")
                    }
                }
            }
            .navigationTitle("Exportar")
            .navigationBarTitleDisplayMode(.inline)
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
    }

    private var durationDescription: String {
        let seconds = assets.values.reduce(0) { $0 + $1.descriptor.duration }
        let minutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }
}

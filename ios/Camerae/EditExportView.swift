import CameraeCore
import CameraeMedia
import SwiftUI

struct EditExportView: View {
    let document: EditProjectDocument
    let assets: [MediaAssetID: ResolvedMediaAsset]
    @StateObject private var model: EditExportViewModel
    @Environment(\.dismiss) private var dismiss

    init(
        project: CameraProject,
        document: EditProjectDocument,
        assets: [MediaAssetID: ResolvedMediaAsset]
    ) {
        self.document = document
        self.assets = assets
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
                            Task { await model.export(document: document, assets: assets) }
                        } label: {
                            Label("Exportar MP4", systemImage: "film")
                        }
                    } footer: {
                        Text("Os clipes serão unidos na ordem da sequência, preservando o áudio disponível.")
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

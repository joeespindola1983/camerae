import SwiftUI

struct AstroProcessingView: View {
    let session: TimelapseSession
    let onComplete: () -> Void
    let onDeleteProject: () throws -> Void

    @StateObject private var processor: AstroProcessingController
    @State private var stackSize = 10.0
    @State private var fps = 24.0
    @State private var isConfirmingProjectDelete = false
    @State private var deleteErrorMessage: String?
    @Environment(\.dismiss) private var dismiss

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
        processor.outputFrameCount(stackSize: Int(stackSize))
    }

    private var maxStackSize: Int {
        max(processor.originalFrameCount, 1)
    }

    private var videoDuration: Double {
        guard fps > 0 else { return 0 }
        return Double(outputFrameCount) / fps
    }

    var body: some View {
        List {
            Section("Captura") {
                LabeledContent("Fotos originais", value: "\(processor.originalFrameCount)")
                LabeledContent("Sessao", value: session.name)
            }

            Section("Stacking") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Imagens por stack")
                        Spacer()
                        Text("\(min(Int(stackSize), maxStackSize))")
                            .font(.system(.body, design: .monospaced, weight: .semibold))
                    }

                    if processor.originalFrameCount > 1 {
                        Slider(value: $stackSize, in: 1...Double(processor.originalFrameCount), step: 1)
                    } else {
                        Text("Capture pelo menos 2 fotos para escolher um tamanho de stack.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Frames processados", value: "\(outputFrameCount)")
            }

            Section("Video") {
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

            Section {
                Button {
                    Task {
                        await processor.renderStacks(stackSize: Int(stackSize), fps: Int(fps))
                    }
                } label: {
                    Label(processor.isRendering ? "Processando..." : "Iniciar processo astro", systemImage: "sparkles")
                }
                .disabled(processor.isRendering || processor.originalFrameCount == 0)

                if let lastRenderURL = processor.lastRenderURL {
                    Text(lastRenderURL.lastPathComponent)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button("Concluir") {
                    onComplete()
                    dismiss()
                }
                .disabled(processor.isRendering)
            } footer: {
                Text(processor.status)
            }

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
        .navigationTitle("Processo astro")
        .navigationBarTitleDisplayMode(.inline)
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
        .alert("Nao foi possivel excluir", isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        .task {
            processor.reload()
            clampStackSize()
        }
        .onChange(of: processor.originalFrameCount) {
            clampStackSize()
        }
    }

    private func clampStackSize() {
        let upper = maxStackSize
        stackSize = Double(min(max(Int(stackSize), 1), upper))

        if processor.originalFrameCount > 1 {
            stackSize = Double(min(10, processor.originalFrameCount))
        }
    }

    private func deleteProject() {
        do {
            try onDeleteProject()
            dismiss()
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }
}

@MainActor
final class AstroProcessingController: ObservableObject {
    @Published private(set) var originalFrameCount = 0
    @Published private(set) var status = "Pronto para processar"
    @Published private(set) var isRendering = false
    @Published private(set) var lastRenderURL: URL?

    private let session: TimelapseSession
    private let fileManager = FileManager.default
    private let stacker = ExposureStacker()

    init(session: TimelapseSession) {
        self.session = session
    }

    func reload() {
        originalFrameCount = originalFrames().count
    }

    func outputFrameCount(stackSize: Int) -> Int {
        let size = max(stackSize, 1)
        return originalFrameCount / size
    }

    func renderStacks(stackSize: Int, fps: Int) async {
        let size = max(stackSize, 1)
        let frames = originalFrames()
        guard !frames.isEmpty else {
            status = "Nenhum frame original encontrado"
            return
        }

        isRendering = true
        status = "Preparando render"

        do {
            let renderURL = try createRenderDirectory(stackSize: size, fps: fps)
            let groups = frames.chunked(into: size).filter { $0.count == size }

            for (index, group) in groups.enumerated() {
                status = "Stack \(index + 1)/\(groups.count)"
                let data = try stacker.averageJPEGs(group.map { try Data(contentsOf: $0) })
                let outputURL = renderURL.appendingPathComponent(String(format: "stack_%06d.jpg", index + 1))
                try data.write(to: outputURL, options: [.atomic])
            }

            try writeRenderManifest(renderURL: renderURL, stackSize: size, fps: fps, outputFrames: groups.count)
            lastRenderURL = renderURL
            status = "Render pronto: \(groups.count) frames"
        } catch {
            status = "Falha no processo: \(error.localizedDescription)"
        }

        isRendering = false
        reload()
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

    private func createRenderDirectory(stackSize: Int, fps: Int) throws -> URL {
        let rendersURL = session.directoryURL.appendingPathComponent("Astro Renders", isDirectory: true)
        try fileManager.createDirectory(at: rendersURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"

        let name = "stack_\(stackSize)_fps_\(fps)_\(formatter.string(from: Date()))"
        let renderURL = rendersURL.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: renderURL, withIntermediateDirectories: true)
        return renderURL
    }

    private func writeRenderManifest(renderURL: URL, stackSize: Int, fps: Int, outputFrames: Int) throws {
        let manifest: [String: Any] = [
            "sourceSessionId": session.id.uuidString,
            "sourceFrameCount": originalFrameCount,
            "stackSize": stackSize,
            "fps": fps,
            "outputFrameCount": outputFrames,
            "estimatedVideoDuration": fps > 0 ? Double(outputFrames) / Double(fps) : 0
        ]

        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: renderURL.appendingPathComponent("render.json"), options: [.atomic])
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

import SwiftUI
import UIKit

struct AstroImageLabView: View {
    @ObservedObject var processor: AstroProcessingController
    let initialStackSize: Int
    let initialStackingStartFrame: Int
    let initialSettings: AstroImageProcessingSettings
    let apply: (Int, AstroImageProcessingSettings) -> Void

    @State private var stackSize: Double
    @State private var selectedPreset = 10
    @State private var settings: AstroImageProcessingSettings
    @State private var previewURL: URL?
    @State private var isRenderingPreview = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private static let presetStackSizes = [5, 10, 15, 30]

    init(
        processor: AstroProcessingController,
        initialStackSize: Int,
        initialStackingStartFrame: Int,
        initialSettings: AstroImageProcessingSettings,
        apply: @escaping (Int, AstroImageProcessingSettings) -> Void
    ) {
        self.processor = processor
        self.initialStackSize = initialStackSize
        self.initialStackingStartFrame = initialStackingStartFrame
        self.initialSettings = initialSettings
        self.apply = apply
        _stackSize = State(initialValue: Double(initialStackSize))
        _selectedPreset = State(initialValue: Self.presetStackSizes.contains(initialStackSize) ? initialStackSize : 10)
        _settings = State(initialValue: initialSettings)
    }

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                stackSection
                processingSection
                actionsSection
            }
            .navigationTitle("Laboratorio astro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fechar") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if isRenderingPreview {
                    BlockingProgressOverlay(
                        title: "Gerando preview",
                        message: "Processando a imagem de referencia",
                        detail: "\(Int(stackSize)) frames"
                    )
                }
            }
            .alert("Nao foi possivel gerar preview", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                await renderPreview()
            }
            .onChange(of: selectedPreset) {
                stackSize = Double(selectedPreset)
                Task {
                    await renderPreview()
                }
            }
            .onChange(of: settings.profile) {
                settings = .defaults(for: settings.profile)
                Task {
                    await renderPreview()
                }
            }
        }
    }

    private var previewSection: some View {
        Section("Imagem de referencia") {
            ZStack {
                Rectangle()
                    .fill(.quaternary)

                if let previewURL, let image = UIImage(contentsOfFile: previewURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ContentUnavailableView("Sem preview", systemImage: "photo")
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            LabeledContent("Frames usados", value: "\(previewFrameCount)")
            LabeledContent("Inicio", value: "\(initialStackingStartFrame)")
        }
    }

    private var stackSection: some View {
        Section("Stack") {
            Picker("Teste rapido", selection: $selectedPreset) {
                ForEach(Self.presetStackSizes, id: \.self) { size in
                    Text("\(size)").tag(size)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Imagens")
                    Spacer()
                    Text("\(Int(stackSize))")
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                }
                Slider(value: $stackSize, in: 2...Double(maxStackSize), step: 1)
            }

            Button {
                Task {
                    await renderPreview()
                }
            } label: {
                Label("Atualizar preview", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(isRenderingPreview || previewFrameCount == 0)
        }
    }

    private var processingSection: some View {
        Section("Tratamento") {
            Picker("Perfil", selection: Binding(
                get: { settings.profile },
                set: { settings.profile = $0 }
            )) {
                ForEach(AstroProcessingProfile.allCases) { profile in
                    Text(profile.title).tag(profile)
                }
            }
            .pickerStyle(.segmented)

            Toggle(isOn: Binding(
                get: { settings.appliesDenoise },
                set: { settings.appliesDenoise = $0 }
            )) {
                Text("Reducao de ruido")
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Ruido")
                    Spacer()
                    Text(String(format: "%.3f", settings.noiseLevel))
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                }
                Slider(
                    value: Binding(
                        get: { Double(settings.noiseLevel) },
                        set: { settings.noiseLevel = Float($0) }
                    ),
                    in: 0...0.08,
                    step: 0.005
                )
            }
            .disabled(!settings.appliesDenoise)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Nitidez")
                    Spacer()
                    Text(String(format: "%.2f", settings.sharpness))
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                }
                Slider(
                    value: Binding(
                        get: { Double(settings.sharpness) },
                        set: { settings.sharpness = Float($0) }
                    ),
                    in: 0...1,
                    step: 0.05
                )
            }
            .disabled(!settings.appliesDenoise)
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                Task {
                    await renderPreview()
                }
            } label: {
                Label("Testar combinacao", systemImage: "wand.and.stars")
            }
            .disabled(isRenderingPreview || previewFrameCount == 0)

            Button {
                apply(Int(stackSize), settings)
                dismiss()
            } label: {
                Label("Aplicar no render", systemImage: "checkmark.circle")
            }
            .disabled(isRenderingPreview || previewFrameCount == 0)
        } footer: {
            Text("O preview usa os frames originais a partir do inicio escolhido. Nada e gravado sobre os originais.")
        }
    }

    private var maxStackSize: Int {
        max(min(processor.originalFrameCount, 120), 2)
    }

    private var previewFrameCount: Int {
        processor.previewReferenceFrameCount(
            stackSize: Int(stackSize),
            stackingStartFrame: initialStackingStartFrame
        )
    }

    private func renderPreview() async {
        guard !isRenderingPreview else { return }
        guard previewFrameCount > 0 else { return }

        isRenderingPreview = true

        do {
            previewURL = try await processor.renderReferencePreview(
                stackSize: Int(stackSize),
                stackingStartFrame: initialStackingStartFrame,
                settings: settings
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isRenderingPreview = false
    }
}

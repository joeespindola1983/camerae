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
    @State private var referenceURL: URL?
    @State private var previewMode: PreviewMode = .processed
    @State private var isShowingPreviewDetail = false
    @State private var isRenderingPreview = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private static let presetStackSizes = [5, 10, 15, 30]

    private enum PreviewMode: String, CaseIterable, Identifiable {
        case processed
        case reference

        var id: String { rawValue }

        var title: String {
            switch self {
            case .processed:
                return "Processada"
            case .reference:
                return "Original"
            }
        }
    }

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
            VStack(spacing: 0) {
                previewPanel
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
                    .overlay(alignment: .bottom) {
                        Divider()
                    }

                Form {
                    stackSection
                    processingSection
                    localAdjustmentsSection
                    actionsSection
                }
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
            .fullScreenCover(isPresented: $isShowingPreviewDetail) {
                if let imageURL = displayedPreviewURL, let image = UIImage(contentsOfFile: imageURL.path) {
                    AstroPreviewDetailView(image: image)
                }
            }
            .task {
                await renderPreview()
            }
            .onChange(of: selectedPreset) {
                stackSize = Double(selectedPreset)
            }
            .onChange(of: settings.profile) {
                applyDefaultsForCurrentProfile()
                Task {
                    await renderPreview()
                }
            }
        }
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Preview", selection: $previewMode) {
                ForEach(PreviewMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            ZStack {
                Rectangle()
                    .fill(.quaternary)

                if let imageURL = displayedPreviewURL, let image = UIImage(contentsOfFile: imageURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ContentUnavailableView("Sem preview", systemImage: "photo")
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            Task {
                                await renderPreview()
                            }
                        } label: {
                            Label("Atualizar", systemImage: "arrow.triangle.2.circlepath")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRenderingPreview || previewFrameCount == 0)
                    }
                    .padding(12)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                if displayedPreviewURL != nil {
                    isShowingPreviewDetail = true
                }
            }

            HStack {
                LabeledContent("Frames", value: "\(previewFrameCount)")
                Spacer()
                LabeledContent("Inicio", value: "\(initialStackingStartFrame)")
                Button {
                    isShowingPreviewDetail = true
                } label: {
                    Label("Tela cheia", systemImage: "arrow.up.left.and.arrow.down.right")
                        .labelStyle(.iconOnly)
                }
                .disabled(displayedPreviewURL == nil)
            }
        }
    }

    private var stackSection: some View {
        Section("Stack") {
            Picker("Backend", selection: Binding(
                get: { settings.stackingBackend },
                set: { updateStackingBackend($0) }
            )) {
                ForEach(AstroStackingBackend.allCases) { backend in
                    Text(backend.title).tag(backend)
                }
            }
            .pickerStyle(.segmented)

            Picker("Teste rapido", selection: $selectedPreset) {
                ForEach(Self.presetStackSizes, id: \.self) { size in
                    Text("\(size)").tag(size)
                }
            }
            .pickerStyle(.segmented)

            Toggle(isOn: Binding(
                get: { settings.alignsStars },
                set: { settings.alignsStars = $0 }
            )) {
                Text("Alinhar estrelas")
            }
            .disabled(settings.stackingBackend != .openCV)

            if settings.stackingBackend != .openCV {
                Text("Alinhamento de estrelas fica disponivel apenas com OpenCV.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Imagens")
                    Spacer()
                    Text("\(Int(stackSize))")
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                }
                Slider(value: $stackSize, in: 2...Double(maxStackSize), step: 1)
            }
        }
    }

    private var processingSection: some View {
        Section("Tratamento") {
            Picker("Preset", selection: Binding(
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

            Picker("Motor", selection: Binding(
                get: { settings.denoiseBackend },
                set: { settings.denoiseBackend = $0 }
            )) {
                ForEach(AstroDenoiseBackend.allCases) { backend in
                    Text(backend.title).tag(backend)
                }
            }
            .disabled(!settings.appliesDenoise)

            LabeledContent("OpenCV", value: OpenCVBridge.versionString())

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
            .disabled(!settings.appliesDenoise || settings.denoiseBackend != .coreImage)

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
            .disabled(!settings.appliesDenoise || settings.denoiseBackend != .coreImage)
        }
    }

    private var localAdjustmentsSection: some View {
        Section("Ajustes locais") {
            adjustmentSlider(
                title: "Gamma",
                value: Binding(
                    get: { Double(settings.gamma) },
                    set: { settings.gamma = Float($0) }
                ),
                range: 0.60...1.20,
                step: 0.01,
                format: "%.2f"
            )

            adjustmentSlider(
                title: "Contraste",
                value: Binding(
                    get: { Double(settings.contrast) },
                    set: { settings.contrast = Float($0) }
                ),
                range: 0.80...1.35,
                step: 0.01,
                format: "%.2f"
            )

            adjustmentSlider(
                title: "Saturacao",
                value: Binding(
                    get: { Double(settings.saturation) },
                    set: { settings.saturation = Float($0) }
                ),
                range: 0.70...1.60,
                step: 0.01,
                format: "%.2f"
            )

            adjustmentSlider(
                title: "Sombras",
                value: Binding(
                    get: { Double(settings.shadowAmount) },
                    set: { settings.shadowAmount = Float($0) }
                ),
                range: 0...0.80,
                step: 0.01,
                format: "%.2f"
            )

            adjustmentSlider(
                title: "Highlights",
                value: Binding(
                    get: { Double(settings.highlightAmount) },
                    set: { settings.highlightAmount = Float($0) }
                ),
                range: 0.60...1.00,
                step: 0.01,
                format: "%.2f"
            )

            adjustmentSlider(
                title: "Vibrance",
                value: Binding(
                    get: { Double(settings.vibrance) },
                    set: { settings.vibrance = Float($0) }
                ),
                range: 0...0.60,
                step: 0.01,
                format: "%.2f"
            )

            adjustmentSlider(
                title: "Unsharp",
                value: Binding(
                    get: { Double(settings.unsharpAmount) },
                    set: { settings.unsharpAmount = Float($0) }
                ),
                range: 0...1.20,
                step: 0.01,
                format: "%.2f"
            )
        }
    }

    private var actionsSection: some View {
        Section {
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

    private func adjustmentSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.system(.body, design: .monospaced, weight: .semibold))
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private var previewFrameCount: Int {
        processor.previewReferenceFrameCount(
            stackSize: Int(stackSize),
            stackingStartFrame: initialStackingStartFrame
        )
    }

    private var displayedPreviewURL: URL? {
        switch previewMode {
        case .processed:
            return previewURL
        case .reference:
            return referenceURL
        }
    }

    private func applyDefaultsForCurrentProfile() {
        let profile = settings.profile
        let stackingBackend = settings.stackingBackend
        settings = .defaults(for: profile)
        settings.stackingBackend = stackingBackend
        if stackingBackend == .coreImage {
            settings.alignsStars = false
        }
    }

    private func updateStackingBackend(_ backend: AstroStackingBackend) {
        settings.stackingBackend = backend
        switch backend {
        case .coreImage:
            settings.alignsStars = false
        case .openCV:
            settings.alignsStars = settings.profile.alignsStars
        }
    }

    private func renderPreview() async {
        guard !isRenderingPreview else { return }
        guard previewFrameCount > 0 else { return }

        isRenderingPreview = true

        do {
            referenceURL = try await processor.normalizedReferencePreviewFrameURL(
                stackingStartFrame: initialStackingStartFrame
            )
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

private struct AstroPreviewDetailView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZoomableImageView(image: image)
                .ignoresSafeArea(edges: .bottom)
                .background(.black)
                .navigationTitle("Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Label("Fechar", systemImage: "xmark")
                        }
                    }
                }
        }
    }
}

private struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .black
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 8
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

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
        context.coordinator.scrollView = scrollView

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
                let rect = CGRect(
                    x: point.x - width / 2,
                    y: point.y - height / 2,
                    width: width,
                    height: height
                )
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}

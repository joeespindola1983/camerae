import CameraeCore
import SwiftUI

struct CameraeNextCaptureConfiguration: Equatable, Sendable {
    var module: CameraModule
    var repeatableKind: RepeatableCaptureKind
    var durationMinutes: Int
    var videoDurationSeconds: Int
    var videoSettings: WorkflowVideoSettings
    var cameraLens: RepeatableCameraLens
    var sourceFormat: CaptureSourceFormat
    var exposureBias: Double
    var referenceOpacity: Double
    var intervalSeconds: Double
    var usesAutomaticAstroExposure: Bool
    var astroExposureSeconds: Double
    var astroCapturesPerFrame: Int

    static let repeatableDefault = Self(
        module: .repeatable,
        repeatableKind: .timelapse,
        durationMinutes: 30,
        videoDurationSeconds: 30,
        videoSettings: .repeatableDefault,
        cameraLens: .wide,
        sourceFormat: .heic,
        exposureBias: 0,
        referenceOpacity: 0.45,
        intervalSeconds: 5,
        usesAutomaticAstroExposure: false,
        astroExposureSeconds: 8,
        astroCapturesPerFrame: 3
    )

    static let astroDefault = Self(
        module: .astrophotography,
        repeatableKind: .timelapse,
        durationMinutes: 30,
        videoDurationSeconds: 30,
        videoSettings: .astroDefault,
        cameraLens: .wide,
        sourceFormat: .heic,
        exposureBias: 0,
        referenceOpacity: 0.45,
        intervalSeconds: 8,
        usesAutomaticAstroExposure: false,
        astroExposureSeconds: 8,
        astroCapturesPerFrame: 3
    )

    var estimatedFrameCount: Int {
        let seconds = repeatableKind == .video
            ? Double(videoDurationSeconds)
            : Double(durationMinutes * 60)
        switch module {
        case .repeatable:
            if repeatableKind == .video {
                return max(1, Int(seconds) * videoSettings.fps)
            }
            return max(1, Int((seconds / max(intervalSeconds, 0.1)).rounded(.down)))
        case .astrophotography:
            let frameDuration = max(astroExposureSeconds * Double(astroCapturesPerFrame), 0.1)
            return max(1, Int((seconds / frameDuration).rounded(.down)))
        case .edit:
            return 0
        }
    }

    var estimatedStorageDescription: String {
        if module == .repeatable, repeatableKind == .video {
            let baseMegabitsPerSecond: Double = switch videoSettings.resolution {
            case .preview: 15
            case .fourK: 60
            case .full: 90
            }
            let fpsFactor = Double(videoSettings.fps) / 30
            let bytes = baseMegabitsPerSecond * fpsFactor * videoSettings.quality.bitRateMultiplier
                * Double(videoDurationSeconds) * 1_000_000 / 8
            return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) + " estimado"
        }
        let bytesPerFrame = module == .astrophotography ? 18_000_000.0 : 4_000_000.0
        let gigabytes = Double(estimatedFrameCount) * bytesPerFrame / 1_000_000_000
        return gigabytes.formatted(.number.precision(.fractionLength(1))) + " GB estimado"
    }
}

enum CameraeNextCameraPresentation: Equatable, Sendable {
    case selector
    case lockedStatus(lens: String, zoom: String)
}

struct CameraeNextWorkflowConfigurationPresentation: Equatable, Sendable {
    let navigationTitle: String
    let primaryActionTitle: String
    let captureSectionTitle: String
    let adjustmentsSectionTitle: String
    let adjustmentTitles: [String]
    let durationLabels: [String]
    let cameraPresentation: CameraeNextCameraPresentation
    let showsVideoSettings: Bool
    let showsInterval: Bool

    init(configuration: CameraeNextCaptureConfiguration) {
        let isAstro = configuration.module == .astrophotography
        let isVideo = !isAstro && configuration.repeatableKind == .video
        navigationTitle = isAstro ? "Novo astro" : (isVideo ? "Novo vídeo" : "Novo timelapse")
        primaryActionTitle = isAstro ? "Abrir câmera" : "Abrir alinhamento"
        captureSectionTitle = isAstro ? "SESSÃO" : "CAPTURA"
        adjustmentsSectionTitle = isAstro ? "CAPTURA ASTRO" : "AJUSTES"
        adjustmentTitles = isAstro
            ? ["Exposição", "Intervalo", "Capturas/frame"]
            : (isVideo ? ["EV", "Opacidade"] : ["EV", "Opacidade", "Intervalo"])
        durationLabels = isAstro
            ? ["15 min", "30 min", "1 h", "Personal."]
            : (isVideo ? ["30 s", "1 min", "2 min"] : ["15 min", "30 min", "1 h", "Custom"])
        cameraPresentation = isAstro
            ? .lockedStatus(lens: "Wide", zoom: "1×")
            : .selector
        showsVideoSettings = isVideo
        showsInterval = isAstro || !isVideo
    }
}

struct CameraeNextWorkflowConfigurationView: View {
    let project: CameraProject
    let onStart: (CameraeNextCaptureConfiguration) -> Void
    let onShowSessions: () -> Void

    @State private var configuration: CameraeNextCaptureConfiguration

    init(
        project: CameraProject,
        onStart: @escaping (CameraeNextCaptureConfiguration) -> Void,
        onShowSessions: @escaping () -> Void
    ) {
        self.project = project
        self.onStart = onStart
        self.onShowSessions = onShowSessions
        _configuration = State(initialValue: project.module == .astrophotography ? .astroDefault : .repeatableDefault)
    }

    private var theme: CameraeNextTheme { .init(workflow: project.module.designTheme) }
    private var isAstro: Bool { project.module == .astrophotography }
    private var presentation: CameraeNextWorkflowConfigurationPresentation {
        .init(configuration: configuration)
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 8) {
                    modePicker
                    captureCard
                    cameraCard
                    adjustmentsCard
                    if presentation.showsVideoSettings { videoSettingsCard }
                    planningCard
                    referenceCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                CameraeNextActionButton(
                    title: presentation.primaryActionTitle,
                    systemImage: nil,
                    theme: theme
                ) {
                    onStart(configuration)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(theme.background.opacity(0.96))
            }
        }
        .navigationTitle(presentation.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.background.opacity(0.96), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onShowSessions) {
                    Image(systemName: "rectangle.stack")
                }
                .accessibilityLabel("Abrir sessões existentes")
            }
        }
        .tint(theme.accent)
        .preferredColorScheme(theme.colorScheme)
        .onAppear { AppOrientationLock.shared.restorePortrait() }
    }

    private var modePicker: some View {
        CameraeNextSegmentedControl(
            items: isAstro ? CameraeNextCaptureModeOption.astroItems : CameraeNextCaptureModeOption.repeatableItems,
            selection: modeBinding,
            theme: theme
        )
    }

    private var modeBinding: Binding<CameraeNextCaptureModeOption> {
        Binding(
            get: {
                isAstro
                    ? (configuration.usesAutomaticAstroExposure ? .automatic : .manual)
                    : (configuration.repeatableKind == .video ? .video : .timelapse)
            },
            set: { value in
                if isAstro {
                    configuration.usesAutomaticAstroExposure = value == .automatic
                } else {
                    configuration.repeatableKind = value == .video ? .video : .timelapse
                }
            }
        )
    }

    private var captureCard: some View {
        CameraeNextCard(theme: theme) {
            VStack(spacing: 12) {
                CameraeNextSectionLabel(title: presentation.captureSectionTitle, theme: theme)

                CameraeNextSegmentedControl(
                    items: Array(zip(durationValues, presentation.durationLabels)).map {
                        CameraeNextSegmentItem(value: $0.0, label: $0.1)
                    },
                    selection: durationBinding,
                    theme: theme,
                    height: 34
                )

                HStack {
                    summary(title: "FORMATO", value: configuration.repeatableKind == .video ? "MP4" : (configuration.sourceFormat == .heic ? "HEIC" : "JPEG"))
                    Spacer()
                    summary(title: "ESTIMATIVA", value: "\(configuration.estimatedFrameCount) frames", accent: true)
                }
            }
        }
    }

    private var durationValues: [Int] {
        presentation.showsVideoSettings ? [30, 60, 120] : [15, 30, 60, 180]
    }

    private var durationBinding: Binding<Int> {
        presentation.showsVideoSettings ? $configuration.videoDurationSeconds : $configuration.durationMinutes
    }

    @ViewBuilder
    private var cameraCard: some View {
        switch presentation.cameraPresentation {
        case .selector:
            CameraeNextCameraSelector(selection: $configuration.cameraLens, theme: theme)
        case let .lockedStatus(lens, zoom):
            CameraeNextCameraStatus(lens: lens, zoom: zoom, theme: theme)
        }
    }

    private var adjustmentsCard: some View {
        CameraeNextCard(theme: theme) {
            VStack(spacing: 10) {
                CameraeNextSectionLabel(title: presentation.adjustmentsSectionTitle, theme: theme)

                if isAstro {
                    CameraeNextSliderRow(
                        title: "Exposição",
                        value: configuration.usesAutomaticAstroExposure
                            ? "Automática"
                            : "\(Int(configuration.astroExposureSeconds))s",
                        theme: theme
                    ) {
                        Slider(value: $configuration.astroExposureSeconds, in: 1...30, step: 1)
                    }
                    CameraeNextSliderRow(
                        title: "Intervalo",
                        value: "\(Int(configuration.intervalSeconds))s",
                        theme: theme
                    ) {
                        Slider(value: $configuration.intervalSeconds, in: 1...120, step: 1)
                    }
                    CameraeNextSliderRow(
                        title: "Capturas/frame",
                        value: "\(configuration.astroCapturesPerFrame)",
                        theme: theme
                    ) {
                        Slider(value: astroCapturesBinding, in: 1...12, step: 1)
                    }
                } else {
                    CameraeNextSliderRow(title: "EV", value: configuration.exposureBias.formatted(.number.precision(.fractionLength(1))), theme: theme) {
                        Slider(value: $configuration.exposureBias, in: -2...2, step: 0.1)
                    }
                    CameraeNextSliderRow(title: "Opacidade", value: configuration.referenceOpacity.formatted(.percent.precision(.fractionLength(0))), theme: theme) {
                        Slider(value: $configuration.referenceOpacity, in: 0...1, step: 0.05)
                    }
                    if presentation.showsInterval {
                        CameraeNextSliderRow(title: "Intervalo", value: "\(Int(configuration.intervalSeconds))s", theme: theme) {
                            Slider(value: $configuration.intervalSeconds, in: 1...120, step: 1)
                        }
                    }
                }
            }
        }
    }

    private var videoSettingsCard: some View {
        CameraeNextCard(theme: theme) {
            VStack(spacing: 10) {
                CameraeNextSectionLabel(title: "VÍDEO", theme: theme)

                CameraeNextSettingRow(title: "Resolução", helper: "Tamanho do arquivo final", theme: theme) {
                    Picker("Resolução", selection: $configuration.videoSettings.resolution) {
                        ForEach(WorkflowVideoResolution.allCases) { resolution in
                            Text(resolution.label).tag(resolution)
                        }
                    }
                    .pickerStyle(.menu)
                }

                CameraeNextSegmentedControl(
                    items: [24, 30, 60].map { CameraeNextSegmentItem(value: $0, label: "\($0) fps") },
                    selection: $configuration.videoSettings.fps,
                    theme: theme,
                    height: 34
                )

                CameraeNextSettingRow(title: "Qualidade", helper: "Compressão do MP4", theme: theme) {
                    Picker("Qualidade", selection: $configuration.videoSettings.quality) {
                        ForEach(WorkflowVideoQuality.allCases) { quality in
                            Text(quality.label).tag(quality)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private var astroCapturesBinding: Binding<Double> {
        Binding(
            get: { Double(configuration.astroCapturesPerFrame) },
            set: { configuration.astroCapturesPerFrame = Int($0.rounded()) }
        )
    }

    private var planningCard: some View {
        CameraeNextCard(theme: theme) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    CameraeNextSectionLabel(title: "Planejamento", theme: theme)
                    Text("PRONTO")
                        .font(.custom("DMMono-Regular", size: 10, relativeTo: .caption2))
                        .foregroundStyle(theme.accent)
                }
                Text("\(configuration.estimatedFrameCount) frames  ·  \(configuration.estimatedStorageDescription)  ·  82% livre")
                    .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                    .foregroundStyle(theme.text)
                ProgressView(value: min(Double(configuration.estimatedFrameCount) / 1_800, 1))
                    .tint(theme.accent)
            }
        }
    }

    private var referenceCard: some View {
        CameraeNextCard(theme: theme) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.surface)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Text(isAstro ? "AST" : "REF")
                            .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
                            .tracking(1.4)
                            .foregroundStyle(theme.accent)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    CameraeNextSectionLabel(title: isAstro ? "Guia noturno" : "Referência", theme: theme)
                    Text(isAstro ? "Céu e horizonte" : "Primeiro enquadramento")
                        .font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
                        .foregroundStyle(theme.text)
                    Text(isAstro ? "Nível e orientação salvos" : "Rotação e GPS salvos")
                        .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                        .foregroundStyle(theme.muted)
                }
                Spacer()
                Text("ATIVA")
                    .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
                    .tracking(1.2)
                    .foregroundStyle(theme.accent)
            }
        }
    }

    private func summary(title: String, value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.custom("DMMono-Regular", size: 9, relativeTo: .caption2))
                .tracking(1.3)
                .foregroundStyle(theme.muted)
            Text(value)
                .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                .foregroundStyle(accent ? theme.accent : theme.text)
        }
    }
}

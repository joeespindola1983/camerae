import CameraeCore
import Foundation
import SwiftUI

struct CameraeNextCaptureConfiguration: Equatable, Hashable, Sendable {
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
    let isAstroExposureControlEnabled: Bool

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
        isAstroExposureControlEnabled = isAstro && !configuration.usesAutomaticAstroExposure
    }
}

struct CameraeNextWorkflowConfigurationView: View {
    let project: CameraProject
    let onStart: (CameraeNextCaptureConfiguration) -> Void
    let onShowSessions: () -> Void

    @State private var configuration: CameraeNextCaptureConfiguration
    @StateObject private var planning: CapturePlanningViewModel
    @State private var usesCustomDuration = false
    @State private var isShowingCustomDuration = false

    private let availableLenses: [RepeatableCameraLens]
    private let preferredLens: RepeatableCameraLens

    init(
        project: CameraProject,
        onStart: @escaping (CameraeNextCaptureConfiguration) -> Void,
        onShowSessions: @escaping () -> Void
    ) {
        self.project = project
        self.onStart = onStart
        self.onShowSessions = onShowSessions
        let preferredLens = RepeatableCameraLens.wide
        let availableLenses = RepeatableCameraLens.availableBackLenses()
        var initialConfiguration = project.module == .astrophotography
            ? CameraeNextCaptureConfiguration.astroDefault
            : CameraeNextCaptureConfiguration.repeatableDefault
        if !availableLenses.contains(preferredLens), let fallback = availableLenses.first {
            initialConfiguration.cameraLens = fallback
        }
        self.availableLenses = availableLenses
        self.preferredLens = preferredLens
        _configuration = State(initialValue: initialConfiguration)
        _planning = StateObject(wrappedValue: CapturePlanningViewModel(
            projectDirectoryURL: project.directoryURL
        ))
    }

    private var theme: CameraeNextTheme { .init(workflow: project.module.designTheme) }
    private var isAstro: Bool { project.module == .astrophotography }
    private var presentation: CameraeNextWorkflowConfigurationPresentation {
        .init(configuration: configuration)
    }
    private var cameraSetupPresentation: CameraeNextCameraSetupPresentation {
        .init(
            module: project.module,
            availableLenses: availableLenses,
            selectedLens: configuration.cameraLens,
            preferredLens: preferredLens
        )
    }
    private var planningPresentation: CameraeNextCapturePlanningPresentation {
        if planning.isLoading { return .evaluating }
        if let result = planning.result { return .init(result: result) }
        if planning.errorMessage != nil { return .error(planning.errorMessage) }
        return .evaluating
    }
    private var referencePresentation: CameraeNextReferencePresentation {
        .init(module: project.module, state: referenceState)
    }
    private var referenceState: CameraeNextReferenceState {
        guard let url = project.referenceFrameURL else { return .missing }
        return FileManager.default.fileExists(atPath: url.path) ? .active : .unavailable
    }
    private var canStart: Bool {
        planningPresentation.canStart && cameraSetupPresentation.canStart
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
                    title: primaryActionTitle,
                    systemImage: nil,
                    theme: theme,
                    isBusy: planning.isLoading,
                    isDisabled: !canStart
                ) {
                    var resolved = configuration
                    if let format = planning.result?.resolvedPlan.sourceFormat {
                        resolved.sourceFormat = format
                    }
                    onStart(resolved)
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
        .task(id: configuration) {
            await refreshPreflight()
        }
        .sheet(isPresented: $isShowingCustomDuration) {
            CameraeNextCustomDurationSheet(
                minutes: $configuration.durationMinutes,
                module: project.module,
                theme: theme,
                onApply: { usesCustomDuration = true }
            )
        }
    }

    private var primaryActionTitle: String {
        if cameraSetupPresentation.state == .unavailable {
            return "Câmera indisponível"
        }
        switch planningPresentation.state {
        case .blocked: return "Libere espaço para continuar"
        case .error: return "Planejamento indisponível"
        default: return presentation.primaryActionTitle
        }
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
                    if configuration.repeatableKind == .video {
                        usesCustomDuration = false
                    }
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
        presentation.showsVideoSettings ? [30, 60, 120] : [15, 30, 60, 0]
    }

    private var durationBinding: Binding<Int> {
        if presentation.showsVideoSettings {
            return $configuration.videoDurationSeconds
        }
        return Binding(
            get: { usesCustomDuration ? 0 : configuration.durationMinutes },
            set: { value in
                if value == 0 {
                    isShowingCustomDuration = true
                } else {
                    usesCustomDuration = false
                    configuration.durationMinutes = value
                }
            }
        )
    }

    @ViewBuilder
    private var cameraCard: some View {
        if !isAstro, cameraSetupPresentation.state == .available {
            CameraeNextCameraSelector(
                selection: $configuration.cameraLens,
                theme: theme,
                availableLenses: availableLenses
            )
        } else {
            CameraeNextCameraSetupStateCard(
                presentation: cameraSetupPresentation,
                theme: theme
            )
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
                            .disabled(!presentation.isAstroExposureControlEnabled)
                    }
                    .opacity(presentation.isAstroExposureControlEnabled ? 1 : 0.58)
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
        CameraeNextCapturePlanningCard(presentation: planningPresentation, theme: theme)
    }

    private var referenceCard: some View {
        CameraeNextReferenceStateCard(presentation: referencePresentation, theme: theme)
    }

    private func refreshPreflight() async {
        do {
            let plan = try capturePlan
            await planning.evaluate(
                plan: plan,
                sizeProfile: sizeProfile,
                capabilityProfile: .init(
                    supportedSourceFormats: [.heic, .jpeg],
                    supportedAstroPipelines: isAstro ? [astroPipeline] : []
                ),
                observedDrainPerHour: configuration.repeatableKind == .video ? 0.12 : (isAstro ? 0.20 : 0.10)
            )
        } catch {
            // Transient invalid input keeps the primary action blocked.
        }
    }

    private var capturePlan: CapturePlan {
        get throws {
            let workflow: CaptureWorkflow = isAstro
                ? .astro
                : (configuration.repeatableKind == .video ? .repeatableVideo : .repeatableTimelapse)
            return try CapturePlan(
                workflow: workflow,
                plannedDuration: configuration.repeatableKind == .video
                    ? TimeInterval(configuration.videoDurationSeconds)
                    : TimeInterval(configuration.durationMinutes * 60),
                captureInterval: workflow == .repeatableVideo
                    ? nil
                    : (isAstro
                        ? max(configuration.astroExposureSeconds * Double(configuration.astroCapturesPerFrame), 0.1)
                        : configuration.intervalSeconds),
                sourceFormat: configuration.sourceFormat,
                captureFPS: workflow == .repeatableVideo ? configuration.videoSettings.fps : nil,
                renderFPS: workflow == .repeatableVideo ? nil : configuration.videoSettings.fps,
                resolution: captureResolution,
                astroPipeline: isAstro ? astroPipeline : nil
            )
        }
    }

    private var sizeProfile: CaptureSizeProfile {
        if configuration.repeatableKind == .video, !isAstro {
            return .init(
                videoBitsPerSecondUpperBound: videoBitsPerSecondUpperBound,
                publicationOverheadFraction: 0.10
            )
        }
        return .init(
            bytesPerFrameUpperBound: configuration.sourceFormat == .heic ? 4_000_000 : 8_000_000,
            processingOverheadFraction: isAstro ? 0.50 : 0.10,
            publicationOverheadFraction: isAstro ? 0.25 : 0.20
        )
    }

    private var captureResolution: CaptureResolution {
        guard configuration.repeatableKind == .video, !isAstro else { return .fullSensor }
        switch configuration.videoSettings.resolution {
        case .preview: return .fullHD
        case .fourK: return .ultraHD
        case .full: return .fullSensor
        }
    }

    private var videoBitsPerSecondUpperBound: UInt64 {
        let base: Double = switch configuration.videoSettings.resolution {
        case .preview: 16_000_000
        case .fourK: 60_000_000
        case .full: 90_000_000
        }
        return UInt64(base * (Double(configuration.videoSettings.fps) / 30) * configuration.videoSettings.quality.bitRateMultiplier)
    }

    private var astroPipeline: AstroPipelineProfile {
        let thermal: CaptureThermalState = switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .unknown
        }
        return AstroPipelineResolver().resolve(.init(
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            thermalState: thermal,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        ))
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

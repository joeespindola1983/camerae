import CameraeCore
import Foundation
import ImageIO
import PhotosUI
import SwiftUI
import UIKit

struct CameraeNextCaptureConfiguration: Equatable, Hashable, Sendable {
    var module: CameraModule
    var repeatableKind: RepeatableCaptureKind
    var durationMinutes: Int
    var videoDurationSeconds: Int
    var videoSettings: WorkflowVideoSettings
    var cameraLens: RepeatableCameraLens
    var cameraZoomFactor: Double
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
        cameraZoomFactor: 1,
        sourceFormat: .heic,
        exposureBias: 0,
        referenceOpacity: 0.5,
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
        cameraZoomFactor: 1,
        sourceFormat: .heic,
        exposureBias: 0,
        referenceOpacity: 0.5,
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
        navigationTitle = isAstro ? CameraeL10n.newAstro : (isVideo ? CameraeL10n.newVideo : CameraeL10n.newTimelapse)
        primaryActionTitle = CameraeL10n.openCamera
        captureSectionTitle = isAstro ? CameraeL10n.sessionSection : CameraeL10n.captureSection
        adjustmentsSectionTitle = isAstro ? CameraeL10n.astroCaptureSection : CameraeL10n.adjustmentsSection
        adjustmentTitles = isAstro
            ? [CameraeL10n.exposure, CameraeL10n.interval, CameraeL10n.capturesPerFrame]
            : (isVideo ? ["EV"] : ["EV", CameraeL10n.interval])
        durationLabels = isAstro
            ? ["15 min", "30 min", "1 h", CameraeL10n.customDurationShort]
            : (isVideo ? ["30 s", "1 min", "2 min"] : ["15 min", "30 min", "1 h", CameraeL10n.customDurationShort])
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
    let isEmbeddedInProjectWorkspace: Bool
    let referenceRefreshID: Int

    @State private var configuration: CameraeNextCaptureConfiguration
    @StateObject private var planning: CapturePlanningViewModel
    @State private var usesCustomDuration = false
    @State private var isShowingCustomDuration = false
    @State private var referenceURL: URL?
    @State private var importedReferenceItem: PhotosPickerItem?
    @State private var isShowingReferenceImporter = false
    @State private var isShowingReferenceCamera = false
    @State private var isReferenceLoading = false
    @State private var referenceErrorMessage: String?

    private let availableLenses: [RepeatableCameraLens]
    private let preferredLens: RepeatableCameraLens
    private let referenceStore: TimelapseSessionStore

    init(
        project: CameraProject,
        onStart: @escaping (CameraeNextCaptureConfiguration) -> Void,
        onShowSessions: @escaping () -> Void,
        isEmbeddedInProjectWorkspace: Bool = false,
        referenceRefreshID: Int = 0
    ) {
        self.project = project
        self.onStart = onStart
        self.onShowSessions = onShowSessions
        self.isEmbeddedInProjectWorkspace = isEmbeddedInProjectWorkspace
        self.referenceRefreshID = referenceRefreshID
        let referenceStore = TimelapseSessionStore(project: project)
        let cameraPolicy = CameraeNextProjectCameraPolicy(
            summaries: referenceStore.sessionSummaries()
        )
        let preferredLens = cameraPolicy.lockedLens ?? RepeatableCameraLens.wide
        let availableLenses = RepeatableCameraLens.availableBackLenses()
        var initialConfiguration = project.module == .astrophotography
            ? CameraeNextCaptureConfiguration.astroDefault
            : CameraeNextCaptureConfiguration.repeatableDefault
        if let lockedLens = cameraPolicy.lockedLens {
            initialConfiguration.cameraLens = lockedLens
            initialConfiguration.cameraZoomFactor = cameraPolicy.lockedZoomFactor
        } else if !availableLenses.contains(preferredLens), let fallback = availableLenses.first {
            initialConfiguration.cameraLens = fallback
        }
        self.availableLenses = availableLenses
        self.preferredLens = preferredLens
        self.referenceStore = referenceStore
        _configuration = State(initialValue: initialConfiguration)
        _referenceURL = State(initialValue: project.referenceFrameURL)
        _planning = StateObject(wrappedValue: CapturePlanningViewModel(
            projectDirectoryURL: project.directoryURL
        ))
    }

    private var theme: CameraeNextTheme { .init(workflow: project.module.designTheme) }
    private var isAstro: Bool { project.module == .astrophotography }
    private var cameraPolicy: CameraeNextProjectCameraPolicy {
        .init(summaries: referenceStore.sessionSummaries())
    }
    private var presentation: CameraeNextWorkflowConfigurationPresentation {
        .init(configuration: configuration)
    }
    private var cameraSetupPresentation: CameraeNextCameraSetupPresentation {
        .init(
            module: project.module,
            availableLenses: availableLenses,
            selectedLens: configuration.cameraLens,
            preferredLens: preferredLens,
            lockedLens: cameraPolicy.lockedLens,
            lockedZoomFactor: cameraPolicy.lockedZoomFactor
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
        if isReferenceLoading { return .loading }
        guard let url = referenceURL else { return .missing }
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
                    referenceCard
                    modePicker
                    captureCard
                    cameraCard
                    adjustmentsCard
                    if presentation.showsVideoSettings { videoSettingsCard }
                    planningCard
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
                    openCamera()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(theme.background.opacity(0.96))
            }
        }
        .navigationTitle(isEmbeddedInProjectWorkspace ? project.name : presentation.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.background.opacity(0.96), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            if !isEmbeddedInProjectWorkspace {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onShowSessions) {
                        Image(systemName: "rectangle.stack")
                    }
                    .accessibilityLabel(CameraeL10n.openExistingSessions)
                }
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
        .photosPicker(
            isPresented: $isShowingReferenceImporter,
            selection: $importedReferenceItem,
            matching: .images
        )
        .onChange(of: importedReferenceItem) { _, item in
            guard let item else { return }
            Task { await importReference(from: item) }
        }
        .fullScreenCover(isPresented: $isShowingReferenceCamera) {
            CameraeNextReferenceCameraPicker(fallbackLens: configuration.cameraLens) { capture in
                isShowingReferenceCamera = false
                guard let capture else { return }
                Task {
                    do {
                        let policy = cameraPolicy
                        guard policy.accepts(
                            lens: capture.selection.lens,
                            zoomFactor: capture.selection.zoomFactor
                        ) else {
                            throw CameraeNextReferenceError.cameraMismatch(
                                expectedLens: policy.lockedLens ?? configuration.cameraLens,
                                expectedZoom: policy.lockedZoomFactor
                            )
                        }
                        try await saveReference(
                            capture.image,
                            cameraLens: capture.selection.lens,
                            cameraZoomFactor: capture.selection.zoomFactor
                        )
                        configuration.cameraLens = capture.selection.lens
                        configuration.cameraZoomFactor = capture.selection.zoomFactor
                    } catch {
                        referenceErrorMessage = error.localizedDescription
                    }
                }
            }
            .ignoresSafeArea()
        }
        .alert(
            CameraeL10n.referenceImage,
            isPresented: Binding(
                get: { referenceErrorMessage != nil },
                set: { if !$0 { referenceErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(referenceErrorMessage ?? "")
        }
        .onAppear(perform: synchronizeReference)
        .onChange(of: referenceRefreshID) { _, _ in synchronizeReference() }
    }

    private var primaryActionTitle: String {
        if cameraSetupPresentation.state == .unavailable {
            return CameraeL10n.cameraUnavailable
        }
        switch planningPresentation.state {
        case .blocked: return CameraeL10n.freeSpaceToContinue
        case .error: return CameraeL10n.planningUnavailable
        default: return presentation.primaryActionTitle
        }
    }

    private func openCamera() {
        var resolved = configuration
        if let format = planning.result?.resolvedPlan.sourceFormat {
            resolved.sourceFormat = format
        }
        onStart(resolved)
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
                    summary(title: CameraeL10n.format, value: configuration.repeatableKind == .video ? "MP4" : (configuration.sourceFormat == .heic ? "HEIC" : "JPEG"))
                    Spacer()
                    summary(title: CameraeL10n.estimate, value: "\(configuration.estimatedFrameCount) frames", accent: true)
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
                selection: Binding(
                    get: { configuration.cameraLens },
                    set: {
                        configuration.cameraLens = $0
                        configuration.cameraZoomFactor = 1
                    }
                ),
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
                        title: CameraeL10n.exposure,
                        value: configuration.usesAutomaticAstroExposure
                            ? CameraeL10n.automatic
                            : "\(Int(configuration.astroExposureSeconds))s",
                        theme: theme
                    ) {
                        Slider(value: $configuration.astroExposureSeconds, in: 1...30, step: 1)
                            .disabled(!presentation.isAstroExposureControlEnabled)
                    }
                    .opacity(presentation.isAstroExposureControlEnabled ? 1 : 0.58)
                    CameraeNextSliderRow(
                        title: CameraeL10n.interval,
                        value: "\(Int(configuration.intervalSeconds))s",
                        theme: theme
                    ) {
                        Slider(value: $configuration.intervalSeconds, in: 1...120, step: 1)
                    }
                    CameraeNextSliderRow(
                        title: CameraeL10n.capturesPerFrame,
                        value: "\(configuration.astroCapturesPerFrame)",
                        theme: theme
                    ) {
                        Slider(value: astroCapturesBinding, in: 1...12, step: 1)
                    }
                } else {
                    CameraeNextSliderRow(title: "EV", value: configuration.exposureBias.formatted(.number.precision(.fractionLength(1))), theme: theme) {
                        Slider(value: $configuration.exposureBias, in: -2...2, step: 0.1)
                    }
                    if presentation.showsInterval {
                        CameraeNextSliderRow(title: CameraeL10n.interval, value: "\(Int(configuration.intervalSeconds))s", theme: theme) {
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
                CameraeNextSectionLabel(title: CameraeL10n.videoSection, theme: theme)

                CameraeNextSettingRow(title: CameraeL10n.resolution, helper: CameraeL10n.resolutionHelper, theme: theme) {
                    Picker(CameraeL10n.resolution, selection: $configuration.videoSettings.resolution) {
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

                CameraeNextSettingRow(title: CameraeL10n.quality, helper: CameraeL10n.qualityHelper, theme: theme) {
                    Picker(CameraeL10n.quality, selection: $configuration.videoSettings.quality) {
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
        CameraeNextReferenceStateCard(
            presentation: referencePresentation,
            imageURL: referenceURL,
            theme: theme,
            primaryAction: {
                isShowingReferenceCamera = UIImagePickerController.isSourceTypeAvailable(.camera)
                if !isShowingReferenceCamera {
                    isShowingReferenceImporter = true
                }
            },
            secondaryAction: {
                if referenceURL == nil {
                    isShowingReferenceImporter = true
                } else {
                    removeReference()
                }
            }
        )
    }

    @MainActor
    private func importReference(from item: PhotosPickerItem) async {
        isReferenceLoading = true
        defer {
            isReferenceLoading = false
            importedReferenceItem = nil
        }
        do {
            guard
                let data = try await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                throw CameraeNextReferenceError.unreadableImage
            }
            try await saveReference(image, cameraLens: nil, cameraZoomFactor: nil)
        } catch {
            referenceErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func saveReference(
        _ image: UIImage,
        cameraLens: RepeatableCameraLens?,
        cameraZoomFactor: Double?
    ) async throws {
        isReferenceLoading = true
        defer { isReferenceLoading = false }
        let session = try referenceStore.importReferenceImage(
            image,
            cameraLens: cameraLens,
            cameraZoomFactor: cameraZoomFactor
        )
        referenceURL = referenceStore.firstFrameURL(in: session)
    }

    private func removeReference() {
        guard let referenceURL else { return }
        guard let summary = referenceStore.sessionSummaries().first(where: {
            $0.referenceFrameURL?.standardizedFileURL == referenceURL.standardizedFileURL
        }) else {
            self.referenceURL = nil
            return
        }
        guard summary.captureKind == .photo else {
            referenceErrorMessage = "O primeiro frame pertence a uma captura e não será apagado. Importe ou fotografe outra referência para substituí-lo."
            return
        }
        do {
            try referenceStore.deleteSession(summary.session)
            self.referenceURL = referenceStore.firstReferenceFrameURL()
        } catch {
            referenceErrorMessage = error.localizedDescription
        }
    }

    private func synchronizeReference() {
        referenceURL = referenceStore.firstReferenceFrameURL()
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

private enum CameraeNextReferenceError: LocalizedError {
    case unreadableImage
    case cameraMismatch(expectedLens: RepeatableCameraLens, expectedZoom: Double)

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            "Não foi possível ler a imagem selecionada."
        case let .cameraMismatch(expectedLens, expectedZoom):
            "Esta referência usa outra câmera. Tire a foto com \(expectedLens.title), zoom \(Self.zoomLabel(expectedZoom)), para manter o projeto alinhado."
        }
    }

    private static func zoomLabel(_ value: Double) -> String {
        value.formatted(
            .number.locale(.current).precision(.fractionLength(0...1))
        ) + "×"
    }
}

struct CameraeNextReferenceCameraSelection: Equatable, Sendable {
    let lens: RepeatableCameraLens
    let zoomFactor: Double
}

enum CameraeNextReferenceCameraMetadataResolver {
    static func resolve(
        metadata: [String: Any],
        fallbackLens: RepeatableCameraLens
    ) -> CameraeNextReferenceCameraSelection {
        let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? metadata
        let lensModel = (exif[kCGImagePropertyExifLensModel as String] as? String ?? "").lowercased()
        let digitalZoom = max(number(exif[kCGImagePropertyExifDigitalZoomRatio as String]) ?? 1, 1)
        let equivalentFocalLength = number(exif[kCGImagePropertyExifFocalLenIn35mmFilm as String])
        let baseEquivalentFocalLength = equivalentFocalLength.map { $0 / digitalZoom }

        let lens: RepeatableCameraLens
        if lensModel.contains("ultra wide") || lensModel.contains("ultrawide") {
            lens = .ultraWide
        } else if lensModel.contains("telephoto") || lensModel.contains(" tele ") {
            lens = .telephoto
        } else if let focalLength = baseEquivalentFocalLength {
            if focalLength <= 18 {
                lens = .ultraWide
            } else if focalLength >= 45 {
                lens = .telephoto
            } else {
                lens = .wide
            }
        } else if lensModel.contains("wide") {
            lens = .wide
        } else {
            lens = fallbackLens
        }

        return .init(lens: lens, zoomFactor: digitalZoom)
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}

private struct CameraeNextCapturedReference {
    let image: UIImage
    let selection: CameraeNextReferenceCameraSelection
}

private struct CameraeNextReferenceCameraPicker: UIViewControllerRepresentable {
    let fallbackLens: RepeatableCameraLens
    let completion: (CameraeNextCapturedReference?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(fallbackLens: fallbackLens, completion: completion)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.cameraDevice = .rear
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let fallbackLens: RepeatableCameraLens
        let completion: (CameraeNextCapturedReference?) -> Void

        init(
            fallbackLens: RepeatableCameraLens,
            completion: @escaping (CameraeNextCapturedReference?) -> Void
        ) {
            self.fallbackLens = fallbackLens
            self.completion = completion
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                completion(nil)
                return
            }
            let metadata = info[.mediaMetadata] as? [String: Any] ?? [:]
            completion(.init(
                image: image,
                selection: CameraeNextReferenceCameraMetadataResolver.resolve(
                    metadata: metadata,
                    fallbackLens: fallbackLens
                )
            ))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            completion(nil)
        }
    }
}

import CameraeCore
import SwiftUI
import UIKit

struct CameraView: View {
    @StateObject private var camera: CameraController
    @StateObject private var planning: CapturePlanningViewModel
    private let project: CameraProject
    private let onDeleteProject: () throws -> Void
    private let onClose: (() -> Void)?
    private let onCompletedSession: ((TimelapseSession) -> Void)?
    private let usesNextInterface: Bool

    @State private var timelapseIntervalSeconds = 5.0
    @State private var astroIntervalSeconds = 1.0
    @State private var astroBatchSize = 30.0
    @State private var usesAutomaticAstroExposure = true
    @State private var isControlsVisible = true
    @State private var isShowingExportedArchives = false
    @State private var isExportingOriginalFrames = false
    @State private var exportedArchiveURLs: [URL] = []
    @State private var exportTask: Task<Void, Never>?
    @State private var processingSession: TimelapseSession?
    @State private var durationOption = AstroDurationOption.thirtyMinutes
    @State private var customDurationMinutes = 60
    @State private var sourceFormat = CaptureSourceFormat.heic
    @State private var capturePhase = AstroCapturePhase.setup
    @State private var isGridVisible = true
    @State private var selectedGridStyle = CameraeNextGridStyle.default
    @State private var isShowingGridPicker = false

    init(
        project: CameraProject,
        nextConfiguration: CameraeNextCaptureConfiguration? = nil,
        onDeleteProject: @escaping () throws -> Void = {},
        onClose: (() -> Void)? = nil,
        onCompletedSession: ((TimelapseSession) -> Void)? = nil
    ) {
        CameraeCaptureDiagnostics.event(
            "R01.7 astro.init",
            "hasNextConfiguration=\(nextConfiguration != nil)"
        )
        self.project = project
        self.onDeleteProject = onDeleteProject
        self.onClose = onClose
        self.onCompletedSession = onCompletedSession
        self.usesNextInterface = nextConfiguration != nil
        _camera = StateObject(wrappedValue: CameraController(project: project))
        _planning = StateObject(wrappedValue: CapturePlanningViewModel(
            projectDirectoryURL: project.directoryURL
        ))
        if let nextConfiguration {
            _astroIntervalSeconds = State(initialValue: nextConfiguration.astroExposureSeconds)
            _astroBatchSize = State(initialValue: Double(nextConfiguration.astroCapturesPerFrame))
            _usesAutomaticAstroExposure = State(initialValue: nextConfiguration.usesAutomaticAstroExposure)
            _durationOption = State(initialValue: .custom)
            _customDurationMinutes = State(initialValue: max(1, nextConfiguration.durationMinutes))
            _sourceFormat = State(initialValue: nextConfiguration.sourceFormat)
            _capturePhase = State(initialValue: .capture)
        }
    }

    var body: some View {
        Group {
            switch capturePhase {
            case .setup:
                setupView
            case .capture:
                captureView
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if capturePhase == .setup, let onClose {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) {
                        Label("Timelapses", systemImage: "chevron.left")
                    }
                    .accessibilityLabel("Voltar para timelapses")
                }
            }
        }
        .toolbar(capturePhase == .capture ? .hidden : .visible, for: .navigationBar)
        .onAppear {
            AppOrientationLock.shared.restorePortrait()
        }
        .onDisappear {
            camera.stop()
            AppOrientationLock.shared.restorePortrait()
        }
        .task {
            await camera.start()
        }
        .task(id: planningInput) {
            await refreshPreflight()
        }
        .sheet(isPresented: $isShowingExportedArchives) {
            if !exportedArchiveURLs.isEmpty {
                ExportedArchivesView(urls: exportedArchiveURLs)
            }
        }
        .fullScreenCover(isPresented: $isShowingGridPicker, onDismiss: restartCameraIfNeeded) {
            CameraeNextGridPickerView(
                selection: $selectedGridStyle,
                isVisible: $isGridVisible,
                theme: .astro
            )
        }
        .navigationDestination(item: $processingSession) { session in
            AstroProcessingView(session: session) {
                processingSession = nil
            } onDeleteProject: {
                try onDeleteProject()
            }
        }
        .onChange(of: camera.completedSession) { _, session in
            guard let session else { return }
            if let onCompletedSession {
                onCompletedSession(session)
            } else {
                processingSession = session
            }
        }
    }

    private func restartCameraIfNeeded() {
        guard camera.lifecycleState != .running else { return }
        Task { await camera.start() }
    }

    private var setupView: some View {
        List {
            Section("Captura") {
                Picker("Duração", selection: $durationOption) {
                    ForEach(AstroDurationOption.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                if durationOption == .custom {
                    Stepper(
                        "Duração: \(customDurationMinutes) min",
                        value: $customDurationMinutes,
                        in: 5...720,
                        step: 5
                    )
                }

                Picker("Formato", selection: $sourceFormat) {
                    Text("HEIC").tag(CaptureSourceFormat.heic)
                    Text("JPEG").tag(CaptureSourceFormat.jpeg)
                }
                .pickerStyle(.segmented)
            }

            Section("Ajustes") {
                Toggle(isOn: $usesAutomaticAstroExposure) {
                    Label("Exposição automática Astro", systemImage: "camera.aperture")
                }

                if usesAutomaticAstroExposure {
                    ControlSlider(
                        title: "Intervalo timelapse",
                        value: $timelapseIntervalSeconds,
                        range: 2...120,
                        step: 1,
                        suffix: "s"
                    )
                }

                ControlSlider(
                    title: "Intervalo astro",
                    value: $astroIntervalSeconds,
                    range: 1...10,
                    step: 1,
                    suffix: "s"
                )

                ControlSlider(
                    title: "Capturas por frame",
                    value: $astroBatchSize,
                    range: 5...30,
                    step: 1,
                    suffix: ""
                )
            }

            Section("Planejamento") {
                CapturePreflightCard(model: planning)
            }

            Section {
                Button {
                    AppOrientationLock.shared.unlock()
                    capturePhase = .capture
                } label: {
                    Label("Abrir câmera", systemImage: "viewfinder")
                }
                .disabled(!canStartCapture)
            }
        }
    }

    private var captureView: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            if usesNextInterface, isGridVisible {
                CameraeNextGridOverlay(style: selectedGridStyle)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            GeometryReader { proxy in
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    if isControlsVisible {
                        controls(for: proxy.size)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            if isExportingOriginalFrames {
                if usesNextInterface {
                    CameraeNextOperationOverlay(
                        state: .processing(
                            title: "Exportando originais",
                            detail: camera.originalFrameExportProgress?.detailText ?? "Preparando",
                            canCancel: true
                        ),
                        theme: .init(workflow: .astro),
                        onCancel: { exportTask?.cancel() }
                    )
                } else {
                    BlockingProgressOverlay(
                        title: "Exportando ZIP",
                        message: "Gerando pacote com os frames originais",
                        detail: camera.originalFrameExportProgress?.detailText ?? "Preparando",
                        cancelTitle: "Parar",
                        cancelAction: {
                            exportTask?.cancel()
                        }
                    )
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            if !camera.isTimelapseRunning {
                Button {
                    AppOrientationLock.shared.restorePortrait()
                    capturePhase = .setup
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Voltar para configuração")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.system(size: 18, weight: .semibold))
                Text(camera.status)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if usesNextInterface {
                Button {
                    isShowingGridPicker = true
                } label: {
                    Image(systemName: "square.grid.3x3")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Escolher grade de composição")
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isControlsVisible.toggle()
                }
            } label: {
                Image(systemName: isControlsVisible ? "eye.slash" : "eye")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(isControlsVisible ? "Esconder controles" : "Mostrar controles")

            Button {
                exportTask = Task {
                    isExportingOriginalFrames = true
                    await camera.exportLastSession()
                    exportedArchiveURLs = camera.lastExportURLs
                    isExportingOriginalFrames = false
                    exportTask = nil
                    isShowingExportedArchives = !exportedArchiveURLs.isEmpty
                }
            } label: {
                if isExportingOriginalFrames {
                    ProgressView()
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .disabled(camera.currentSession == nil || isExportingOriginalFrames)
            .accessibilityLabel("Exportar ZIP")
        }
        .foregroundStyle(.white)
        .shadow(radius: 12)
    }

    @ViewBuilder
    private func controls(for size: CGSize) -> some View {
        if usesNextInterface {
            nextControls(for: size)
        } else {
            legacyControls
        }
    }

    private var legacyControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                MetricPill(title: "Originais", value: "\(camera.frameCount)")
                MetricPill(title: "Bons", value: "\(camera.astroCompositeFrameCount)")
                MetricPill(title: "Lote", value: camera.astroBatchProgressLabel)
            }

            HStack(spacing: 8) {
                MetricPill(title: "Fase", value: camera.astroExposurePhaseLabel)
                MetricPill(title: "Base", value: camera.baseExposureLabel)
                MetricPill(title: "Última", value: camera.lastCapturedExposureLabel)
            }

            AstroBatchPreview(url: camera.astroPreviewURL)

            Button {
                Task {
                    guard let plan = planning.result?.resolvedPlan else { return }
                    if let preflight = planning.result {
                        camera.configureCapturePreflight(preflight)
                    }
                    camera.setCaptureSourceFormat(plan.sourceFormat)
                    await camera.toggleAstroBatchCapture(
                        timelapseInterval: timelapseIntervalSeconds,
                        astroInterval: astroIntervalSeconds,
                        batchSize: Int(astroBatchSize),
                        usesAutomaticExposure: usesAutomaticAstroExposure,
                        plan: plan
                    )
                }
            } label: {
                Label(
                    camera.isTimelapseRunning ? "Parar" : "Iniciar lotes astro",
                    systemImage: camera.isTimelapseRunning ? "stop.fill" : "timer"
                )
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(camera.isTimelapseRunning ? .red : .blue)
            .disabled(!camera.isTimelapseRunning && !canStartCapture)
        }
        .foregroundStyle(.white)
        .font(.system(size: 11, weight: .medium))
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.top, 8)
    }

    private func nextControls(for size: CGSize) -> some View {
        let orientation = size.width > size.height
            ? CameraeCapturePanelOrientation.landscape
            : .portrait
        let presentation = CameraeNextCaptureSessionPresentation.astro(
            originalCount: camera.frameCount,
            acceptedCount: camera.astroCompositeFrameCount,
            batch: camera.astroBatchProgressLabel,
            phase: camera.astroExposurePhaseLabel,
            baseExposure: camera.baseExposureLabel,
            lastExposure: camera.lastCapturedExposureLabel,
            isRunning: camera.isTimelapseRunning
        )

        return CameraeCaptureSessionPanel(
            theme: presentation.theme,
            orientation: orientation,
            metrics: presentation.metrics,
            actionTitle: presentation.actionTitle,
            actionSystemImage: presentation.actionSystemImage,
            isRunning: presentation.isRunning,
            isActionDisabled: !camera.isTimelapseRunning && !canStartCapture,
            showsLandscapePreview: presentation.showsLandscapePreview,
            action: {
                Task {
                    guard let plan = planning.result?.resolvedPlan else { return }
                    if let preflight = planning.result {
                        camera.configureCapturePreflight(preflight)
                    }
                    camera.setCaptureSourceFormat(plan.sourceFormat)
                    await camera.toggleAstroBatchCapture(
                        timelapseInterval: timelapseIntervalSeconds,
                        astroInterval: astroIntervalSeconds,
                        batchSize: Int(astroBatchSize),
                        usesAutomaticExposure: usesAutomaticAstroExposure,
                        plan: plan
                    )
                }
            }
        ) {
            AstroBatchPreview(url: camera.astroPreviewURL)
        }
    }

    private var plannedDuration: TimeInterval {
        durationOption.duration ?? TimeInterval(customDurationMinutes * 60)
    }

    private var planningInput: AstroPlanningInput {
        AstroPlanningInput(
            duration: plannedDuration,
            interval: astroIntervalSeconds,
            format: sourceFormat,
            batchSize: Int(astroBatchSize),
            supportedFormats: camera.supportedSourceFormats
        )
    }

    private var canStartCapture: Bool {
        guard let result = planning.result else { return false }
        return CapturePreflightPresentation(storage: result.storage).canStart
    }

    private func refreshPreflight() async {
        do {
            let plan = try CapturePlan(
                workflow: .astro,
                plannedDuration: plannedDuration,
                captureInterval: astroIntervalSeconds,
                sourceFormat: sourceFormat,
                captureFPS: nil,
                renderFPS: 30,
                resolution: .fullSensor,
                astroPipeline: resolvedAstroPipeline
            )
            let bytesPerFrame: UInt64 = sourceFormat == .heic ? 4_000_000 : 8_000_000
            await planning.evaluate(
                plan: plan,
                sizeProfile: .init(
                    bytesPerFrameUpperBound: bytesPerFrame,
                    processingOverheadFraction: 0.5,
                    publicationOverheadFraction: 0.25
                ),
                capabilityProfile: .init(
                    supportedSourceFormats: camera.supportedSourceFormats,
                    supportedAstroPipelines: [resolvedAstroPipeline]
                ),
                observedDrainPerHour: 0.20
            )
        } catch {
            // CapturePlanningViewModel publishes runtime errors; invalid UI input stays blocked.
        }
    }

    private var resolvedAstroPipeline: AstroPipelineProfile {
        let thermal: CaptureThermalState
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = .nominal
        case .fair: thermal = .fair
        case .serious: thermal = .serious
        case .critical: thermal = .critical
        @unknown default: thermal = .unknown
        }
        return AstroPipelineResolver().resolve(.init(
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            thermalState: thermal,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        ))
    }
}

private enum AstroCapturePhase {
    case setup
    case capture
}

private enum AstroDurationOption: String, CaseIterable, Identifiable {
    case thirtyMinutes
    case oneHour
    case threeHours
    case custom

    var id: String { rawValue }
    var duration: TimeInterval? {
        switch self {
        case .thirtyMinutes: 30 * 60
        case .oneHour: 60 * 60
        case .threeHours: 3 * 60 * 60
        case .custom: nil
        }
    }
    var title: String {
        switch self {
        case .thirtyMinutes: "30m"
        case .oneHour: "1h"
        case .threeHours: "3h"
        case .custom: "Custom"
        }
    }
}

private struct AstroPlanningInput: Hashable {
    let duration: TimeInterval
    let interval: TimeInterval
    let format: CaptureSourceFormat
    let batchSize: Int
    let supportedFormats: Set<CaptureSourceFormat>
}

private struct AstroBatchPreview: View {
    let url: URL?

    var body: some View {
        if let url, let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 76)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Label("Ultimo frame bom", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(8)
                }
        }
    }
}

private struct MetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ControlSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    let suffix: String
    var isDisabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(displayValue)
                    .font(.system(.body, design: .monospaced, weight: .semibold))
            }

            if let step {
                Slider(value: $value, in: range, step: step)
            } else {
                Slider(value: $value, in: range)
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .opacity(isDisabled ? 0.55 : 1)
        .disabled(isDisabled)
    }

    private var displayValue: String {
        if suffix.isEmpty {
            return String(format: "%.0f", value)
        }

        return String(format: "%.1f%@", value, suffix)
    }
}

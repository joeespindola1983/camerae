import AVFoundation
import CameraeCore
import SwiftUI
import UIKit

struct RepeatableCameraView: View {
    @StateObject private var camera: CameraController
    @StateObject private var planning: CapturePlanningViewModel

    private let project: CameraProject
    private let store: TimelapseSessionStore
    private let onClose: () -> Void
    private let onCompletedTimelapse: () -> Void
    private let onDeletedOpenedTimelapse: () -> Void
    private let explicitReferenceURL: URL?
    private let openedSession: TimelapseSession?
    @Binding private var videoSettings: WorkflowVideoSettings

    @State private var intervalSeconds = 5.0
    @State private var selectedCaptureKind = RepeatableCaptureKind.video
    @State private var overlayOpacity = 0.45
    @State private var alignmentOverlayStyle = AlignmentOverlayStyle.normal
    @State private var edgeReferenceImage: UIImage?
    @State private var edgeOverlayTint = EdgeOverlayTint.green
    @State private var edgeOverlayStroke = EdgeOverlayStroke()
    @State private var isReferenceBlinking = false
    @State private var isReferenceBlinkVisible = true
    @State private var referenceBlinkInterval = ReferenceBlinkInterval.five
    @State private var referenceBlinkOpacity = ReferenceBlinkOpacity.half
    @State private var referenceBlinkTask: Task<Void, Never>?
    @State private var evBias = 0.0
    @State private var referenceImage: UIImage?
    @State private var referenceMotion: MotionAttitude?
    @State private var referenceGeoPose: GeoPose?
    @State private var referenceOrientation: CaptureDisplayOrientation?
    @State private var referenceName = "Sem referencia"
    @State private var isShowingDeleteConfirmation = false
    @State private var deleteErrorMessage: String?
    @State private var capturePhase = RepeatableCapturePhase.setup
    @State private var isPositionHUDVisible = true
    @State private var isScaleHUDVisible = false
    @State private var isMotionHUDVisible = true
    @State private var isTimelapseInfoVisible = false
    @State private var isGridVisible = true
    @State private var isVisualMatchGuideVisible = true
    @State private var isMagnifierVisible = false
    @State private var magnifierCenter = CGPoint.zero
    @State private var magnifierZoom = AlignmentMagnifierZoom.four
    @State private var alignmentDisplaySize = CGSize.zero
    @State private var activeHUDCategory: AlignmentHUDCategory?
    @State private var referenceOverlayID = UUID()
    @State private var edgeReferenceRenderID = UUID()
    @State private var currentAlignmentOrientation = CaptureDisplayOrientation.portrait
    @State private var durationOption = RepeatableDurationOption.short
    @State private var customVideoSeconds = 90
    @State private var customTimelapseMinutes = 45
    @State private var sourceFormat = CaptureSourceFormat.heic

    init(
        project: CameraProject,
        referenceURL: URL? = nil,
        openedSession: TimelapseSession? = nil,
        videoSettings: Binding<WorkflowVideoSettings>,
        onClose: @escaping () -> Void = {},
        onCompletedTimelapse: @escaping () -> Void = {},
        onDeletedOpenedTimelapse: @escaping () -> Void = {}
    ) {
        self.project = project
        let sessionStore = TimelapseSessionStore(project: project)
        self.store = sessionStore
        self.onClose = onClose
        self.onCompletedTimelapse = onCompletedTimelapse
        self.onDeletedOpenedTimelapse = onDeletedOpenedTimelapse
        self.explicitReferenceURL = referenceURL
        self.openedSession = openedSession
        _videoSettings = videoSettings
        let referenceLens = openedSession?.cameraLens
            ?? sessionStore.cameraLens(forFrameURL: referenceURL ?? sessionStore.firstReferenceFrameURL())
        _camera = StateObject(wrappedValue: CameraController(
            project: project,
            captureMode: .repeatable,
            initialRepeatableLens: referenceLens
        ))
        _planning = StateObject(wrappedValue: CapturePlanningViewModel(
            projectDirectoryURL: project.directoryURL
        ))
    }

    var body: some View {
        Group {
            switch capturePhase {
            case .setup:
                setupView
            case .align:
                alignmentView
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if capturePhase == .setup {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) {
                        Label("Timelapses", systemImage: "chevron.left")
                    }
                    .accessibilityLabel("Voltar para timelapses")
                }
            }
        }
        .toolbar(capturePhase == .align ? .hidden : .visible, for: .navigationBar)
        .task {
            await camera.start()
            await camera.setExposureBias(evBias)
            loadReference()
        }
        .task(id: planningInput) {
            await refreshPreflight()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            refreshReferenceOverlay()
        }
        .onChange(of: camera.completedSession) {
            loadReference()
            if camera.completedSession != nil {
                AppOrientationLock.shared.unlock()
                onCompletedTimelapse()
            }
        }
        .onDisappear {
            stopReferenceBlinking()
            AppOrientationLock.shared.unlock()
        }
        .alert("Excluir esta captura?", isPresented: $isShowingDeleteConfirmation) {
            Button("Excluir captura", role: .destructive) {
                deleteOpenedTimelapse()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Essa acao apaga somente os frames, o MP4 e os arquivos desta captura. O projeto Repeatable continua salvo.")
        }
        .alert("Nao foi possivel excluir", isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
    }

    private var setupView: some View {
        List {
            Section("Captura") {
                Picker("Tipo", selection: $selectedCaptureKind) {
                    ForEach(RepeatableCaptureKind.captureOptions) { kind in
                        Label(kind.title, systemImage: kind.systemImage)
                            .tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isCaptureActive)

                if activeReferenceURL != nil {
                    RepeatableLensIndicator(lens: camera.selectedRepeatableLens)
                } else if !camera.availableRepeatableLenses.isEmpty {
                    RepeatableLensPicker(
                        lenses: camera.availableRepeatableLenses,
                        selectedLens: camera.selectedRepeatableLens,
                        isDisabled: isCaptureActive,
                        selectAction: { lens in
                            Task {
                                await camera.selectRepeatableLens(lens)
                            }
                        }
                    )
                }
            }

            Section("Ajustes") {
                Picker("Duração", selection: $durationOption) {
                    ForEach(RepeatableDurationOption.options(for: selectedCaptureKind)) { option in
                        Text(option.title(for: selectedCaptureKind)).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isCaptureActive)

                if durationOption == .custom {
                    if selectedCaptureKind == .video {
                        Stepper(
                            "Duração: \(customVideoSeconds)s",
                            value: $customVideoSeconds,
                            in: 10...3_600,
                            step: 10
                        )
                    } else {
                        Stepper(
                            "Duração: \(customTimelapseMinutes) min",
                            value: $customTimelapseMinutes,
                            in: 1...720,
                            step: 5
                        )
                    }
                }

                if selectedCaptureKind == .timelapse {
                    Picker("Formato", selection: $sourceFormat) {
                        Text("HEIC").tag(CaptureSourceFormat.heic)
                        Text("JPEG").tag(CaptureSourceFormat.jpeg)
                    }
                    .pickerStyle(.segmented)
                    .disabled(isCaptureActive)
                }

                RepeatableControlSlider(
                    title: "EV",
                    value: $evBias,
                    range: -3...3,
                    step: 1,
                    formatter: { value in
                        abs(value) < 0.05 ? "0" : String(format: "%+.0f", value)
                    },
                    isDisabled: isCaptureActive
                )
                .onChange(of: evBias) { _, newValue in
                    Task {
                        await camera.setExposureBias(newValue)
                    }
                }

                RepeatableControlSlider(
                    title: "Opacidade referencia",
                    value: $overlayOpacity,
                    range: 0...1,
                    step: 0.05,
                    formatter: { "\(Int($0 * 100))%" },
                    isDisabled: referenceImage == nil || isCaptureActive
                )

                if selectedCaptureKind == .timelapse {
                    RepeatableControlSlider(
                        title: "Intervalometro",
                        value: $intervalSeconds,
                        range: 2...10,
                        step: 1,
                        formatter: { String(format: "%.0fs", $0) },
                        isDisabled: isCaptureActive
                    )
                }
            }

            Section("Planejamento") {
                CapturePreflightCard(model: planning)
            }

            if selectedCaptureKind == .video {
                Section("Video") {
                    WorkflowVideoSettingsView(
                        settings: $videoSettings,
                        isDisabled: isCaptureActive
                    )

                    LabeledContent("Saida", value: videoSettings.summary)
                }
            }

            Section("Referencia") {
                HStack(spacing: 12) {
                    ReferenceThumbnail(imageURL: activeReferenceURL, systemImage: "photo")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(referenceImage == nil ? "Sem referencia" : referenceName)
                            .font(.headline)
                        Text("Usada como overlay no alinhamento")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Label(referenceMotion == nil ? "Rotacao nao salva" : "Rotacao salva", systemImage: "gyroscope")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Label(referenceGeoPose == nil ? "GPS nao salvo" : "GPS salvo", systemImage: "location")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Button {
                    lockToReferenceOrientation()
                    capturePhase = .align
                    refreshReferenceOverlay()
                } label: {
                    Label("Abrir alinhamento", systemImage: "viewfinder")
                }
                .disabled(isCaptureActive)
            }

            if openedSession != nil {
                Section {
                    Button(role: .destructive) {
                        isShowingDeleteConfirmation = true
                    } label: {
                        Label("Excluir captura", systemImage: "trash")
                    }
                    .disabled(isCaptureActive)
                }
            }
        }
    }

    private var alignmentView: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                CameraPreview(session: camera.session)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .ignoresSafeArea()

                if let referenceImage {
                    ReferenceOverlayImage(
                        image: overlayImage(for: referenceImage),
                        referenceOrientation: referenceOrientation,
                        displayOrientation: currentAlignmentOrientation
                    )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .opacity(referenceOverlayOpacity)
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                        .id(referenceOverlayID)
                }

                if isGridVisible {
                    RuleOfThirdsGrid()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                }

                if isMotionHUDVisible, let referenceMotion, let currentMotion = camera.currentMotion {
                    MotionAlignmentHUD(reference: referenceMotion, current: currentMotion)
                        .frame(width: min(proxy.size.width * 0.54, 220), height: min(proxy.size.width * 0.54, 220))
                        .position(x: proxy.size.width / 2, y: max(proxy.size.height - 240, proxy.size.height * 0.58))
                }

                if isVisualMatchGuideVisible,
                   let visualAlignment = camera.visualAlignment,
                   !visualAlignment.matchGuides.isEmpty {
                    VisualMatchGuideOverlay(guides: visualAlignment.matchGuides)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .allowsHitTesting(false)
                        .ignoresSafeArea()

                    if let rotationDegrees = visualAlignment.visualRotationDegrees {
                        VisualRotationHUD(rotationDegrees: rotationDegrees)
                            .frame(width: 124, height: 78)
                            .position(x: proxy.size.width / 2, y: max(proxy.size.height - 178, proxy.size.height * 0.68))
                    }
                }

                if isScaleHUDVisible, let visualAlignment = camera.visualAlignment {
                    let hudWidth = min(proxy.size.width * 0.44, 250)
                    VisualDistanceHUD(estimate: visualAlignment)
                        .frame(width: hudWidth, height: 74)
                        .position(x: min(proxy.size.width * 0.25, 145), y: 154)
                }

                if isPositionHUDVisible, let referenceGeoPose, let currentGeoPose = camera.currentGeoPose {
                    let hudSize = min(proxy.size.width * 0.34, 150)
                    GeoAlignmentHUD(reference: referenceGeoPose, current: currentGeoPose)
                        .frame(width: hudSize, height: hudSize)
                        .position(x: proxy.size.width - hudSize / 2 - 12, y: hudSize / 2 + 74)
                }

                if isPositionHUDVisible, let currentHeading = camera.currentGeoPose?.heading {
                    let hudWidth = min(proxy.size.width * 0.44, 250)
                    CompassHeadingBar(
                        referenceHeading: referenceGeoPose?.heading,
                        currentHeading: currentHeading
                    )
                    .frame(width: hudWidth, height: 54)
                    .position(x: min(proxy.size.width * 0.25, 145), y: 82)
                }

                if isMagnifierVisible {
                    AlignmentMagnifierHUD(
                        session: camera.session,
                        referenceImage: referenceImage.map(overlayImage),
                        referenceOrientation: referenceOrientation,
                        displayOrientation: currentAlignmentOrientation,
                        referenceOpacity: referenceOverlayOpacity,
                        displaySize: proxy.size,
                        center: $magnifierCenter,
                        zoom: $magnifierZoom
                    )
                }

                if activeHUDCategory != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture {
                            activeHUDCategory = nil
                        }
                }

                VStack(spacing: 0) {
                    alignmentTopBar
                    Spacer(minLength: 0)
                    alignmentBottomBar(for: proxy.size)
                }
                .padding(12)
                .foregroundStyle(.white)
                .shadow(radius: 12)

                VStack {
                    Spacer(minLength: 0)
                    hudTogglePanel
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 12)
            }
            .onAppear {
                alignmentDisplaySize = proxy.size
                initializeMagnifierPositionIfNeeded(for: proxy.size)
                updateAlignmentOrientation(for: proxy.size)
            }
            .onChange(of: proxy.size) { _, size in
                alignmentDisplaySize = size
                clampMagnifierPosition(for: size)
                updateAlignmentOrientation(for: size)
            }
        }
        .ignoresSafeArea()
    }

    private var hudTogglePanel: some View {
        HStack(spacing: 8) {
            VStack(spacing: 10) {
                categoryButton(
                    category: .trace,
                    systemImage: "scribble",
                    accessibilityLabel: "Abrir controles de traco"
                )

                categoryButton(
                    category: .guides,
                    systemImage: "viewfinder",
                    accessibilityLabel: "Abrir controles de guias"
                )

                categoryButton(
                    category: .blink,
                    systemImage: "eye",
                    accessibilityLabel: "Abrir controles de piscar referencia"
                )

                categoryButton(
                    category: .sensors,
                    systemImage: "location.north.line",
                    accessibilityLabel: "Abrir controles de sensores"
                )

                categoryButton(
                    category: .info,
                    systemImage: "info.circle",
                    accessibilityLabel: "Abrir controles de informacoes"
                )
            }
            .padding(6)
            .background(.black.opacity(0.24), in: Capsule())

            if let activeHUDCategory {
                hudCategoryOptions(for: activeHUDCategory)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: activeHUDCategory)
        .animation(.easeInOut(duration: 0.18), value: alignmentOverlayStyle)
    }

    private func hudCategoryOptions(for category: AlignmentHUDCategory) -> some View {
        HStack(spacing: 8) {
            switch category {
            case .trace:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        hudToggleButton(
                            systemImage: "scribble.variable",
                            isOn: alignmentOverlayStyle.isEdgeEnabled,
                            accessibilityLabel: "Alternar traco da referencia",
                            tint: edgeOverlayTint.swiftUIColor
                        ) {
                            alignmentOverlayStyle = alignmentOverlayStyle.isEdgeEnabled ? .normal : .referenceEdges
                            refreshReferenceOverlay()
                        }

                        ForEach(EdgeOverlayTint.allCases, id: \.self) { tint in
                            edgeColorButton(tint)
                        }
                    }

                    edgeStrokeSlider
                }

            case .guides:
                hudToggleButton(
                    systemImage: "square.grid.3x3",
                    isOn: isGridVisible,
                    accessibilityLabel: "Alternar grade de enquadramento"
                ) {
                    isGridVisible.toggle()
                }

                hudToggleButton(
                    systemImage: "point.3.connected.trianglepath.dotted",
                    isOn: isVisualMatchGuideVisible,
                    accessibilityLabel: "Alternar pontos de similaridade"
                ) {
                    isVisualMatchGuideVisible.toggle()
                }

                hudToggleButton(
                    systemImage: "arrow.up.left.and.arrow.down.right",
                    isOn: isScaleHUDVisible,
                    accessibilityLabel: "Alternar escala visual"
                ) {
                    isScaleHUDVisible.toggle()
                }

                hudToggleButton(
                    systemImage: "magnifyingglass",
                    isOn: isMagnifierVisible,
                    accessibilityLabel: "Alternar lupa de alinhamento"
                ) {
                    isMagnifierVisible.toggle()
                    if isMagnifierVisible {
                        initializeMagnifierPositionIfNeeded(for: alignmentDisplaySize)
                    }
                }

            case .blink:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        hudToggleButton(
                            systemImage: isReferenceBlinking ? "eye" : "eye.slash",
                            isOn: isReferenceBlinking,
                            accessibilityLabel: "Alternar piscar referencia"
                        ) {
                            setReferenceBlinking(!isReferenceBlinking)
                        }

                        ForEach(ReferenceBlinkInterval.allCases, id: \.self) { interval in
                            textOptionButton(
                                label: interval.label,
                                isSelected: referenceBlinkInterval == interval,
                                accessibilityLabel: "Usar intervalo de \(interval.label)"
                            ) {
                                referenceBlinkInterval = interval
                                restartReferenceBlinkingIfNeeded()
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        ForEach(ReferenceBlinkOpacity.allCases, id: \.self) { opacity in
                            textOptionButton(
                                label: opacity.label,
                                isSelected: referenceBlinkOpacity == opacity,
                                accessibilityLabel: "Usar opacidade de \(opacity.label)"
                            ) {
                                referenceBlinkOpacity = opacity
                                refreshReferenceOverlay()
                            }
                        }
                    }
                }

            case .sensors:
                hudToggleButton(
                    systemImage: "location.north.line",
                    isOn: isPositionHUDVisible,
                    accessibilityLabel: "Alternar GPS e direcao"
                ) {
                    isPositionHUDVisible.toggle()
                }

                hudToggleButton(
                    systemImage: "gyroscope",
                    isOn: isMotionHUDVisible,
                    accessibilityLabel: "Alternar orientacao"
                ) {
                    isMotionHUDVisible.toggle()
                }

            case .info:
                hudToggleButton(
                    systemImage: "info.circle",
                    isOn: isTimelapseInfoVisible,
                    accessibilityLabel: "Alternar informacoes do timelapse"
                ) {
                    isTimelapseInfoVisible.toggle()
                }
            }
        }
        .padding(6)
        .background(.black.opacity(0.24), in: Capsule())
    }

    private func categoryButton(
        category: AlignmentHUDCategory,
        systemImage: String,
        accessibilityLabel: String
    ) -> some View {
        hudToggleButton(
            systemImage: systemImage,
            isOn: activeHUDCategory == category,
            accessibilityLabel: accessibilityLabel
        ) {
            activeHUDCategory = activeHUDCategory == category ? nil : category
        }
    }

    private func edgeColorButton(_ tint: EdgeOverlayTint) -> some View {
        Button {
            edgeOverlayTint = tint
            if let referenceImage {
                renderEdgeReferenceImage(from: referenceImage)
            }
        } label: {
            Circle()
                .fill(tint.swiftUIColor)
                .frame(width: 28, height: 28)
                .overlay {
                    Circle()
                        .stroke(edgeOverlayTint == tint ? .white.opacity(0.95) : .white.opacity(0.18), lineWidth: edgeOverlayTint == tint ? 3 : 1)
                }
                .frame(width: 40, height: 40)
                .background(edgeOverlayTint == tint ? tint.swiftUIColor.opacity(0.2) : .black.opacity(0.22), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Usar traco \(tint.accessibilityName)")
    }

    private var edgeStrokeSlider: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.diagonal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(edgeOverlayTint.swiftUIColor)
                .frame(width: 22)

            Slider(
                value: Binding(
                    get: { edgeOverlayStroke.detail },
                    set: { newValue in
                        edgeOverlayStroke.detail = newValue
                        if let referenceImage {
                            renderEdgeReferenceImage(from: referenceImage)
                        }
                    }
                ),
                in: 0...1,
                step: 0.05
            )
            .tint(edgeOverlayTint.swiftUIColor)
            .frame(width: 138)

            Text("\(edgeOverlayStroke.displayValue)")
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(.black.opacity(0.22), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
        .accessibilityLabel("Ajustar detalhe das linhas")
    }

    private func textOptionButton(
        label: String,
        isSelected: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.62))
                .frame(width: 40, height: 40)
                .background(isSelected ? .white.opacity(0.2) : .black.opacity(0.22), in: Circle())
                .overlay {
                    Circle()
                        .stroke(isSelected ? .white.opacity(0.34) : .white.opacity(0.1), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func hudToggleButton(
        systemImage: String,
        isOn: Bool,
        accessibilityLabel: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isOn ? (tint ?? .white) : .white.opacity(0.42))
                .frame(width: 40, height: 40)
                .background(isOn ? (tint ?? .white).opacity(0.2) : .black.opacity(0.22), in: Circle())
                .overlay {
                    Circle()
                        .stroke(isOn ? (tint ?? .white).opacity(0.34) : .white.opacity(0.1), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var alignmentTopBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedCaptureKind.title)
                    .font(.system(size: 17, weight: .semibold))
                Text(camera.status)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let startedAt = camera.videoRecordingStartedAt {
                recordingTimer(startedAt: startedAt)
            }

            Spacer()
        }
    }

    private func alignmentBottomBar(for size: CGSize) -> some View {
        VStack(spacing: 12) {
            if isTimelapseInfoVisible {
                alignmentInfoPanel(for: size)
            }

            alignmentActionBar
        }
    }

    private func alignmentInfoPanel(for size: CGSize) -> some View {
        let isLandscape = size.width > size.height
        let maxWidth = isLandscape ? size.width * 0.5 : min(size.width * 0.86, 420)

        return VStack(spacing: 7) {
            HStack(spacing: 10) {
                RepeatableMetricPill(title: "Frames", value: "\(camera.frameCount)")
                RepeatableMetricPill(title: "EV", value: camera.baseExposureLabel)
                RepeatableMetricPill(title: "Ref", value: referenceName)
            }

            HStack(spacing: 10) {
                RepeatableMetricPill(title: "Ultima", value: camera.lastCapturedExposureLabel)
                RepeatableMetricPill(title: "Inicio", value: camera.countdownLabel)
                RepeatableMetricPill(title: "GPS", value: currentGPSLabel)
            }
        }
        .font(.system(size: isLandscape ? 10 : 11, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, isLandscape ? 8 : 10)
        .padding(.vertical, 8)
        .frame(maxWidth: maxWidth)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var alignmentActionBar: some View {
        Group {
            if isCaptureActive {
                Button {
                    Task {
                        await performPrimaryCaptureAction()
                    }
                } label: {
                    if camera.isSinglePhotoCaptureRunning {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label(activeStopButtonTitle, systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(camera.isSinglePhotoCaptureRunning)
            } else {
                HStack(spacing: 10) {
                    Button {
                        AppOrientationLock.shared.unlock()
                        capturePhase = .setup
                    } label: {
                        Label("Cancelar", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)

                    Button {
                        Task {
                            await performPrimaryCaptureAction()
                        }
                    } label: {
                        Label(primaryButtonTitle, systemImage: primaryButtonImage)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func cameraPanel(isLandscape: Bool) -> some View {
        ZStack {
            CameraPreview(session: camera.session)

            if let referenceImage {
                Image(uiImage: referenceImage)
                    .resizable()
                    .scaledToFill()
                    .opacity(overlayOpacity)
                    .allowsHitTesting(false)
            }
        }
        .aspectRatio(isLandscape ? 16.0 / 9.0 : 3.0 / 4.0, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .background(Color.black, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.system(size: 18, weight: .semibold))
                Text(camera.status)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if openedSession != nil {
                Button {
                    isShowingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .disabled(camera.isTimelapseRunning || camera.isVideoRecording)
                .accessibilityLabel("Excluir captura")
            }
        }
        .foregroundStyle(.white)
        .shadow(radius: 12)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("Tipo", selection: $selectedCaptureKind) {
                ForEach(RepeatableCaptureKind.captureOptions) { kind in
                    Label(kind.title, systemImage: kind.systemImage)
                        .tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .disabled(camera.isTimelapseRunning || camera.isSinglePhotoCaptureRunning || camera.isVideoRecording)

            HStack {
                RepeatableMetricPill(title: "Frames", value: "\(camera.frameCount)")
                RepeatableMetricPill(title: "EV", value: camera.baseExposureLabel)
                RepeatableMetricPill(title: "Ref", value: referenceName)
            }

            HStack {
                RepeatableMetricPill(title: "Ultima", value: camera.lastCapturedExposureLabel)
                RepeatableMetricPill(title: "Inicio", value: camera.countdownLabel)
                RepeatableMetricPill(title: "GPS", value: currentGPSLabel)
            }

            RepeatableControlSlider(
                title: "EV",
                value: $evBias,
                range: -3...3,
                step: 1,
                formatter: { value in
                    abs(value) < 0.05 ? "0" : String(format: "%+.0f", value)
                },
                isDisabled: camera.isTimelapseRunning || camera.isSinglePhotoCaptureRunning || camera.isVideoRecording
            )
            .onChange(of: evBias) { _, newValue in
                Task {
                    await camera.setExposureBias(newValue)
                }
            }

            RepeatableControlSlider(
                title: "Opacidade referencia",
                value: $overlayOpacity,
                range: 0...1,
                step: 0.05,
                formatter: { "\(Int($0 * 100))%" },
                isDisabled: referenceImage == nil || camera.isSinglePhotoCaptureRunning || camera.isVideoRecording
            )

            if selectedCaptureKind == .timelapse {
                RepeatableControlSlider(
                    title: "Intervalometro",
                    value: $intervalSeconds,
                    range: 2...10,
                    step: 1,
                    formatter: { String(format: "%.0fs", $0) },
                    isDisabled: camera.isTimelapseRunning || camera.isVideoRecording
                )
            }

            Button {
                Task {
                    switch selectedCaptureKind {
                    case .timelapse:
                        guard let plan = planning.result?.resolvedPlan else { return }
                        if let preflight = planning.result {
                            camera.configureCapturePreflight(preflight)
                        }
                        camera.setCaptureSourceFormat(plan.sourceFormat)
                        await camera.toggleTimelapse(
                            interval: intervalSeconds,
                            plan: plan
                        )
                    case .video:
                        guard let plan = planning.result?.resolvedPlan else { return }
                        if let preflight = planning.result {
                            camera.configureCapturePreflight(preflight)
                        }
                        await camera.toggleVideoRecording(plan: plan)
                    case .photo:
                        await camera.captureSinglePhoto()
                    }
                }
            } label: {
                if camera.isSinglePhotoCaptureRunning {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label(primaryButtonTitle, systemImage: primaryButtonImage)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(camera.isTimelapseRunning || camera.isVideoRecording ? .red : .blue)
            .disabled(camera.isSinglePhotoCaptureRunning)
            .disabled(!isCaptureActive && !canStartCapture)
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.top, 10)
    }

    private var primaryButtonTitle: String {
        if camera.isTimelapseRunning || camera.isVideoRecording {
            return activeStopButtonTitle
        }

        switch selectedCaptureKind {
        case .timelapse:
            return "Iniciar timelapse"
        case .video:
            return "Gravar video"
        case .photo:
            return "Capturar foto"
        }
    }

    private var primaryButtonImage: String {
        if camera.isTimelapseRunning || camera.isVideoRecording {
            return "stop.fill"
        }

        return selectedCaptureKind.systemImage
    }

    private var activeStopButtonTitle: String {
        switch selectedCaptureKind {
        case .timelapse:
            return "Finalizar timelapse"
        case .video:
            return "Finalizar video"
        case .photo:
            return "Finalizar"
        }
    }

    @ViewBuilder
    private func recordingTimer(startedAt: Date) -> some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            let elapsed = max(0, Int(context.date.timeIntervalSince(startedAt)))
            Label(Self.formattedRecordingDuration(elapsed), systemImage: "record.circle.fill")
                .font(.system(.body, design: .monospaced, weight: .semibold))
                .foregroundStyle(.red)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .accessibilityLabel("Tempo de gravacao")
                .accessibilityValue(Self.formattedRecordingDuration(elapsed))
        }
    }

    private static func formattedRecordingDuration(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func performPrimaryCaptureAction() async {
        camera.setPendingReferenceOrientation(currentAlignmentOrientation)
        switch selectedCaptureKind {
        case .timelapse:
            guard let plan = planning.result?.resolvedPlan else { return }
            if let preflight = planning.result {
                camera.configureCapturePreflight(preflight)
            }
            camera.setCaptureSourceFormat(plan.sourceFormat)
            await camera.toggleTimelapse(
                interval: intervalSeconds,
                plan: plan
            )
        case .video:
            guard let plan = planning.result?.resolvedPlan else { return }
            if let preflight = planning.result {
                camera.configureCapturePreflight(preflight)
            }
            await camera.toggleVideoRecording(plan: plan)
        case .photo:
            await camera.captureSinglePhoto()
        }
    }

    private var isCaptureActive: Bool {
        camera.isTimelapseRunning || camera.isVideoRecording || camera.isSinglePhotoCaptureRunning
    }

    private var plannedDuration: TimeInterval {
        if let preset = durationOption.duration(for: selectedCaptureKind) {
            return preset
        }
        return selectedCaptureKind == .video
            ? TimeInterval(customVideoSeconds)
            : TimeInterval(customTimelapseMinutes * 60)
    }

    private var planningInput: RepeatablePlanningInput {
        RepeatablePlanningInput(
            kind: selectedCaptureKind,
            duration: plannedDuration,
            interval: intervalSeconds,
            format: sourceFormat,
            fps: videoSettings.fps
        )
    }

    private var canStartCapture: Bool {
        guard let result = planning.result else { return false }
        return CapturePreflightPresentation(storage: result.storage).canStart
    }

    private func refreshPreflight() async {
        guard selectedCaptureKind != .photo else { return }
        do {
            let workflow: CaptureWorkflow = selectedCaptureKind == .video
                ? .repeatableVideo
                : .repeatableTimelapse
            let plan = try CapturePlan(
                workflow: workflow,
                plannedDuration: plannedDuration,
                captureInterval: selectedCaptureKind == .timelapse ? intervalSeconds : nil,
                sourceFormat: sourceFormat,
                captureFPS: selectedCaptureKind == .video ? videoSettings.fps : nil,
                renderFPS: selectedCaptureKind == .timelapse ? videoSettings.fps : nil,
                resolution: captureResolution,
                astroPipeline: nil
            )
            let profile = selectedCaptureKind == .video
                ? CaptureSizeProfile(
                    videoBitsPerSecondUpperBound: videoBitsPerSecondUpperBound,
                    publicationOverheadFraction: 0.10
                )
                : CaptureSizeProfile(
                    bytesPerFrameUpperBound: sourceFormat == .heic ? 4_000_000 : 8_000_000,
                    processingOverheadFraction: 0.10,
                    publicationOverheadFraction: 0.20
                )
            await planning.evaluate(
                plan: plan,
                sizeProfile: profile,
                capabilityProfile: .init(
                    supportedSourceFormats: [.heic, .jpeg],
                    supportedAstroPipelines: []
                ),
                observedDrainPerHour: selectedCaptureKind == .video ? 0.12 : 0.10
            )
        } catch {
            // Invalid transient UI input leaves capture blocked.
        }
    }

    private var captureResolution: CaptureResolution {
        guard selectedCaptureKind == .video else { return .fullSensor }
        switch videoSettings.resolution {
        case .preview: return .fullHD
        case .fourK: return .ultraHD
        case .full: return .fullSensor
        }
    }

    private var videoBitsPerSecondUpperBound: UInt64 {
        let base: Double
        switch videoSettings.resolution {
        case .preview: base = 16_000_000
        case .fourK: base = 60_000_000
        case .full: base = 80_000_000
        }
        let frameRateFactor = max(Double(videoSettings.fps) / 30, 1)
        return UInt64(ceil(base * frameRateFactor * videoSettings.quality.bitRateMultiplier))
    }

    private var activeReferenceURL: URL? {
        explicitReferenceURL ?? store.firstReferenceFrameURL()
    }

    private var currentGPSLabel: String {
        guard let currentGeoPose = camera.currentGeoPose else {
            return "sem fino"
        }

        return String(format: "±%.0fm", currentGeoPose.horizontalAccuracy)
    }

    private func loadReference() {
        guard let referenceURL = activeReferenceURL,
              let image = UIImage(contentsOfFile: referenceURL.path) else {
            referenceImage = nil
            edgeReferenceImage = nil
            edgeReferenceRenderID = UUID()
            isReferenceBlinking = false
            stopReferenceBlinking()
            referenceMotion = nil
            referenceGeoPose = nil
            referenceOrientation = nil
            referenceName = "Sem ref"
            Task {
                await camera.setVisualReference(nil)
            }
            return
        }

        referenceImage = image
        renderEdgeReferenceImage(from: image)
        referenceMotion = store.referenceMotion(forFrameURL: referenceURL)
        referenceGeoPose = store.referenceGeoPose(forFrameURL: referenceURL)
        referenceOrientation = store.referenceOrientation(forFrameURL: referenceURL) ?? CaptureDisplayOrientation(image: image)
        referenceName = referenceURL.lastPathComponent.replacingOccurrences(of: "frame_", with: "")
        Task {
            await camera.setVisualReference(referenceURL)
        }
    }

    private func overlayImage(for referenceImage: UIImage) -> UIImage {
        guard alignmentOverlayStyle.isEdgeEnabled else {
            return referenceImage
        }

        return edgeReferenceImage ?? referenceImage
    }

    private var referenceOverlayOpacity: Double {
        if isReferenceBlinking {
            return isReferenceBlinkVisible ? referenceBlinkOpacity.opacity : 0
        }

        return alignmentOverlayStyle.isEdgeEnabled ? 1 : overlayOpacity
    }

    private func setReferenceBlinking(_ isEnabled: Bool) {
        isReferenceBlinking = isEnabled
        if isEnabled {
            startReferenceBlinking()
        } else {
            stopReferenceBlinking()
        }
        refreshReferenceOverlay()
    }

    private func restartReferenceBlinkingIfNeeded() {
        guard isReferenceBlinking else { return }
        startReferenceBlinking()
    }

    private func startReferenceBlinking() {
        referenceBlinkTask?.cancel()
        isReferenceBlinkVisible = true
        let interval = referenceBlinkInterval.seconds

        referenceBlinkTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    isReferenceBlinkVisible.toggle()
                    refreshReferenceOverlay()
                }
            }
        }
    }

    private func stopReferenceBlinking() {
        referenceBlinkTask?.cancel()
        referenceBlinkTask = nil
        isReferenceBlinkVisible = true
    }

    private func renderEdgeReferenceImage(from image: UIImage) {
        edgeReferenceImage = nil
        let renderID = UUID()
        let tint = edgeOverlayTint
        let stroke = edgeOverlayStroke
        edgeReferenceRenderID = renderID

        Task.detached(priority: .userInitiated) {
            let rendered = EdgeOverlayRenderer.render(
                image: image,
                options: EdgeOverlayOptions(tint: tint, stroke: stroke, inverted: false)
            )

            await MainActor.run {
                guard edgeReferenceRenderID == renderID else { return }
                edgeReferenceImage = rendered
                refreshReferenceOverlay()
            }
        }
    }

    private func refreshReferenceOverlay() {
        referenceOverlayID = UUID()
    }

    private func lockToReferenceOrientation() {
        guard let referenceOrientation else { return }
        currentAlignmentOrientation = referenceOrientation
        camera.setPendingReferenceOrientation(referenceOrientation)
        AppOrientationLock.shared.lock(to: referenceOrientation)
    }

    private func updateAlignmentOrientation(for size: CGSize) {
        if capturePhase == .align, referenceOrientation != nil {
            return
        }

        let orientation = CaptureDisplayOrientation(displaySize: size)
        if currentAlignmentOrientation != orientation {
            currentAlignmentOrientation = orientation
            refreshReferenceOverlay()
        }
    }

    private func initializeMagnifierPositionIfNeeded(for size: CGSize) {
        guard size.width > 0, size.height > 0, magnifierCenter == .zero else { return }
        let geometry = AlignmentMagnifierGeometry(displaySize: size)
        magnifierCenter = geometry.initialCenter
    }

    private func clampMagnifierPosition(for size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let geometry = AlignmentMagnifierGeometry(displaySize: size)
        magnifierCenter = magnifierCenter == .zero
            ? geometry.initialCenter
            : geometry.clampedCenter(magnifierCenter)
    }

    private func deleteOpenedTimelapse() {
        guard let openedSession else { return }

        do {
            try store.deleteSession(openedSession)
            onDeletedOpenedTimelapse()
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
    }
}

private extension EdgeOverlayTint {
    var swiftUIColor: Color {
        switch self {
        case .red:
            return .red
        case .green:
            return .green
        case .blue:
            return .blue
        }
    }

    var accessibilityName: String {
        switch self {
        case .red:
            return "vermelho"
        case .green:
            return "verde"
        case .blue:
            return "azul"
        }
    }
}

private enum AlignmentHUDCategory {
    case trace
    case guides
    case blink
    case sensors
    case info
}

private enum ReferenceBlinkInterval: CaseIterable {
    case two
    case five
    case ten

    var seconds: Double {
        switch self {
        case .two:
            return 2
        case .five:
            return 5
        case .ten:
            return 10
        }
    }

    var label: String {
        switch self {
        case .two:
            return "2s"
        case .five:
            return "5s"
        case .ten:
            return "10s"
        }
    }
}

private enum ReferenceBlinkOpacity: CaseIterable {
    case quarter
    case half
    case full

    var opacity: Double {
        switch self {
        case .quarter:
            return 0.25
        case .half:
            return 0.5
        case .full:
            return 1
        }
    }

    var label: String {
        switch self {
        case .quarter:
            return "25"
        case .half:
            return "50"
        case .full:
            return "100"
        }
    }
}

private enum RepeatableCapturePhase {
    case setup
    case align
}

enum AlignmentMagnifierZoom: CGFloat, CaseIterable, Equatable {
    case two = 2
    case four = 4
    case six = 6

    var next: AlignmentMagnifierZoom {
        switch self {
        case .two: return .four
        case .four: return .six
        case .six: return .two
        }
    }

    var label: String {
        "\(Int(rawValue))×"
    }
}

struct AlignmentMagnifierGeometry: Equatable {
    let displaySize: CGSize
    let lensSize: CGFloat
    let margin: CGFloat

    init(displaySize: CGSize, lensSize: CGFloat = 140, margin: CGFloat = 8) {
        self.displaySize = displaySize
        self.lensSize = lensSize
        self.margin = margin
    }

    var initialCenter: CGPoint {
        clampedCenter(CGPoint(
            x: displaySize.width - lensSize / 2 - 16,
            y: lensSize / 2 + 76
        ))
    }

    func clampedCenter(_ point: CGPoint) -> CGPoint {
        let inset = lensSize / 2 + margin
        let maximumX = max(inset, displaySize.width - inset)
        let maximumY = max(inset, displaySize.height - inset)
        return CGPoint(
            x: min(max(point.x, inset), maximumX),
            y: min(max(point.y, inset), maximumY)
        )
    }

    func contentOffset(samplePoint: CGPoint, zoom: CGFloat) -> CGSize {
        CGSize(
            width: lensSize / 2 - samplePoint.x * zoom,
            height: lensSize / 2 - samplePoint.y * zoom
        )
    }
}

private struct AlignmentMagnifierHUD: View {
    let session: AVCaptureSession
    let referenceImage: UIImage?
    let referenceOrientation: CaptureDisplayOrientation?
    let displayOrientation: CaptureDisplayOrientation
    let referenceOpacity: Double
    let displaySize: CGSize
    @Binding var center: CGPoint
    @Binding var zoom: AlignmentMagnifierZoom

    private let lensSize: CGFloat = 140
    @GestureState private var dragTranslation = CGSize.zero

    var body: some View {
        let geometry = AlignmentMagnifierGeometry(displaySize: displaySize, lensSize: lensSize)
        let renderedCenter = geometry.clampedCenter(CGPoint(
            x: center.x + dragTranslation.width,
            y: center.y + dragTranslation.height
        ))

        ZStack(alignment: .topLeading) {
            magnifiedComposite(samplePoint: renderedCenter, geometry: geometry)
                .allowsHitTesting(false)

            Rectangle()
                .stroke(.white.opacity(0.92), lineWidth: 2)

            Path { path in
                let middle = lensSize / 2
                path.move(to: CGPoint(x: middle - 10, y: middle))
                path.addLine(to: CGPoint(x: middle + 10, y: middle))
                path.move(to: CGPoint(x: middle, y: middle - 10))
                path.addLine(to: CGPoint(x: middle, y: middle + 10))
            }
            .stroke(.white.opacity(0.9), lineWidth: 1)

            Text(zoom.label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.black.opacity(0.58), in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(7)
        }
        .frame(width: lensSize, height: lensSize)
        .background(.black)
        .clipShape(Rectangle())
        .shadow(color: .black.opacity(0.5), radius: 12, y: 5)
        .position(renderedCenter)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($dragTranslation) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    center = geometry.clampedCenter(CGPoint(
                        x: center.x + value.translation.width,
                        y: center.y + value.translation.height
                    ))
                }
        )
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    zoom = zoom.next
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lupa de alinhamento")
        .accessibilityValue("Zoom \(zoom.label)")
        .accessibilityHint("Arraste para mover e toque duas vezes para alterar o zoom")
    }

    private func magnifiedComposite(
        samplePoint: CGPoint,
        geometry: AlignmentMagnifierGeometry
    ) -> some View {
        let scale = zoom.rawValue
        let offset = geometry.contentOffset(samplePoint: samplePoint, zoom: scale)

        return ZStack {
            CameraPreview(session: session)
                .frame(width: displaySize.width, height: displaySize.height)

            if let referenceImage {
                ReferenceOverlayImage(
                    image: referenceImage,
                    referenceOrientation: referenceOrientation,
                    displayOrientation: displayOrientation
                )
                .frame(width: displaySize.width, height: displaySize.height)
                .opacity(referenceOpacity)
            }
        }
        .frame(width: displaySize.width, height: displaySize.height, alignment: .topLeading)
        .scaleEffect(scale, anchor: .topLeading)
        .offset(offset)
    }
}

private struct ReferenceOverlayImage: View {
    let image: UIImage
    let referenceOrientation: CaptureDisplayOrientation?
    let displayOrientation: CaptureDisplayOrientation

    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct RuleOfThirdsGrid: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let lineColor = Color.white.opacity(0.5)
            let diagonalColor = Color.white.opacity(0.3)
            let centerColor = Color.white.opacity(0.24)
            let accentColor = Color.cyan.opacity(0.72)

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: size.width / 3, y: 0))
                    path.addLine(to: CGPoint(x: size.width / 3, y: size.height))
                    path.move(to: CGPoint(x: size.width * 2 / 3, y: 0))
                    path.addLine(to: CGPoint(x: size.width * 2 / 3, y: size.height))
                    path.move(to: CGPoint(x: 0, y: size.height / 3))
                    path.addLine(to: CGPoint(x: size.width, y: size.height / 3))
                    path.move(to: CGPoint(x: 0, y: size.height * 2 / 3))
                    path.addLine(to: CGPoint(x: size.width, y: size.height * 2 / 3))
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: 1, lineCap: .round))

                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                    path.move(to: CGPoint(x: 0, y: size.height))
                    path.addLine(to: CGPoint(x: size.width, y: 0))
                }
                .stroke(diagonalColor, style: StrokeStyle(lineWidth: 1, lineCap: .round))

                Path { path in
                    let crossLength = min(size.width, size.height) * 0.055
                    path.move(to: CGPoint(x: size.width / 2 - crossLength, y: size.height / 2))
                    path.addLine(to: CGPoint(x: size.width / 2 + crossLength, y: size.height / 2))
                    path.move(to: CGPoint(x: size.width / 2, y: size.height / 2 - crossLength))
                    path.addLine(to: CGPoint(x: size.width / 2, y: size.height / 2 + crossLength))
                }
                .stroke(centerColor, style: StrokeStyle(lineWidth: 1, lineCap: .round))

                ForEach(Array(gridIntersections(in: size).enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(accentColor)
                        .frame(width: 5, height: 5)
                        .position(point)
                }
            }
            .shadow(color: .black.opacity(0.38), radius: 2, x: 0, y: 1)
        }
    }

    private func gridIntersections(in size: CGSize) -> [CGPoint] {
        [
            CGPoint(x: size.width / 3, y: size.height / 3),
            CGPoint(x: size.width * 2 / 3, y: size.height / 3),
            CGPoint(x: size.width / 3, y: size.height * 2 / 3),
            CGPoint(x: size.width * 2 / 3, y: size.height * 2 / 3)
        ]
    }
}

private struct VisualMatchGuideOverlay: View {
    let guides: [VisualMatchGuide]

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                for guide in guides {
                    let referencePoint = screenPoint(for: guide.reference, in: size)
                    let currentPoint = screenPoint(for: guide.current, in: size)
                    let isMatched = isMatched(referencePoint, currentPoint, in: size)

                    let referenceRect = CGRect(
                        x: referencePoint.x - 8,
                        y: referencePoint.y - 8,
                        width: 16,
                        height: 16
                    )
                    context.fill(Path(ellipseIn: referenceRect), with: .color(.black.opacity(0.42)))
                    context.stroke(
                        Path(ellipseIn: referenceRect),
                        with: .color(isMatched ? .green.opacity(0.98) : .cyan.opacity(0.98)),
                        lineWidth: 2
                    )

                    let currentRect = CGRect(
                        x: currentPoint.x - 6,
                        y: currentPoint.y - 6,
                        width: 12,
                        height: 12
                    )
                    context.fill(
                        Path(ellipseIn: currentRect),
                        with: .color(isMatched ? .green.opacity(0.98) : .yellow.opacity(0.98))
                    )
                    context.stroke(Path(ellipseIn: currentRect), with: .color(.black.opacity(0.5)), lineWidth: 1)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func screenPoint(for normalizedPoint: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: normalizedPoint.x * size.width,
            y: (1 - normalizedPoint.y) * size.height
        )
    }

    private func isMatched(_ start: CGPoint, _ end: CGPoint, in size: CGSize) -> Bool {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = sqrt(dx * dx + dy * dy)
        return distance <= max(14, min(size.width, size.height) * 0.024)
    }
}

private struct VisualRotationHUD: View {
    let rotationDegrees: Double

    private var clampedRotation: Double {
        min(max(rotationDegrees, -18), 18)
    }

    private var isAligned: Bool {
        abs(rotationDegrees) < 0.8
    }

    private var tint: Color {
        isAligned ? .green : .yellow
    }

    private var title: String {
        if isAligned {
            return "ROT OK"
        }

        return rotationDegrees > 0 ? "GIRE DIR" : "GIRE ESQ"
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = CGPoint(x: size.width / 2, y: 32)
            let radius = min(size.width * 0.28, 30)

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black.opacity(0.32))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.white.opacity(0.14), lineWidth: 1)
                    }

                Canvas { context, _ in
                    let arcRect = CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )

                    var baseArc = Path()
                    baseArc.addArc(
                        center: center,
                        radius: radius,
                        startAngle: .degrees(205),
                        endAngle: .degrees(335),
                        clockwise: false
                    )
                    context.stroke(baseArc, with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: 4, lineCap: .round))

                    var needle = Path()
                    needle.move(to: center)
                    let needleAngle = Angle(degrees: -90 + clampedRotation * 3.1).radians
                    needle.addLine(to: CGPoint(
                        x: center.x + cos(needleAngle) * radius * 0.86,
                        y: center.y + sin(needleAngle) * radius * 0.86
                    ))
                    context.stroke(needle, with: .color(tint.opacity(0.95)), style: StrokeStyle(lineWidth: 3, lineCap: .round))

                    context.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)), with: .color(.white.opacity(0.9)))
                    context.stroke(Path(ellipseIn: arcRect), with: .color(.clear), lineWidth: 0)
                }

                VStack(spacing: 1) {
                    Spacer()
                    Text(title)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(tint)
                    Text(String(format: "%+.1f°", rotationDegrees))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.82))
                }
                .padding(.bottom, 7)
            }
        }
    }
}

private extension CaptureDisplayOrientation {
    init(displaySize: CGSize) {
        self = displaySize.width > displaySize.height ? .landscapeRight : .portrait
    }

    init(image: UIImage) {
        if image.size.width > image.size.height {
            self = .landscapeRight
        } else {
            self = .portrait
        }
    }
}

private struct RepeatableLensPicker: View {
    let lenses: [RepeatableCameraLens]
    let selectedLens: RepeatableCameraLens
    let isDisabled: Bool
    let selectAction: (RepeatableCameraLens) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Camera")
                .font(.subheadline.weight(.medium))

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 10),
                    count: max(lenses.count, 1)
                ),
                spacing: 10
            ) {
                ForEach(lenses) { lens in
                    Button {
                        selectAction(lens)
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: lens.systemImage)
                                .font(.system(size: 22, weight: .medium))
                            Text(lens.shortTitle)
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                            Text(lens.title)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(selectedLens == lens ? Color.white : Color.primary)
                        .background(
                            selectedLens == lens ? Color.accentColor : Color.secondary.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    selectedLens == lens ? Color.accentColor : Color.secondary.opacity(0.2),
                                    lineWidth: 1
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isDisabled)
                    .accessibilityLabel("Camera \(lens.title), \(lens.shortTitle)")
                    .accessibilityAddTraits(selectedLens == lens ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RepeatableLensIndicator: View {
    let lens: RepeatableCameraLens

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: lens.systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Camera em uso")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(lens.title) · \(lens.shortTitle)")
                    .font(.subheadline.weight(.semibold))
            }

            Spacer()

            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Camera em uso: \(lens.title), \(lens.shortTitle)")
    }
}

private struct RepeatableMetricPill: View {
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

private struct MotionAlignmentHUD: View {
    let reference: MotionAttitude
    let current: MotionAttitude

    private var delta: MotionAttitude {
        current.delta(from: reference)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size * 0.36
            let offset = currentOffset(radius: radius)

            ZStack {
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 1)
                    .frame(width: size * 0.82, height: size * 0.82)

                Circle()
                    .stroke(.white.opacity(0.09), lineWidth: 1)
                    .frame(width: size * 0.54, height: size * 0.54)

                Rectangle()
                    .fill(.white.opacity(0.16))
                    .frame(width: size * 0.72, height: 1)

                Rectangle()
                    .fill(.white.opacity(0.16))
                    .frame(width: 1, height: size * 0.72)

                Circle()
                    .stroke(.cyan.opacity(0.95), lineWidth: 2)
                    .frame(width: 18, height: 18)

                Rectangle()
                    .fill(.cyan.opacity(0.85))
                    .frame(width: 2, height: size * 0.18)
                    .offset(y: -size * 0.09)

                Rectangle()
                    .fill(.yellow.opacity(0.9))
                    .frame(width: 2, height: size * 0.24)
                    .offset(y: -size * 0.12)
                    .rotationEffect(.degrees(delta.z))

                Circle()
                    .fill(.yellow.opacity(0.96))
                    .frame(width: 14, height: 14)
                    .overlay {
                        Circle()
                            .stroke(.black.opacity(0.35), lineWidth: 1)
                    }
                    .offset(offset)

                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        axisPill("X", delta.x)
                        axisPill("Y", delta.y)
                        axisPill("Z", delta.z)
                    }
                }
                .padding(.bottom, 8)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(.black.opacity(0.18), in: Circle())
        }
        .allowsHitTesting(false)
    }

    private func currentOffset(radius: CGFloat) -> CGSize {
        let x = CGFloat(clamped(delta.y / 18)) * radius
        let y = CGFloat(clamped(-delta.x / 18)) * radius
        return CGSize(width: x, height: y)
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, -1), 1)
    }

    private func axisPill(_ axis: String, _ value: Double) -> some View {
        HStack(spacing: 3) {
            Text(axis)
                .foregroundStyle(.white.opacity(0.65))
            Text(String(format: "%+.1f", value))
                .foregroundStyle(abs(value) < 2 ? .green : .white)
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.black.opacity(0.38), in: Capsule())
    }
}

private struct VisualDistanceHUD: View {
    let estimate: VisualAlignmentEstimate

    private var isFineAdjustment: Bool {
        estimate.isFineAdjustment
    }

    private var scaleRange: Double {
        isFineAdjustment ? 0.035 : 0.16
    }

    private var markerOffset: Double {
        min(max((estimate.scale - 1) / scaleRange, -1), 1)
    }

    private var title: String {
        if isFineAdjustment {
            if abs(estimate.scale - 1) < 0.008 {
                return "FINO OK"
            }

            return estimate.scale < 1 ? "AFASTE LEVE" : "APROXIME LEVE"
        }

        switch estimate.distanceHint {
        case .searching:
            return "ANALISANDO"
        case .moveForward:
            return "APROXIME"
        case .moveBack:
            return "AFASTE"
        case .matched:
            return "ESCALA OK"
        }
    }

    private var tint: Color {
        if isFineAdjustment {
            return abs(estimate.scale - 1) < 0.008 ? .green : .cyan
        }

        switch estimate.distanceHint {
        case .searching:
            return .white.opacity(0.7)
        case .matched:
            return .green
        case .moveForward, .moveBack:
            return .yellow
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let markerX = width / 2 + CGFloat(markerOffset) * (width * 0.38)

            VStack(spacing: 8) {
                HStack {
                    Text(isFineAdjustment ? "- FINO" : "MENOR")
                    Spacer()
                    Text(title)
                        .foregroundStyle(tint)
                    Spacer()
                    Text(isFineAdjustment ? "+ FINO" : "MAIOR")
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.58))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.16))
                        .frame(height: 6)

                    Rectangle()
                        .fill(.white.opacity(0.24))
                        .frame(width: 1, height: 18)
                        .position(x: width / 2, y: 3)

                    Circle()
                        .fill(tint)
                        .frame(width: 16, height: 16)
                        .position(x: markerX, y: 3)
                }
                .frame(height: 18)

                Text(detailLabel)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }

    private var detailLabel: String {
        if isFineAdjustment {
            return String(format: "ajuste fino | escala %.3f", estimate.scale)
        }

        return String(format: "escala %.2f", estimate.scale)
    }
}

private struct CompassHeadingBar: View {
    let referenceHeading: Double?
    let currentHeading: Double

    private var normalizedCurrent: Double {
        normalized(currentHeading)
    }

    private var normalizedReference: Double? {
        referenceHeading.map(normalized)
    }

    private var deltaLabel: String {
        guard let normalizedReference else {
            return "--"
        }

        let delta = normalizedSigned(normalizedCurrent - normalizedReference)
        return String(format: "%+.0f", delta)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let currentX = xPosition(for: normalizedCurrent, width: width)
            let referenceX = normalizedReference.map { xPosition(for: $0, width: width) }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black.opacity(0.34))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.white.opacity(0.16), lineWidth: 1)
                    }

                ForEach([0, 90, 180, 270, 360], id: \.self) { value in
                    let x = xPosition(for: Double(value), width: width)
                    VStack(spacing: 3) {
                        Rectangle()
                            .fill(.white.opacity(0.28))
                            .frame(width: 1, height: value % 180 == 0 ? 16 : 10)
                        Text("\(value)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                    .position(x: x, y: 24)
                }

                if let referenceX {
                    VStack(spacing: 2) {
                        Triangle()
                            .fill(.cyan.opacity(0.95))
                            .frame(width: 12, height: 8)
                        Text("REF")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan.opacity(0.9))
                    }
                    .position(x: referenceX, y: 11)
                }

                VStack(spacing: 2) {
                    Text(String(format: "%.0f", normalizedCurrent))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.yellow.opacity(0.95))
                    Triangle()
                        .fill(.yellow.opacity(0.96))
                        .frame(width: 14, height: 10)
                        .rotationEffect(.degrees(180))
                }
                .position(x: currentX, y: 42)

                Text(deltaLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(referenceHeading == nil ? .white.opacity(0.42) : .white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.42), in: Capsule())
                    .position(x: width / 2, y: 42)
            }
        }
        .allowsHitTesting(false)
    }

    private func xPosition(for heading: Double, width: CGFloat) -> CGFloat {
        let clampedHeading = min(max(heading, 0), 360)
        return CGFloat(clampedHeading / 360) * (width - 20) + 10
    }

    private func normalized(_ value: Double) -> Double {
        var result = value.truncatingRemainder(dividingBy: 360)
        if result < 0 {
            result += 360
        }
        return result
    }

    private func normalizedSigned(_ value: Double) -> Double {
        var result = value
        while result > 180 { result -= 360 }
        while result < -180 { result += 360 }
        return result
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct GeoAlignmentHUD: View {
    let reference: GeoPose
    let current: GeoPose

    private var offset: CGSize {
        current.offsetMeters(from: reference)
    }

    private var distance: Double {
        sqrt(offset.width * offset.width + offset.height * offset.height)
    }

    private var scaleMeters: Double {
        max(8, min(50, max(distance * 1.35, current.horizontalAccuracy)))
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size * 0.34
            let dotOffset = currentOffset(radius: radius)

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black.opacity(0.24))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.white.opacity(0.14), lineWidth: 1)
                    }

                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 1)
                    .frame(width: radius * 2, height: radius * 2)

                Rectangle()
                    .fill(.white.opacity(0.14))
                    .frame(width: radius * 1.72, height: 1)

                Rectangle()
                    .fill(.white.opacity(0.14))
                    .frame(width: 1, height: radius * 1.72)

                Circle()
                    .stroke(.cyan.opacity(0.95), lineWidth: 2)
                    .frame(width: 14, height: 14)

                Circle()
                    .fill(.yellow.opacity(0.96))
                    .frame(width: 12, height: 12)
                    .overlay {
                        Circle()
                            .stroke(.black.opacity(0.35), lineWidth: 1)
                    }
                    .offset(dotOffset)

                VStack {
                    HStack {
                        Text("GPS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text(String(format: "%.1fm", distance))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(distance < 2 ? .green : .white)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        axisPill("E", Double(offset.width))
                        axisPill("N", Double(offset.height))
                    }
                }
                .padding(8)
            }
        }
        .allowsHitTesting(false)
    }

    private func currentOffset(radius: CGFloat) -> CGSize {
        let x = CGFloat(clamped(Double(offset.width) / scaleMeters)) * radius
        let y = CGFloat(clamped(-Double(offset.height) / scaleMeters)) * radius
        return CGSize(width: x, height: y)
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, -1), 1)
    }

    private func axisPill(_ axis: String, _ value: Double) -> some View {
        HStack(spacing: 3) {
            Text(axis)
                .foregroundStyle(.white.opacity(0.62))
            Text(String(format: "%+.1f", value))
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(.black.opacity(0.38), in: Capsule())
    }
}

private struct RepeatableControlSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let formatter: (Double) -> String
    var isDisabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(formatter(value))
                    .font(.system(.body, design: .monospaced, weight: .semibold))
            }

            Slider(value: $value, in: range, step: step)
        }
        .font(.system(size: 12, weight: .semibold))
        .opacity(isDisabled ? 0.55 : 1)
        .disabled(isDisabled)
    }
}

private enum RepeatableDurationOption: String, CaseIterable, Identifiable {
    case short
    case medium
    case long
    case custom

    var id: String { rawValue }

    static func options(for kind: RepeatableCaptureKind) -> [RepeatableDurationOption] {
        kind == .video ? [.short, .medium, .custom] : allCases
    }

    func duration(for kind: RepeatableCaptureKind) -> TimeInterval? {
        switch (kind, self) {
        case (.video, .short): 30
        case (.video, .medium): 60
        case (.timelapse, .short): 5 * 60
        case (.timelapse, .medium): 10 * 60
        case (.timelapse, .long): 30 * 60
        case (_, .custom), (.video, .long), (.photo, _): nil
        }
    }

    func title(for kind: RepeatableCaptureKind) -> String {
        switch (kind, self) {
        case (.video, .short): "30s"
        case (.video, .medium): "1m"
        case (.timelapse, .short): "5m"
        case (.timelapse, .medium): "10m"
        case (.timelapse, .long): "30m"
        case (_, .custom): "Custom"
        default: "—"
        }
    }
}

private struct RepeatablePlanningInput: Hashable {
    let kind: RepeatableCaptureKind
    let duration: TimeInterval
    let interval: TimeInterval
    let format: CaptureSourceFormat
    let fps: Int
}

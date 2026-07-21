@preconcurrency import AVFoundation
import CameraeCore
import CoreLocation
import CoreMotion
import ImageIO
import UIKit

enum CameraeLocationAuthorizationAction: Equatable, Sendable {
    case requestWhenInUse
    case startUpdates
    case unavailable
}

enum CameraeLocationAuthorizationPolicy {
    static func action(for status: CLAuthorizationStatus) -> CameraeLocationAuthorizationAction {
        switch status {
        case .notDetermined:
            .requestWhenInUse
        case .authorizedAlways, .authorizedWhenInUse:
            .startUpdates
        case .denied, .restricted:
            .unavailable
        @unknown default:
            .unavailable
        }
    }
}

@MainActor
final class CameraController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, CLLocationManagerDelegate {
    nonisolated(unsafe) let session = AVCaptureSession()

    @Published private(set) var status = "Preparando camera"
    @Published private(set) var isTimelapseRunning = false
    @Published private(set) var isSinglePhotoCaptureRunning = false
    @Published private(set) var isVideoRecording = false
    @Published private(set) var videoRecordingStartedAt: Date?
    @Published private(set) var timelapseStartedAt: Date?
    @Published private(set) var frameCount = 0
    @Published private(set) var astroCompositeFrameCount = 0
    @Published private(set) var baseExposureLabel = "-"
    @Published private(set) var stackProgressLabel = "-"
    @Published private(set) var lastCapturedExposureLabel = "-"
    @Published private(set) var countdownLabel = "-"
    @Published private(set) var astroBatchProgressLabel = "-"
    @Published private(set) var astroExposurePhaseLabel = "-"
    @Published private(set) var astroStackingStartFrame: Int?
    @Published private(set) var astroPreviewURL: URL?
    @Published private(set) var currentMotion: MotionAttitude?
    @Published private(set) var currentGeoPose: GeoPose?
    @Published private(set) var visualAlignment: VisualAlignmentEstimate?
    @Published private(set) var currentSession: TimelapseSession?
    @Published private(set) var completedSession: TimelapseSession?
    @Published private(set) var lastExportURL: URL?
    @Published private(set) var lastExportURLs: [URL] = []
    @Published private(set) var originalFrameExportProgress: OriginalFrameExportProgress?
    @Published private(set) var availableRepeatableLenses = RepeatableCameraLens.availableBackLenses()
    @Published private(set) var selectedRepeatableLens = RepeatableCameraLens.wide
    @Published private(set) var selectedCameraZoomFactor = 1.0
    @Published private(set) var supportedSourceFormats: Set<CaptureSourceFormat> = [.jpeg]
    @Published private(set) var lifecycleState = CameraeCaptureLifecycleState.idle

    private let captureMode: CameraCaptureMode
    private let captureQueue = DispatchQueue(label: "camerae.capture.queue")
    private let visualAlignmentQueue = DispatchQueue(label: "camerae.visual-alignment.queue")
    nonisolated(unsafe) private let visualAlignmentEvaluator: any VisualAlignmentEvaluating = AppleVisionAlignmentEvaluator()
    private let cameraeVisionCoordinator = CameraeVisionCaptureCoordinator(
        configuration: CameraeVisionFeatureConfiguration.current(),
        backendFactory: { reference, orientation in
            try CameraeVisionOpenCVBackend(reference: reference, orientation: orientation)
        }
    )
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    nonisolated(unsafe) private let photoOutput = AVCapturePhotoOutput()
    nonisolated(unsafe) private let movieOutput = AVCaptureMovieFileOutput()
    nonisolated(unsafe) private let videoDataOutput = AVCaptureVideoDataOutput()
    nonisolated(unsafe) private let store: TimelapseSessionStore
    private let storageProvider: VolumeStorageCapacityProvider
    nonisolated(unsafe) private var device: AVCaptureDevice?
    nonisolated(unsafe) private var exposureBias: Float = 0
    nonisolated(unsafe) private var astroExposureStrategy = AstroExposureStrategy.automatic(maxDuration: 1.0)
    private var timelapseTask: Task<Void, Never>?
    private var videoStopTask: Task<Void, Never>?
    private var latestLocation: CLLocation?
    private var latestHeading: CLHeading?
    private var bestFineGeoPose: GeoPose?
    private var didRequestTemporaryFullAccuracy = false
    private var pendingReferenceOrientation: CaptureDisplayOrientation?
    nonisolated(unsafe) private var referenceCGImage: CGImage?
    nonisolated(unsafe) private var lastVisualAlignmentAnalysis = Date.distantPast
    nonisolated(unsafe) private var isAnalyzingVisualAlignment = false
    nonisolated(unsafe) private var isVisualFineAdjustmentActive = false
    nonisolated(unsafe) private var isSequenceFocusLocked = false
    nonisolated(unsafe) private var configured = false
    nonisolated(unsafe) private var isConfiguring = false
    nonisolated(unsafe) private var selectedSourceFormat = CaptureSourceFormat.heic
    nonisolated(unsafe) private var requestedInitialZoomFactor = 1.0
    private var captureStorageGuard: CaptureStorageGuard?
    private var stoppedForStorage = false
    private var lifecycleGeneration: UInt64 = 0

    init(
        project: CameraProject,
        captureMode: CameraCaptureMode = .astro,
        initialRepeatableLens: RepeatableCameraLens? = nil,
        initialCameraZoomFactor: Double = 1
    ) {
        self.captureMode = captureMode
        store = TimelapseSessionStore(project: project)
        storageProvider = VolumeStorageCapacityProvider(rootURL: project.directoryURL)
        super.init()
        if let initialRepeatableLens,
           availableRepeatableLenses.contains(initialRepeatableLens) {
            selectedRepeatableLens = initialRepeatableLens
        }
        if !availableRepeatableLenses.contains(selectedRepeatableLens),
           let firstAvailableLens = availableRepeatableLenses.first {
            selectedRepeatableLens = firstAvailableLens
        }
        selectedCameraZoomFactor = max(initialCameraZoomFactor, 1)
        requestedInitialZoomFactor = selectedCameraZoomFactor
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.headingFilter = 1
        locationManager.pausesLocationUpdatesAutomatically = false
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCameraeVisionThermalStateChange),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCaptureSessionDidStartRunning(_:)),
            name: .AVCaptureSessionDidStartRunning,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCaptureSessionDidStopRunning(_:)),
            name: .AVCaptureSessionDidStopRunning,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCaptureSessionWasInterrupted(_:)),
            name: .AVCaptureSessionWasInterrupted,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCaptureSessionInterruptionEnded(_:)),
            name: .AVCaptureSessionInterruptionEnded,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCaptureSessionRuntimeError(_:)),
            name: .AVCaptureSessionRuntimeError,
            object: session
        )
        CameraeCaptureDiagnostics.event("C00 controller.init", "mode=\(captureMode)")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCameraeVisionPowerStateChange),
            name: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCameraeVisionDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCameraeVisionDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCameraeVisionMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc nonisolated private func handleCameraeVisionThermalStateChange(_ notification: Notification) {
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical:
            cameraeVisionCoordinator.pause(.thermal)
        case .fair:
            cameraeVisionCoordinator.updateCadence(.conservative)
            cameraeVisionCoordinator.resume(.thermal)
        case .nominal:
            cameraeVisionCoordinator.updateCadence(
                ProcessInfo.processInfo.isLowPowerModeEnabled ? .conservative : .balanced
            )
            cameraeVisionCoordinator.resume(.thermal)
        @unknown default:
            cameraeVisionCoordinator.pause(.thermal)
        }
    }

    @objc nonisolated private func handleCameraeVisionPowerStateChange(_ notification: Notification) {
        cameraeVisionCoordinator.updateCadence(
            ProcessInfo.processInfo.isLowPowerModeEnabled ? .conservative : .balanced
        )
    }

    @objc nonisolated private func handleCameraeVisionDidEnterBackground(_ notification: Notification) {
        cameraeVisionCoordinator.pause(.lifecycle)
    }

    @objc nonisolated private func handleCameraeVisionDidBecomeActive(_ notification: Notification) {
        cameraeVisionCoordinator.resume(.lifecycle)
    }

    @objc nonisolated private func handleCameraeVisionMemoryWarning(_ notification: Notification) {
        CameraeCaptureDiagnostics.error("C90 memory.warning", "OpenCV scheduling paused")
        cameraeVisionCoordinator.pause(.memoryPressure)
    }

    @objc nonisolated private func handleCaptureSessionDidStartRunning(_ notification: Notification) {
        CameraeCaptureDiagnostics.event("C15 avfoundation.didStartRunning")
    }

    @objc nonisolated private func handleCaptureSessionDidStopRunning(_ notification: Notification) {
        CameraeCaptureDiagnostics.event("C81 avfoundation.didStopRunning")
    }

    @objc nonisolated private func handleCaptureSessionWasInterrupted(_ notification: Notification) {
        let rawReason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber
        CameraeCaptureDiagnostics.error(
            "C91 avfoundation.interrupted",
            "reason=\(rawReason?.intValue.description ?? "unknown")"
        )
        Task { @MainActor in
            self.status = "Câmera interrompida pelo sistema"
        }
    }

    @objc nonisolated private func handleCaptureSessionInterruptionEnded(_ notification: Notification) {
        CameraeCaptureDiagnostics.event("C16 avfoundation.interruptionEnded")
    }

    @objc nonisolated private func handleCaptureSessionRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
        let detail = error.map { "domain=\($0.domain) code=\($0.code) message=\($0.localizedDescription)" }
            ?? "unknown runtime error"
        CameraeCaptureDiagnostics.error("C92 avfoundation.runtimeError", detail)
        Task { @MainActor in
            self.status = "Erro da câmera: \(error?.localizedDescription ?? "desconhecido")"
            self.lifecycleState = .failed(error?.localizedDescription ?? "Erro interno do AVFoundation")
        }
    }

    func start() async {
        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        lifecycleState = .preparing
        CameraeCaptureDiagnostics.event("C01 controller.start", "generation=\(generation)")
        CameraeCaptureDiagnostics.event(
            "C02 permission.request",
            "current=\(AVCaptureDevice.authorizationStatus(for: .video).rawValue)"
        )
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        CameraeCaptureDiagnostics.event("C03 permission.result", "allowed=\(allowed)")
        guard generation == lifecycleGeneration else { return }
        guard allowed else {
            status = "Permissao da camera negada"
            lifecycleState = .unauthorized
            CameraeCaptureDiagnostics.error("C03 permission.denied", "authorization rejected")
            return
        }

        do {
            CameraeCaptureDiagnostics.event("C04 configure.await.begin")
            try await configureIfNeeded()
            CameraeCaptureDiagnostics.event("C17 configure.await.end")
            guard generation == lifecycleGeneration else { return }
            supportedSourceFormats = photoOutput.availablePhotoCodecTypes.contains(.hevc)
                ? [.heic, .jpeg]
                : [.jpeg]
            startMotionUpdates()
            startLocationUpdates()
            status = "Camera principal pronta"
            lifecycleState = .running
            cameraeVisionCoordinator.resume(.lifecycle)
            CameraeCaptureDiagnostics.event(
                "C18 controller.ready",
                "running=\(session.isRunning) inputs=\(session.inputs.count) outputs=\(session.outputs.count)"
            )
        } catch {
            status = "Erro: \(error.localizedDescription)"
            lifecycleState = .failed(error.localizedDescription)
            CameraeCaptureDiagnostics.error("C93 controller.start.failed", error.localizedDescription)
        }
    }

    func stop() {
        lifecycleGeneration &+= 1
        lifecycleState = .stopped
        timelapseTask?.cancel()
        videoStopTask?.cancel()
        motionManager.stopDeviceMotionUpdates()
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        cameraeVisionCoordinator.pause(.lifecycle)
        CameraeCaptureDiagnostics.event("C80 controller.stop.requested")

        captureQueue.async { [session] in
            if session.isRunning {
                CameraeCaptureDiagnostics.event("C80 controller.stopRunning.begin")
                session.stopRunning()
                CameraeCaptureDiagnostics.event("C82 controller.stopRunning.end")
            }
        }
    }

    func toggleTimelapse(interval: Double, plan: CapturePlan) async {
        if isTimelapseRunning {
            stopTimelapse()
        } else {
            await startTimelapse(interval: interval, plan: plan)
        }
    }

    func toggleAstroBatchCapture(
        timelapseInterval: Double,
        astroInterval: Double,
        batchSize: Int,
        usesAutomaticExposure: Bool,
        plan: CapturePlan
    ) async {
        if isTimelapseRunning {
            stopTimelapse()
        } else {
            await startAstroBatchCapture(
                timelapseInterval: timelapseInterval,
                astroInterval: astroInterval,
                batchSize: batchSize,
                usesAutomaticExposure: usesAutomaticExposure,
                plan: plan
            )
        }
    }

    func captureSinglePhoto() async {
        guard !isTimelapseRunning, !isSinglePhotoCaptureRunning else { return }
        isSinglePhotoCaptureRunning = true
        defer { isSinglePhotoCaptureRunning = false }

        do {
            currentSession = try store.createSession(
                captureKind: .photo,
                cameraLens: selectedRepeatableLens,
                cameraZoomFactor: selectedCameraZoomFactor
            )
            completedSession = nil
            frameCount = 0
            astroCompositeFrameCount = 0
            astroBatchProgressLabel = "-"
            astroExposurePhaseLabel = "-"
            astroStackingStartFrame = nil
            astroPreviewURL = nil
            lastExportURL = nil
            lastExportURLs = []
            status = "Estabilizando tripe"

            for second in stride(from: 3, through: 1, by: -1) {
                countdownLabel = "\(second)s"
                status = "Foto em \(second)s"
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }

            countdownLabel = "-"
            try await captureAndSaveFrame()
            completedSession = currentSession
            status = "Foto salva"
        } catch {
            countdownLabel = "-"
            status = "Foto falhou: \(error.localizedDescription)"
        }
    }

    func toggleVideoRecording(plan: CapturePlan) async {
        if isVideoRecording {
            stopVideoRecording()
        } else {
            await startVideoRecording(plan: plan)
        }
    }

    func setPendingReferenceOrientation(_ orientation: CaptureDisplayOrientation) {
        pendingReferenceOrientation = orientation
    }

    func setCaptureSourceFormat(_ format: CaptureSourceFormat) {
        selectedSourceFormat = format
    }

    func configureCapturePreflight(_ preflight: CapturePreflightResult) {
        let required = preflight.storage.requiredBytes ?? 0
        let completionReserve = required > preflight.estimate.captureBytes
            ? required - preflight.estimate.captureBytes
            : 2 * 1_024 * 1_024 * 1_024
        let frameCount = max(preflight.estimate.expectedFrameCount, 1)
        let bytesPerFrame = max(preflight.estimate.captureBytes / frameCount, 1)
        captureStorageGuard = CaptureStorageGuard(
            completionReserveBytes: completionReserve,
            bytesPerFrameUpperBound: bytesPerFrame
        )
    }

    func setExposureBias(_ bias: Double) async {
        let clampedBias = Float(min(max(bias, -3), 3))
        exposureBias = clampedBias

        await withCheckedContinuation { continuation in
            captureQueue.async {
                guard let device = self.device else {
                    continuation.resume()
                    return
                }

                do {
                    try self.applyRepeatableAutoConfiguration(device: device)
                    Task { @MainActor in
                        self.baseExposureLabel = Self.formatEV(Double(clampedBias))
                    }
                } catch {
                    Task { @MainActor in
                        self.status = "EV falhou: \(error.localizedDescription)"
                    }
                }

                continuation.resume()
            }
        }
    }

    func selectRepeatableLens(_ lens: RepeatableCameraLens) async {
        guard captureMode == .repeatable,
              availableRepeatableLenses.contains(lens),
              !isTimelapseRunning,
              !isSinglePhotoCaptureRunning,
              !isVideoRecording,
              lens != selectedRepeatableLens else {
            return
        }
        cameraeVisionCoordinator.pause(.lensChange)
        cameraeVisionCoordinator.invalidateResults()
        defer { cameraeVisionCoordinator.resume(.lensChange) }

        do {
            try await configureIfNeeded()
            try await withCheckedThrowingContinuation { continuation in
                captureQueue.async {
                    do {
                        guard let newDevice = AVCaptureDevice.default(
                            lens.deviceType,
                            for: .video,
                            position: .back
                        ) else {
                            throw CameraError.noCamera
                        }

                        let newInput = try AVCaptureDeviceInput(device: newDevice)
                        let previousInput = self.session.inputs
                            .compactMap { $0 as? AVCaptureDeviceInput }
                            .first { $0.device.hasMediaType(.video) }

                        self.session.beginConfiguration()
                        if let previousInput {
                            self.session.removeInput(previousInput)
                        }

                        guard self.session.canAddInput(newInput) else {
                            if let previousInput, self.session.canAddInput(previousInput) {
                                self.session.addInput(previousInput)
                            }
                            self.session.commitConfiguration()
                            throw CameraError.configurationFailed
                        }

                        self.session.addInput(newInput)
                        self.session.commitConfiguration()
                        try Self.applyZoom(1, to: newDevice)
                        self.device = newDevice
                        _ = try self.prepareCapture(device: newDevice)
                        continuation.resume(returning: ())
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            selectedRepeatableLens = lens
            selectedCameraZoomFactor = 1
            status = "Camera \(lens.shortTitle) selecionada"
        } catch {
            status = "Camera falhou: \(error.localizedDescription)"
        }
    }

    func setVisualReference(_ url: URL?) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            visualAlignmentQueue.async {
                guard let url,
                      let image = UIImage(contentsOfFile: url.path),
                      let cgImage = image.normalizedReferenceCGImage() else {
                    self.referenceCGImage = nil
                    self.cameraeVisionCoordinator.updateReference(nil, orientation: .up)
                    Task { @MainActor in
                        self.visualAlignment = nil
                    }
                    continuation.resume()
                    return
                }

                self.referenceCGImage = cgImage
                if self.cameraeVisionCoordinator.isEnabled,
                   let referenceBuffer = try? CameraeVisionPixelBufferFactory.makeBGRA(from: cgImage) {
                    self.cameraeVisionCoordinator.updateReference(referenceBuffer, orientation: .up)
                } else if self.cameraeVisionCoordinator.isEnabled {
                    self.cameraeVisionCoordinator.updateReference(nil, orientation: .up)
                }
                self.lastVisualAlignmentAnalysis = .distantPast
                Task { @MainActor in
                    self.visualAlignment = nil
                }
                continuation.resume()
            }
        }
    }

    func exportLastSession() async {
        guard let currentSession else {
            status = "Nenhuma sessao para exportar"
            return
        }

        do {
            status = "Gerando ZIP de originais"
            originalFrameExportProgress = nil
            lastExportURLs = try await store.exportOriginalFramesArchivesInBackground(for: currentSession) { [weak self] progress in
                await self?.updateOriginalFrameExportProgress(progress)
            }
            lastExportURL = lastExportURLs.first
            status = lastExportURLs.count == 1
                ? "ZIP de originais pronto"
                : "ZIP de originais pronto (\(lastExportURLs.count) partes)"
            originalFrameExportProgress = nil
        } catch is CancellationError {
            lastExportURLs = TimelapseSessionStore.existingOriginalFrameArchives(for: currentSession)
            lastExportURL = lastExportURLs.first
            status = lastExportURLs.isEmpty
                ? "Export cancelado"
                : "Export cancelado (\(lastExportURLs.count) lotes prontos)"
            originalFrameExportProgress = nil
        } catch {
            lastExportURLs = []
            lastExportURL = nil
            status = "Falha no ZIP: \(error.localizedDescription)"
            originalFrameExportProgress = nil
        }
    }

    private func updateOriginalFrameExportProgress(_ progress: OriginalFrameExportProgress) {
        originalFrameExportProgress = progress
        status = progress.detailText
    }

    private func startTimelapse(interval: Double, plan: CapturePlan) async {
        do {
            stoppedForStorage = false
            currentSession = try store.createSession(
                captureKind: .timelapse,
                cameraLens: selectedRepeatableLens,
                cameraZoomFactor: selectedCameraZoomFactor
            )
            if let currentSession {
                try store.saveCapturePlan(plan, in: currentSession)
            }
            completedSession = nil
            frameCount = 0
            astroCompositeFrameCount = 0
            astroBatchProgressLabel = "-"
            astroExposurePhaseLabel = "-"
            astroStackingStartFrame = nil
            astroPreviewURL = nil
            lastExportURL = nil
            lastExportURLs = []
            isTimelapseRunning = true
            status = "Estabilizando tripe"

            timelapseTask = Task { [weak self] in
                guard let self else { return }
                await self.runTimelapseWithCountdown(
                    interval: interval,
                    plannedDuration: plan.plannedDuration
                )
            }
        } catch {
            status = "Falha ao criar sessao: \(error.localizedDescription)"
        }
    }

    private func startAstroBatchCapture(
        timelapseInterval: Double,
        astroInterval: Double,
        batchSize: Int,
        usesAutomaticExposure: Bool,
        plan: CapturePlan
    ) async {
        guard case .astro = captureMode else {
            await startTimelapse(interval: timelapseInterval, plan: plan)
            return
        }

        do {
            stoppedForStorage = false
            astroExposureStrategy = usesAutomaticExposure ? .automatic(maxDuration: 1.0) : .fixed(duration: 1.0)
            currentSession = try store.createSession(
                captureKind: .timelapse,
                cameraLens: selectedRepeatableLens,
                cameraZoomFactor: selectedCameraZoomFactor
            )
            if let currentSession {
                try store.saveCapturePlan(plan, in: currentSession)
            }
            completedSession = nil
            frameCount = 0
            astroCompositeFrameCount = 0
            astroBatchProgressLabel = "0/\(Self.clampedAstroBatchSize(batchSize))"
            astroExposurePhaseLabel = usesAutomaticExposure ? "Auto" : "Astro"
            astroStackingStartFrame = nil
            astroPreviewURL = nil
            lastExportURL = nil
            lastExportURLs = []
            isTimelapseRunning = true
            status = "Estabilizando tripe"

            timelapseTask = Task { [weak self] in
                guard let self else { return }
                await self.runAstroBatchCaptureWithCountdown(
                    timelapseInterval: timelapseInterval,
                    astroInterval: astroInterval,
                    batchSize: batchSize,
                    waitsForAstroExposure: usesAutomaticExposure,
                    plannedDuration: plan.plannedDuration
                )
            }
        } catch {
            status = "Falha ao criar sessao: \(error.localizedDescription)"
        }
    }

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable, !motionManager.isDeviceMotionActive else {
            return
        }

        motionManager.deviceMotionUpdateInterval = 1.0 / 20.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let attitude = motion?.attitude else { return }
            self.currentMotion = MotionAttitude(
                x: attitude.pitch * 180 / .pi,
                y: attitude.roll * 180 / .pi,
                z: attitude.yaw * 180 / .pi
            )
        }
    }

    private func startLocationUpdates() {
        switch CameraeLocationAuthorizationPolicy.action(for: locationManager.authorizationStatus) {
        case .requestWhenInUse:
            CameraeCaptureDiagnostics.event("L01 location.authorization.requested")
            locationManager.requestWhenInUseAuthorization()
        case .startUpdates:
            if locationManager.accuracyAuthorization == .reducedAccuracy,
               !didRequestTemporaryFullAccuracy {
                didRequestTemporaryFullAccuracy = true
                CameraeCaptureDiagnostics.event("L02 location.fullAccuracy.requested")
                locationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "RepeatableAlignment")
            }
            locationManager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                locationManager.startUpdatingHeading()
            }
            CameraeCaptureDiagnostics.event(
                "L03 location.updates.started",
                "accuracy=\(locationManager.accuracyAuthorization.rawValue)"
            )
        case .unavailable:
            CameraeCaptureDiagnostics.event("L04 location.unavailable")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.startLocationUpdates()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last,
              location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 30 else {
            return
        }

        Task { @MainActor in
            self.latestLocation = location
            self.publishCurrentGeoPose()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            self.latestHeading = newHeading
            self.publishCurrentGeoPose()
        }
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard output === videoDataOutput else { return }
        analyzeVisualAlignmentIfNeeded(sampleBuffer: sampleBuffer)
    }

    nonisolated private func analyzeVisualAlignmentIfNeeded(sampleBuffer: CMSampleBuffer) {
        if cameraeVisionCoordinator.isEnabled,
           let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            cameraeVisionCoordinator.submit(
                pixelBuffer,
                orientation: .right,
                at: ProcessInfo.processInfo.systemUptime
            )
        }
        guard let referenceCGImage,
              !isAnalyzingVisualAlignment,
              Date().timeIntervalSince(lastVisualAlignmentAnalysis) >= visualAlignmentAnalysisInterval else {
            return
        }

        lastVisualAlignmentAnalysis = Date()
        isAnalyzingVisualAlignment = true

        do {
            let estimate = try visualAlignmentEvaluator.evaluate(
                sampleBuffer: sampleBuffer,
                referenceImage: referenceCGImage,
                orientation: .right
            )
            isVisualFineAdjustmentActive = estimate?.isFineAdjustment == true
            Task { @MainActor in
                self.visualAlignment = estimate
            }
        } catch {
            isVisualFineAdjustmentActive = false
            Task { @MainActor in
                self.visualAlignment = VisualAlignmentEstimate(
                    scale: 1,
                    confidence: 0,
                    horizontalOffset: 0,
                    verticalOffset: 0
                )
            }
        }

        isAnalyzingVisualAlignment = false
    }

    nonisolated private var visualAlignmentAnalysisInterval: TimeInterval {
        isVisualFineAdjustmentActive ? 0.16 : 0.28
    }

    private func publishCurrentGeoPose() {
        guard locationManager.accuracyAuthorization == .fullAccuracy,
              let latestLocation else {
            currentGeoPose = nil
            return
        }

        let heading: Double?
        if let latestHeading {
            if latestHeading.trueHeading >= 0 {
                heading = latestHeading.trueHeading
            } else if latestHeading.magneticHeading >= 0 {
                heading = latestHeading.magneticHeading
            } else {
                heading = nil
            }
        } else {
            heading = nil
        }

        let geoPose = GeoPose(
            latitude: latestLocation.coordinate.latitude,
            longitude: latestLocation.coordinate.longitude,
            horizontalAccuracy: latestLocation.horizontalAccuracy,
            heading: heading,
            timestamp: latestLocation.timestamp
        )
        currentGeoPose = geoPose
        updateBestFineGeoPose(with: geoPose)
    }

    private func updateBestFineGeoPose(with geoPose: GeoPose) {
        guard let bestFineGeoPose else {
            self.bestFineGeoPose = geoPose
            return
        }

        let age = geoPose.timestamp.timeIntervalSince(bestFineGeoPose.timestamp)
        let distance = geoPose.distanceMeters(from: bestFineGeoPose)
        let movedBeyondAccuracy = distance > max(geoPose.horizontalAccuracy, bestFineGeoPose.horizontalAccuracy)

        if movedBeyondAccuracy || age > 20 || geoPose.horizontalAccuracy < bestFineGeoPose.horizontalAccuracy {
            self.bestFineGeoPose = geoPose
        }
    }

    private func stopTimelapse() {
        timelapseTask?.cancel()
        timelapseTask = nil
        isTimelapseRunning = false
        timelapseStartedAt = nil
        unlockFocusAfterCaptureSequence()
        countdownLabel = "-"
        astroBatchProgressLabel = "-"
        astroExposurePhaseLabel = "-"
        if frameCount > 0 || astroCompositeFrameCount > 0 {
            completedSession = currentSession
            status = "Timelapse concluido"
        } else {
            status = "Timelapse parado"
        }
    }

    private func runTimelapseWithCountdown(
        interval: Double,
        plannedDuration: TimeInterval
    ) async {
        for second in stride(from: 3, through: 1, by: -1) {
            guard !Task.isCancelled else { return }
            countdownLabel = "\(second)s"
            status = "Comecando em \(second)s"
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        guard !Task.isCancelled else { return }
        countdownLabel = "-"
        timelapseStartedAt = Date()
        await lockFocusForCaptureSequence()
        guard !Task.isCancelled else { return }
        status = "Capturando timelapse"
        await runTimelapse(interval: interval, plannedDuration: plannedDuration)
        if !Task.isCancelled {
            finishPlannedTimelapse()
        }
    }

    private func runAstroBatchCaptureWithCountdown(
        timelapseInterval: Double,
        astroInterval: Double,
        batchSize: Int,
        waitsForAstroExposure: Bool,
        plannedDuration: TimeInterval
    ) async {
        for second in stride(from: 3, through: 1, by: -1) {
            guard !Task.isCancelled else { return }
            countdownLabel = "\(second)s"
            status = "Comecando em \(second)s"
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        guard !Task.isCancelled else { return }
        countdownLabel = "-"
        await lockFocusForCaptureSequence()
        guard !Task.isCancelled else { return }
        status = waitsForAstroExposure ? "Capturando por do sol" : "Capturando lote astro"
        await runAstroBatchCapture(
            timelapseInterval: timelapseInterval,
            astroInterval: astroInterval,
            batchSize: batchSize,
            waitsForAstroExposure: waitsForAstroExposure,
            plannedDuration: plannedDuration
        )
        if !Task.isCancelled {
            finishPlannedTimelapse()
        }
    }

    private func runTimelapse(interval: Double, plannedDuration: TimeInterval) async {
        let clampedInterval = min(max(interval, 2), 10)
        let intervalNanos = UInt64(clampedInterval * 1_000_000_000)

        let runBudget = CaptureRunBudget(
            startedAt: Date(),
            plannedDuration: max(plannedDuration, 1)
        )

        while !Task.isCancelled && !runBudget.hasReachedLimit(at: Date()) {
            do {
                try await captureAndSaveFrame()
                if await shouldStopForStorage() { break }
            } catch {
                status = "Frame falhou: \(error.localizedDescription)"
            }

            if !Task.isCancelled {
                status = "Aguardando \(Self.formatInterval(clampedInterval))"
                try? await Task.sleep(nanoseconds: intervalNanos)
            }
        }
    }

    private func runAstroBatchCapture(
        timelapseInterval: Double,
        astroInterval: Double,
        batchSize: Int,
        waitsForAstroExposure: Bool,
        plannedDuration: TimeInterval
    ) async {
        let clampedTimelapseInterval = min(max(timelapseInterval, 2), 120)
        let clampedAstroInterval = min(max(astroInterval, 1), 10)
        let size = Self.clampedAstroBatchSize(batchSize)
        var currentBatch: [URL] = []
        currentBatch.reserveCapacity(size)
        var isStackingActive = !waitsForAstroExposure
        let runBudget = CaptureRunBudget(
            startedAt: Date(),
            plannedDuration: max(plannedDuration, 1)
        )

        while !Task.isCancelled && !runBudget.hasReachedLimit(at: Date()) {
            let captureStartedAt = Date()
            do {
                let savedFrame = try await captureAndSaveFrame()
                if await shouldStopForStorage() { break }
                if !isStackingActive {
                    if savedFrame.exposureSeconds >= Self.astroStackingExposureThreshold {
                        isStackingActive = true
                        astroStackingStartFrame = savedFrame.index
                        astroExposurePhaseLabel = "Astro"
                        if let currentSession {
                            try store.saveAstroStackingStartFrame(savedFrame.index, in: currentSession)
                        }
                        status = "Inicio astro no frame \(savedFrame.index)"
                    } else {
                        astroExposurePhaseLabel = "Auto"
                        astroBatchProgressLabel = "aguardando"
                        stackProgressLabel = "Auto"
                    }
                }

                if isStackingActive {
                    if astroStackingStartFrame == nil {
                        astroStackingStartFrame = savedFrame.index
                        if let currentSession {
                            try store.saveAstroStackingStartFrame(savedFrame.index, in: currentSession)
                        }
                    }

                    currentBatch.append(savedFrame.url)
                    astroBatchProgressLabel = "\(currentBatch.count)/\(size)"
                    stackProgressLabel = "Lote \(currentBatch.count)/\(size)"
                }

                if currentBatch.count >= size {
                    status = "Processando frame astro"
                    let outputURL = try await processAstroBatch(
                        currentBatch,
                        batchIndex: astroCompositeFrameCount + 1
                    )
                    astroCompositeFrameCount += 1
                    astroPreviewURL = outputURL
                    currentBatch.removeAll(keepingCapacity: true)
                    astroBatchProgressLabel = "0/\(size)"
                    stackProgressLabel = "Stack \(astroCompositeFrameCount)"
                    status = "Preview astro atualizado"
                }
            } catch {
                status = "Frame falhou: \(error.localizedDescription)"
            }

            if !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(captureStartedAt)
                let nextInterval = isStackingActive ? clampedAstroInterval : clampedTimelapseInterval
                let remaining = nextInterval - elapsed
                if remaining > 0 {
                    status = "Aguardando \(Self.formatInterval(remaining))"
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                } else {
                    status = currentBatch.isEmpty ? "Capturando proximo lote" : "Capturando lote astro"
                }
            }
        }
    }

    private func finishPlannedTimelapse() {
        timelapseTask = nil
        isTimelapseRunning = false
        timelapseStartedAt = nil
        unlockFocusAfterCaptureSequence()
        countdownLabel = "-"
        astroBatchProgressLabel = "-"
        astroExposurePhaseLabel = "-"
        if frameCount > 0 || astroCompositeFrameCount > 0 {
            completedSession = currentSession
            status = stoppedForStorage
                ? "Captura encerrada com segurança: espaço insuficiente"
                : "Plano de captura concluído"
        } else {
            status = "Plano encerrado sem frames"
        }
    }

    private func shouldStopForStorage() async -> Bool {
        guard let captureStorageGuard else { return false }
        let snapshot = await storageProvider.snapshot()
        let result = captureStorageGuard.evaluate(
            availableBytes: snapshot.availableForImportantUsage
        )
        switch result.decision {
        case .healthy:
            return false
        case .warning:
            status = result.reason == .capacityUnavailable
                ? "Não foi possível confirmar o espaço livre"
                : "Espaço de armazenamento ficando baixo"
            return false
        case .stop:
            stoppedForStorage = true
            status = "Captura encerrada com segurança: espaço insuficiente"
            return true
        }
    }

    private func startVideoRecording(plan: CapturePlan) async {
        guard !isTimelapseRunning, !isSinglePhotoCaptureRunning, !isVideoRecording else { return }

        do {
            stoppedForStorage = false
            try await configureIfNeeded()
            guard movieOutput.isRecording == false else { return }

            let videoSession = try store.createSession(
                captureKind: .video,
                cameraLens: selectedRepeatableLens,
                cameraZoomFactor: selectedCameraZoomFactor
            )
            try store.saveCapturePlan(plan, in: videoSession)
            let sessionWithMotion = try saveReferencePoseIfAvailable(for: videoSession)
            let outputURL = store.videoClipURL(for: videoSession)
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }

            applyOutputRotation(for: sessionWithMotion.referenceOrientation)
            currentSession = sessionWithMotion
            completedSession = nil
            frameCount = 0
            lastExportURL = nil
            lastExportURLs = []
            isVideoRecording = true
            cameraeVisionCoordinator.pause(.videoRecording)
            videoRecordingStartedAt = Date()
            status = "Gravando video"

            let delegate = MovieRecordingDelegate { [weak self] result in
                Task { @MainActor in
                    await self?.finishVideoRecording(result: result)
                }
            }
            MovieRecordingDelegateRetainer.shared.retain(delegate)
            movieOutput.startRecording(to: outputURL, recordingDelegate: delegate)
            videoStopTask?.cancel()
            videoStopTask = Task { [weak self] in
                let budget = CaptureRunBudget(
                    startedAt: Date(),
                    plannedDuration: max(plan.plannedDuration, 1)
                )
                while !Task.isCancelled && !budget.hasReachedLimit(at: Date()) {
                    let wait = min(5, budget.remainingDuration(at: Date()))
                    try? await Task.sleep(
                        nanoseconds: UInt64(max(wait, 0.1) * 1_000_000_000)
                    )
                    guard !Task.isCancelled else { return }
                    if await self?.shouldStopForStorage() == true {
                        self?.stopVideoRecording()
                        return
                    }
                }
                if !Task.isCancelled { self?.stopVideoRecording() }
            }
        } catch {
            isVideoRecording = false
            cameraeVisionCoordinator.resume(.videoRecording)
            status = "Video falhou: \(error.localizedDescription)"
        }
    }

    private func stopVideoRecording() {
        guard isVideoRecording else { return }
        videoStopTask?.cancel()
        videoStopTask = nil
        status = "Finalizando video"
        movieOutput.stopRecording()
    }

    private func finishVideoRecording(result: Result<URL, Error>) async {
        videoStopTask?.cancel()
        videoStopTask = nil
        isVideoRecording = false
        cameraeVisionCoordinator.resume(.videoRecording)
        videoRecordingStartedAt = nil

        do {
            let outputURL = try result.get()
            guard let currentSession else { throw CameraError.missingSession }
            try saveFirstVideoFrame(from: outputURL, in: currentSession)
            frameCount = store.frameCount(in: currentSession)
            completedSession = currentSession
            status = stoppedForStorage
                ? "Vídeo encerrado com segurança: espaço insuficiente"
                : "Video salvo"
        } catch {
            status = "Video falhou: \(error.localizedDescription)"
        }
    }

    private func saveFirstVideoFrame(from videoURL: URL, in session: TimelapseSession) throws {
        let asset = AVAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
        guard let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.95) else {
            throw CameraError.photoEncodingFailed
        }

        _ = try store.saveFrame(data, in: session, index: 1)
    }

    @discardableResult
    private func captureAndSaveFrame() async throws -> SavedFrame {
        guard let currentSession else { throw CameraError.missingSession }
        applyOutputRotation(for: currentSession.referenceOrientation)
        let photo = try await captureOriginalPhoto()
        let frameIndex = frameCount + 1
        let savedURL = try store.saveFrame(
            photo.data,
            in: currentSession,
            index: frameIndex,
            format: photo.format
        )

        if frameCount == 0 {
            self.currentSession = try saveReferencePoseIfAvailable(for: currentSession)
        }

        frameCount += 1
        lastCapturedExposureLabel = photo.exposureLabel
        baseExposureLabel = Self.formatExposure(photo.exposureSeconds)
        stackProgressLabel = "Original"
        status = "Salvo \(savedURL.lastPathComponent)"
        return SavedFrame(index: frameIndex, url: savedURL, exposureSeconds: photo.exposureSeconds)
    }

    private func processAstroBatch(_ frameURLs: [URL], batchIndex: Int) async throws -> URL {
        guard let currentSession else { throw CameraError.missingSession }
        let data = try await Task.detached(priority: .userInitiated) {
            let stacker = ExposureStacker()
            return try autoreleasepool {
                try stacker.averageJPEGFiles(
                    frameURLs,
                    maxDimension: 1920,
                    profile: .natural
                )
            }
        }.value

        return try store.saveAstroStackFrame(data, in: currentSession, index: batchIndex)
    }

    private func applyOutputRotation(for orientation: CaptureDisplayOrientation?) {
        let angle = (orientation ?? pendingReferenceOrientation ?? Self.currentDisplayOrientation()).videoRotationAngle
        for output in [photoOutput, movieOutput, videoDataOutput] {
            guard let connection = output.connection(with: .video),
                  connection.isVideoRotationAngleSupported(angle) else {
                continue
            }
            connection.videoRotationAngle = angle
        }
    }

    private func saveReferencePoseIfAvailable(for session: TimelapseSession) throws -> TimelapseSession {
        var updatedSession = session

        if updatedSession.referenceMotion == nil, let currentMotion {
            updatedSession = try store.updateReferenceMotion(currentMotion, for: updatedSession)
        }

        if updatedSession.referenceGeoPose == nil, let geoPose = bestAvailableFineGeoPose() {
            updatedSession = try store.updateReferenceGeoPose(geoPose, for: updatedSession)
        }

        if updatedSession.referenceOrientation == nil {
            updatedSession = try store.updateReferenceOrientation(
                pendingReferenceOrientation ?? Self.currentDisplayOrientation(),
                for: updatedSession
            )
        }

        return updatedSession
    }

    private static func currentDisplayOrientation() -> CaptureDisplayOrientation {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let orientation = scenes.first { $0.activationState == .foregroundActive }?.interfaceOrientation ??
            scenes.first?.interfaceOrientation

        switch orientation {
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        case .portrait, .unknown, .none:
            return .portrait
        @unknown default:
            return .portrait
        }
    }

    private func bestAvailableFineGeoPose() -> GeoPose? {
        guard let bestFineGeoPose,
              abs(bestFineGeoPose.timestamp.timeIntervalSinceNow) < 120 else {
            return currentGeoPose
        }

        return bestFineGeoPose
    }

    private func configureIfNeeded() async throws {
        let preferredRepeatableLens = selectedRepeatableLens
        CameraeCaptureDiagnostics.event(
            "C05 configure.enqueue",
            "configured=\(configured) preferredLens=\(preferredRepeatableLens.rawValue)"
        )
        try await withCheckedThrowingContinuation { continuation in
            captureQueue.async {
                do {
                    CameraeCaptureDiagnostics.event(
                        "C06 configure.queue.enter",
                        "configured=\(self.configured) running=\(self.session.isRunning)"
                    )
                    guard !self.configured else {
                        if !self.session.isRunning {
                            CameraeCaptureDiagnostics.event("C14 session.restart.begin")
                            self.session.startRunning()
                            CameraeCaptureDiagnostics.event("C15 session.restart.end")
                        }
                        continuation.resume(returning: ())
                        return
                    }

                    self.isConfiguring = true
                    CameraeCaptureDiagnostics.event("C07 session.beginConfiguration")
                    self.session.beginConfiguration()

                    if self.session.canSetSessionPreset(.photo) {
                        self.session.sessionPreset = .photo
                    }
                    CameraeCaptureDiagnostics.event("C08 session.preset", "value=photo")

                    let deviceType = preferredRepeatableLens.deviceType
                    guard let device = AVCaptureDevice.default(deviceType, for: .video, position: .back) else {
                        throw CameraError.noCamera
                    }
                    CameraeCaptureDiagnostics.event(
                        "C09 device.selected",
                        "type=\(deviceType.rawValue) name=\(device.localizedName)"
                    )

                    let input = try AVCaptureDeviceInput(device: device)
                    CameraeCaptureDiagnostics.event(
                        "C10 capabilities",
                        "input=\(self.session.canAddInput(input)) photo=\(self.session.canAddOutput(self.photoOutput)) movie=\(self.session.canAddOutput(self.movieOutput)) videoData=\(self.session.canAddOutput(self.videoDataOutput))"
                    )
                    guard self.session.canAddInput(input), self.session.canAddOutput(self.photoOutput) else {
                        throw CameraError.configurationFailed
                    }

                    self.session.addInput(input)
                    self.session.addOutput(self.photoOutput)
                    if self.session.canAddOutput(self.movieOutput) {
                        self.session.addOutput(self.movieOutput)
                    }
                    if self.session.canAddOutput(self.videoDataOutput) {
                        self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
                        self.videoDataOutput.videoSettings = [
                            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                        ]
                        self.videoDataOutput.setSampleBufferDelegate(self, queue: self.visualAlignmentQueue)
                        self.session.addOutput(self.videoDataOutput)
                    }
                    self.photoOutput.maxPhotoQualityPrioritization = .speed
                    try self.applyInitialZoom(to: device)
                    self.device = device
                    self.configured = true

                    CameraeCaptureDiagnostics.event(
                        "C11 session.commitConfiguration",
                        "inputs=\(self.session.inputs.count) outputs=\(self.session.outputs.count)"
                    )
                    self.session.commitConfiguration()
                    self.isConfiguring = false
                    CameraeCaptureDiagnostics.event("C12 session.startRunning.begin")
                    self.session.startRunning()
                    CameraeCaptureDiagnostics.event("C13 session.startRunning.end", "running=\(self.session.isRunning)")

                    CameraeCaptureDiagnostics.event("C14 device.prepare.begin")
                    let baseExposure = try self.prepareCapture(device: device)
                    CameraeCaptureDiagnostics.event("C16 device.prepare.end", "exposure=\(baseExposure)")
                    Task { @MainActor in
                        switch self.captureMode {
                        case .astro:
                            self.baseExposureLabel = Self.formatExposure(baseExposure)
                        case .repeatable:
                            self.baseExposureLabel = Self.formatEV(Double(self.exposureBias))
                        }
                    }

                    continuation.resume(returning: ())
                } catch {
                    CameraeCaptureDiagnostics.error("C94 configure.queue.failed", error.localizedDescription)
                    if self.isConfiguring {
                        self.session.commitConfiguration()
                        self.isConfiguring = false
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    nonisolated private static func applyZoom(_ requestedFactor: Double, to device: AVCaptureDevice) throws {
        let minimum = max(Double(device.minAvailableVideoZoomFactor), 1)
        let maximum = max(Double(device.maxAvailableVideoZoomFactor), minimum)
        let applied = min(max(requestedFactor, minimum), maximum)
        try device.lockForConfiguration()
        device.videoZoomFactor = CGFloat(applied)
        device.unlockForConfiguration()
    }

    nonisolated private func applyInitialZoom(to device: AVCaptureDevice) throws {
        try Self.applyZoom(requestedInitialZoomFactor, to: device)
    }

    private func captureOriginalPhoto() async throws -> CapturedPhoto {
        try await withCheckedThrowingContinuation { continuation in
            captureQueue.async {
                do {
                    guard let device = self.device else { throw CameraError.noCamera }
                    let baseExposure = try self.prepareCapture(device: device)

                    if Task.isCancelled {
                        throw CameraError.cancelled
                    }

                    Task { @MainActor in
                        self.status = "Capturando frame"
                        self.stackProgressLabel = "Original"
                        switch self.captureMode {
                        case .astro:
                            self.baseExposureLabel = Self.formatExposure(baseExposure)
                        case .repeatable:
                            self.baseExposureLabel = Self.formatEV(Double(self.exposureBias))
                        }
                    }

                    continuation.resume(returning: try self.captureManualPhoto())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    nonisolated private func captureManualPhoto() throws -> CapturedPhoto {
        cameraeVisionCoordinator.pause(.photoCapture)
        defer { cameraeVisionCoordinator.resume(.photoCapture) }
        return try captureQueue.syncSafeCapture(
            photoOutput: photoOutput,
            preferredFormat: selectedSourceFormat
        )
    }

    nonisolated private func prepareCapture(device: AVCaptureDevice) throws -> Double {
        switch captureMode {
        case .astro:
            return try prepareAstroCapture(device: device)
        case .repeatable:
            try applyRepeatableAutoConfiguration(device: device)
            return CMTimeGetSeconds(device.exposureDuration)
        }
    }

    nonisolated private func prepareAstroCapture(device: AVCaptureDevice) throws -> Double {
        switch astroExposureStrategy {
        case .automatic(let maxDuration):
            return try prepareAutomaticAstroExposureCapture(device: device, maxDuration: maxDuration)
        case .fixed(let duration):
            return try prepareLongExposureCapture(device: device, targetSeconds: duration)
        }
    }

    private func lockFocusForCaptureSequence() async {
        await withCheckedContinuation { continuation in
            captureQueue.async {
                guard let device = self.device else {
                    continuation.resume()
                    return
                }

                do {
                    try device.lockForConfiguration()
                    defer {
                        device.unlockForConfiguration()
                    }

                    if device.isSubjectAreaChangeMonitoringEnabled {
                        device.isSubjectAreaChangeMonitoringEnabled = false
                    }

                    if device.isFocusModeSupported(.locked) {
                        device.focusMode = .locked
                        self.isSequenceFocusLocked = true
                        Task { @MainActor in
                            self.status = "Foco travado"
                        }
                    } else {
                        self.isSequenceFocusLocked = false
                        Task { @MainActor in
                            self.status = "Foco travado indisponivel"
                        }
                    }
                } catch {
                    self.isSequenceFocusLocked = false
                    Task { @MainActor in
                        self.status = "Foco nao travou: \(error.localizedDescription)"
                    }
                }

                continuation.resume()
            }
        }
    }

    private func unlockFocusAfterCaptureSequence() {
        captureQueue.async {
            guard let device = self.device else {
                self.isSequenceFocusLocked = false
                return
            }

            do {
                try device.lockForConfiguration()
                defer {
                    device.unlockForConfiguration()
                }

                self.isSequenceFocusLocked = false
                self.applyAutoFocusConfigurationIfNeeded(device: device)
            } catch {
                self.isSequenceFocusLocked = false
            }
        }
    }

    nonisolated private func applyAutoFocusConfigurationIfNeeded(device: AVCaptureDevice) {
        guard !isSequenceFocusLocked else {
            return
        }

        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        } else if device.isFocusModeSupported(.autoFocus) {
            device.focusMode = .autoFocus
        }

        if device.isSubjectAreaChangeMonitoringEnabled == false {
            device.isSubjectAreaChangeMonitoringEnabled = true
        }
    }

    nonisolated private func applyRepeatableAutoConfiguration(device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer {
            device.unlockForConfiguration()
        }

        if #available(iOS 18.0, *),
           device.activeFormat.isAutoVideoFrameRateSupported,
           device.isAutoVideoFrameRateEnabled == false {
            device.isAutoVideoFrameRateEnabled = true
        }

        device.activeVideoMinFrameDuration = CMTime.invalid
        device.activeVideoMaxFrameDuration = CMTime.invalid

        applyAutoFocusConfigurationIfNeeded(device: device)

        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        } else if device.isExposureModeSupported(.autoExpose) {
            device.exposureMode = .autoExpose
        }

        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        } else if device.isWhiteBalanceModeSupported(.autoWhiteBalance) {
            device.whiteBalanceMode = .autoWhiteBalance
        }

        device.setExposureTargetBias(exposureBias)
    }

    nonisolated private func prepareAutomaticAstroExposureCapture(
        device: AVCaptureDevice,
        maxDuration: Double
    ) throws -> Double {
        let exposureDuration = Self.supportedExposureDuration(for: device, targetSeconds: maxDuration)
        let frameDuration = Self.supportedFrameDuration(for: device, targetSeconds: exposureDuration)

        try device.lockForConfiguration()
        defer {
            device.unlockForConfiguration()
        }

        if #available(iOS 18.0, *), device.isAutoVideoFrameRateEnabled {
            device.isAutoVideoFrameRateEnabled = false
        }

        device.activeVideoMinFrameDuration = CMTime.invalid
        device.activeVideoMaxFrameDuration = CMTime(seconds: frameDuration, preferredTimescale: 600)

        applyAutoFocusConfigurationIfNeeded(device: device)

        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.activeMaxExposureDuration = CMTime(seconds: exposureDuration, preferredTimescale: 1_000_000_000)
            device.exposureMode = .continuousAutoExposure
        } else if device.isExposureModeSupported(.autoExpose) {
            device.exposureMode = .autoExpose
        }

        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        } else if device.isWhiteBalanceModeSupported(.autoWhiteBalance) {
            device.whiteBalanceMode = .autoWhiteBalance
        }

        return CMTimeGetSeconds(device.exposureDuration)
    }

    nonisolated private func prepareLongExposureCapture(device: AVCaptureDevice, targetSeconds: Double) throws -> Double {
        let exposureDuration = Self.supportedExposureDuration(for: device, targetSeconds: targetSeconds)
        let frameDuration = Self.supportedFrameDuration(for: device, targetSeconds: exposureDuration)
        let iso = min(max(device.iso, device.activeFormat.minISO), device.activeFormat.maxISO)
        let semaphore = DispatchSemaphore(value: 0)

        try device.lockForConfiguration()
        if #available(iOS 18.0, *), device.isAutoVideoFrameRateEnabled {
            device.isAutoVideoFrameRateEnabled = false
        }

        device.activeVideoMinFrameDuration = CMTime.invalid
        device.activeVideoMaxFrameDuration = CMTime(seconds: frameDuration, preferredTimescale: 600)

        if device.isExposureModeSupported(.custom) {
            device.setExposureModeCustom(
                duration: CMTime(seconds: exposureDuration, preferredTimescale: 1_000_000_000),
                iso: iso,
                completionHandler: { _ in semaphore.signal() }
            )
        } else if device.isExposureModeSupported(.continuousAutoExposure) {
            device.activeMaxExposureDuration = CMTime(seconds: exposureDuration, preferredTimescale: 1_000_000_000)
            device.exposureMode = .continuousAutoExposure
            semaphore.signal()
        } else {
            semaphore.signal()
        }

        device.unlockForConfiguration()
        _ = semaphore.wait(timeout: .now() + 2)
        return exposureDuration
    }

    nonisolated private static func supportedExposureDuration(for device: AVCaptureDevice, targetSeconds: Double) -> Double {
        let minExposure = CMTimeGetSeconds(device.activeFormat.minExposureDuration)
        let maxExposure = CMTimeGetSeconds(device.activeFormat.maxExposureDuration)
        return min(max(targetSeconds, minExposure), maxExposure)
    }

    nonisolated private static func supportedFrameDuration(for device: AVCaptureDevice, targetSeconds: Double) -> Double {
        let ranges = device.activeFormat.videoSupportedFrameRateRanges
        guard !ranges.isEmpty else { return targetSeconds }

        var bestSeconds = targetSeconds
        var bestDistance = Double.greatestFiniteMagnitude

        for range in ranges {
            let minSeconds = CMTimeGetSeconds(range.minFrameDuration)
            let maxSeconds = CMTimeGetSeconds(range.maxFrameDuration)
            guard minSeconds.isFinite, maxSeconds.isFinite else { continue }

            let lower = min(minSeconds, maxSeconds)
            let upper = max(minSeconds, maxSeconds)
            let clamped = min(max(targetSeconds, lower), upper)
            let distance = abs(clamped - targetSeconds)

            if distance < bestDistance {
                bestSeconds = clamped
                bestDistance = distance
            }
        }

        return bestSeconds
    }

    nonisolated private static func formatExposure(_ seconds: Double) -> String {
        guard seconds > 0 else { return "-" }

        if seconds >= 1 {
            return String(format: "%.1fs", seconds)
        }

        return String(format: "%.2fs", seconds)
    }

    private static func formatInterval(_ seconds: Double) -> String {
        String(format: "%.0fs", seconds)
    }

    private static func clampedAstroBatchSize(_ value: Int) -> Int {
        min(max(value, 5), 30)
    }

    private static let astroStackingExposureThreshold = 0.8

    private static func formatEV(_ value: Double) -> String {
        if abs(value) < 0.05 {
            return "0 EV"
        }

        return String(format: "%+.0f EV", value)
    }
}

enum CameraCaptureMode: Equatable {
    case astro
    case repeatable
}

enum RepeatableCameraLens: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case ultraWide
    case wide
    case telephoto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ultraWide: return "Ultra-wide"
        case .wide: return "Wide"
        case .telephoto: return "Tele"
        }
    }

    var shortTitle: String {
        switch self {
        case .ultraWide: return "0,5×"
        case .wide: return "1×"
        case .telephoto: return "Tele"
        }
    }

    var systemImage: String {
        switch self {
        case .ultraWide: return "camera.macro"
        case .wide: return "camera"
        case .telephoto: return "scope"
        }
    }

    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .ultraWide: return .builtInUltraWideCamera
        case .wide: return .builtInWideAngleCamera
        case .telephoto: return .builtInTelephotoCamera
        }
    }

    static func availableBackLenses() -> [RepeatableCameraLens] {
        allCases.filter { lens in
            AVCaptureDevice.default(lens.deviceType, for: .video, position: .back) != nil
        }
    }
}

private enum AstroExposureStrategy {
    case automatic(maxDuration: Double)
    case fixed(duration: Double)
}

private struct CapturedPhoto {
    let data: Data
    let format: CaptureSourceFormat
    let exposureLabel: String
    let exposureSeconds: Double
}

private struct SavedFrame {
    let index: Int
    let url: URL
    let exposureSeconds: Double
}

private final class MovieRecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    private let completion: (Result<URL, Error>) -> Void

    init(completion: @escaping (Result<URL, Error>) -> Void) {
        self.completion = completion
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        defer { MovieRecordingDelegateRetainer.shared.release(self) }

        if let error {
            let userInfo = (error as NSError).userInfo
            let finished = userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool
            if finished != true {
                completion(.failure(error))
                return
            }
        }

        completion(.success(outputFileURL))
    }
}

private final class MovieRecordingDelegateRetainer {
    static let shared = MovieRecordingDelegateRetainer()
    private var delegates: [ObjectIdentifier: MovieRecordingDelegate] = [:]
    private let lock = NSLock()

    func retain(_ delegate: MovieRecordingDelegate) {
        lock.lock()
        delegates[ObjectIdentifier(delegate)] = delegate
        lock.unlock()
    }

    func release(_ delegate: MovieRecordingDelegate) {
        lock.lock()
        delegates.removeValue(forKey: ObjectIdentifier(delegate))
        lock.unlock()
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<CapturedPhoto, Error>) -> Void
    private let format: CaptureSourceFormat

    init(format: CaptureSourceFormat, completion: @escaping (Result<CapturedPhoto, Error>) -> Void) {
        self.format = format
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer { PhotoCaptureDelegateRetainer.shared.release(self) }

        if let error {
            completion(.failure(error))
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            completion(.failure(CameraError.photoEncodingFailed))
            return
        }

        let exposureSeconds = Self.exposureSeconds(from: photo.metadata)
        completion(.success(CapturedPhoto(
            data: data,
            format: format,
            exposureLabel: Self.exposureLabel(from: exposureSeconds),
            exposureSeconds: exposureSeconds
        )))
    }

    private static func exposureSeconds(from metadata: [String: Any]) -> Double {
        guard let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any],
              let exposureTime = exif[kCGImagePropertyExifExposureTime as String] as? Double else {
            return 0
        }

        return exposureTime
    }

    private static func exposureLabel(from exposureTime: Double) -> String {
        guard exposureTime > 0 else { return "-" }

        if exposureTime >= 1 {
            return String(format: "%.2fs", exposureTime)
        }

        return "1/\(Int(round(1 / exposureTime)))s"
    }
}

private final class PhotoCaptureDelegateRetainer {
    static let shared = PhotoCaptureDelegateRetainer()
    private var delegates: [ObjectIdentifier: PhotoCaptureDelegate] = [:]
    private let lock = NSLock()

    func retain(_ delegate: PhotoCaptureDelegate) {
        lock.lock()
        delegates[ObjectIdentifier(delegate)] = delegate
        lock.unlock()
    }

    func release(_ delegate: PhotoCaptureDelegate) {
        lock.lock()
        delegates.removeValue(forKey: ObjectIdentifier(delegate))
        lock.unlock()
    }
}

private extension DispatchQueue {
    func syncSafeCapture(
        photoOutput: AVCapturePhotoOutput,
        preferredFormat: CaptureSourceFormat
    ) throws -> CapturedPhoto {
        let semaphore = DispatchSemaphore(value: 0)
        var capturedResult: Result<CapturedPhoto, Error>?

        let supportsHEIC = photoOutput.availablePhotoCodecTypes.contains(.hevc)
        let selectedFormat: CaptureSourceFormat = preferredFormat == .heic && supportsHEIC ? .heic : .jpeg
        let codec: AVVideoCodecType = selectedFormat == .heic ? .hevc : .jpeg
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: codec])
        settings.photoQualityPrioritization = .speed
        settings.flashMode = .off

        let delegate = PhotoCaptureDelegate(format: selectedFormat) { result in
            capturedResult = result
            semaphore.signal()
        }

        PhotoCaptureDelegateRetainer.shared.retain(delegate)
        photoOutput.capturePhoto(with: settings, delegate: delegate)
        semaphore.wait()

        switch capturedResult {
        case .success(let photo):
            return photo
        case .failure(let error):
            throw error
        case .none:
            throw CameraError.photoEncodingFailed
        }
    }
}

private extension UIImage {
    func normalizedReferenceCGImage() -> CGImage? {
        if imageOrientation == .up {
            return cgImage
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}

enum CameraError: LocalizedError {
    case noCamera
    case configurationFailed
    case photoEncodingFailed
    case missingSession
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noCamera:
            return "camera principal traseira indisponivel"
        case .configurationFailed:
            return "nao foi possivel configurar a sessao"
        case .photoEncodingFailed:
            return "nao foi possivel gerar o JPEG"
        case .missingSession:
            return "sessao nao criada"
        case .cancelled:
            return "captura cancelada"
        }
    }
}

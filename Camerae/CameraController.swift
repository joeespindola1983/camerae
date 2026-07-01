import AVFoundation
import CoreLocation
import CoreMotion
import ImageIO
import UIKit
import Vision

@MainActor
final class CameraController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, CLLocationManagerDelegate {
    nonisolated(unsafe) let session = AVCaptureSession()

    @Published private(set) var status = "Preparando camera"
    @Published private(set) var isTimelapseRunning = false
    @Published private(set) var isSinglePhotoCaptureRunning = false
    @Published private(set) var isVideoRecording = false
    @Published private(set) var frameCount = 0
    @Published private(set) var baseExposureLabel = "-"
    @Published private(set) var stackProgressLabel = "-"
    @Published private(set) var lastCapturedExposureLabel = "-"
    @Published private(set) var countdownLabel = "-"
    @Published private(set) var currentMotion: MotionAttitude?
    @Published private(set) var currentGeoPose: GeoPose?
    @Published private(set) var visualAlignment: VisualAlignmentEstimate?
    @Published private(set) var currentSession: TimelapseSession?
    @Published private(set) var completedSession: TimelapseSession?
    @Published private(set) var lastExportURL: URL?

    private let captureMode: CameraCaptureMode
    private let captureQueue = DispatchQueue(label: "camerae.capture.queue")
    private let visualAlignmentQueue = DispatchQueue(label: "camerae.visual-alignment.queue")
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    nonisolated(unsafe) private let photoOutput = AVCapturePhotoOutput()
    nonisolated(unsafe) private let movieOutput = AVCaptureMovieFileOutput()
    nonisolated(unsafe) private let videoDataOutput = AVCaptureVideoDataOutput()
    nonisolated(unsafe) private let store: TimelapseSessionStore
    nonisolated(unsafe) private var device: AVCaptureDevice?
    nonisolated(unsafe) private var exposureBias: Float = 0
    private var timelapseTask: Task<Void, Never>?
    private var latestLocation: CLLocation?
    private var latestHeading: CLHeading?
    private var bestFineGeoPose: GeoPose?
    private var pendingReferenceOrientation: CaptureDisplayOrientation?
    nonisolated(unsafe) private var referenceCGImage: CGImage?
    nonisolated(unsafe) private var lastVisualAlignmentAnalysis = Date.distantPast
    nonisolated(unsafe) private var isAnalyzingVisualAlignment = false
    nonisolated(unsafe) private var isVisualFineAdjustmentActive = false
    nonisolated(unsafe) private var configured = false
    nonisolated(unsafe) private var isConfiguring = false

    init(project: CameraProject, captureMode: CameraCaptureMode = .astro) {
        self.captureMode = captureMode
        store = TimelapseSessionStore(project: project)
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.headingFilter = 1
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    func start() async {
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        guard allowed else {
            status = "Permissao da camera negada"
            return
        }

        do {
            try await configureIfNeeded()
            startMotionUpdates()
            startLocationUpdates()
            status = "Camera principal pronta"
        } catch {
            status = "Erro: \(error.localizedDescription)"
        }
    }

    func toggleTimelapse(interval: Double) async {
        if isTimelapseRunning {
            stopTimelapse()
        } else {
            await startTimelapse(interval: interval)
        }
    }

    func captureSinglePhoto() async {
        guard !isTimelapseRunning, !isSinglePhotoCaptureRunning else { return }
        isSinglePhotoCaptureRunning = true
        defer { isSinglePhotoCaptureRunning = false }

        do {
            currentSession = try store.createSession(captureKind: .photo)
            completedSession = nil
            frameCount = 0
            lastExportURL = nil
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

    func toggleVideoRecording() async {
        if isVideoRecording {
            stopVideoRecording()
        } else {
            await startVideoRecording()
        }
    }

    func setPendingReferenceOrientation(_ orientation: CaptureDisplayOrientation) {
        pendingReferenceOrientation = orientation
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

    func setVisualReference(_ url: URL?) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            visualAlignmentQueue.async {
                guard let url,
                      let image = UIImage(contentsOfFile: url.path),
                      let cgImage = image.normalizedReferenceCGImage() else {
                    self.referenceCGImage = nil
                    Task { @MainActor in
                        self.visualAlignment = nil
                    }
                    continuation.resume()
                    return
                }

                self.referenceCGImage = cgImage
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
            lastExportURL = try store.exportZip(for: currentSession)
            status = "ZIP pronto"
        } catch {
            status = "Falha no ZIP: \(error.localizedDescription)"
        }
    }

    private func startTimelapse(interval: Double) async {
        do {
            currentSession = try store.createSession(captureKind: .timelapse)
            completedSession = nil
            frameCount = 0
            lastExportURL = nil
            isTimelapseRunning = true
            status = "Estabilizando tripe"

            timelapseTask = Task { [weak self] in
                guard let self else { return }
                await self.runTimelapseWithCountdown(interval: interval)
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
        guard CLLocationManager.locationServicesEnabled() else {
            return
        }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            if locationManager.accuracyAuthorization == .reducedAccuracy {
                locationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "RepeatableAlignment")
            }
            locationManager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                locationManager.startUpdatingHeading()
            }
        case .denied, .restricted:
            break
        @unknown default:
            break
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
        guard let referenceCGImage,
              !isAnalyzingVisualAlignment,
              Date().timeIntervalSince(lastVisualAlignmentAnalysis) >= visualAlignmentAnalysisInterval else {
            return
        }

        lastVisualAlignmentAnalysis = Date()
        isAnalyzingVisualAlignment = true

        do {
            let request = VNHomographicImageRegistrationRequest(
                targetedCMSampleBuffer: sampleBuffer,
                orientation: .right,
                options: [:]
            )
            let handler = VNImageRequestHandler(cgImage: referenceCGImage, orientation: .up, options: [:])
            try handler.perform([request])
            let referenceSize = CGSize(width: referenceCGImage.width, height: referenceCGImage.height)
            let targetSize = Self.orientedTargetImageSize(from: sampleBuffer)
            let estimate = request.results?.first.map {
                Self.visualAlignmentEstimate(
                    from: $0,
                    referenceSize: referenceSize,
                    targetSize: targetSize
                )
            }
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

    nonisolated private static func orientedTargetImageSize(from sampleBuffer: CMSampleBuffer) -> CGSize {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return CGSize(width: 1, height: 1)
        }

        return CGSize(
            width: CVPixelBufferGetHeight(pixelBuffer),
            height: CVPixelBufferGetWidth(pixelBuffer)
        )
    }

    nonisolated private var visualAlignmentAnalysisInterval: TimeInterval {
        isVisualFineAdjustmentActive ? 0.16 : 0.28
    }

    nonisolated private static func visualAlignmentEstimate(
        from observation: VNImageHomographicAlignmentObservation,
        referenceSize: CGSize,
        targetSize: CGSize
    ) -> VisualAlignmentEstimate {
        let transform = observation.warpTransform
        let a = Double(transform.columns.0.x)
        let b = Double(transform.columns.0.y)
        let c = Double(transform.columns.1.x)
        let d = Double(transform.columns.1.y)
        let determinant = a * d - b * c
        let scale = sqrt(abs(determinant))

        let matchAnalysis = visualMatchAnalysis(
            from: transform,
            confidence: Double(observation.confidence),
            referenceSize: referenceSize,
            targetSize: targetSize
        )

        return VisualAlignmentEstimate(
            scale: scale.isFinite ? scale : 1,
            confidence: Double(observation.confidence),
            horizontalOffset: Double(transform.columns.2.x),
            verticalOffset: Double(transform.columns.2.y),
            matchGuides: matchAnalysis.guides,
            visualRotationDegrees: matchAnalysis.rotationDegrees
        )
    }

    nonisolated private static func visualMatchAnalysis(
        from transform: simd_float3x3,
        confidence: Double,
        referenceSize: CGSize,
        targetSize: CGSize
    ) -> (guides: [VisualMatchGuide], rotationDegrees: Double?) {
        guard confidence > 0.02,
              referenceSize.width > 0,
              referenceSize.height > 0,
              targetSize.width > 0,
              targetSize.height > 0 else {
            return ([], nil)
        }

        let anchors = [
            CGPoint(x: 1.0 / 3.0, y: 1.0 / 3.0),
            CGPoint(x: 2.0 / 3.0, y: 1.0 / 3.0),
            CGPoint(x: 0.5, y: 0.5),
            CGPoint(x: 1.0 / 3.0, y: 2.0 / 3.0),
            CGPoint(x: 2.0 / 3.0, y: 2.0 / 3.0)
        ]

        var candidates = [
            (
                transform: transform,
                guides: guides(from: transform, anchors: anchors, referenceSize: referenceSize, targetSize: targetSize)
            )
        ]

        if let invertedTransform = inverted(transform) {
            candidates.append((
                transform: invertedTransform,
                guides: guides(from: invertedTransform, anchors: anchors, referenceSize: referenceSize, targetSize: targetSize)
            ))
        }

        guard let selected = candidates.filter({ $0.guides.count >= 3 }).max(by: { first, second in
            if first.guides.count == second.guides.count {
                return averageGuideLength(first.guides) > averageGuideLength(second.guides)
            }

            return first.guides.count < second.guides.count
        }) else {
            return ([], nil)
        }

        guard averageGuideLength(selected.guides) <= 0.62 else {
            return ([], nil)
        }

        return (selected.guides, visualRotationDegrees(from: selected.transform))
    }

    nonisolated private static func guides(
        from transform: simd_float3x3,
        anchors: [CGPoint],
        referenceSize: CGSize,
        targetSize: CGSize
    ) -> [VisualMatchGuide] {
        anchors.enumerated().compactMap { index, point in
            let referencePixelPoint = CGPoint(
                x: point.x * referenceSize.width,
                y: point.y * referenceSize.height
            )

            guard let projected = projectedPoint(referencePixelPoint, using: transform) else {
                return nil
            }

            let normalizedProjected = CGPoint(
                x: projected.x / targetSize.width,
                y: projected.y / targetSize.height
            )
            let lenientBounds = -0.35...1.35
            guard lenientBounds.contains(normalizedProjected.x),
                  lenientBounds.contains(normalizedProjected.y) else {
                return nil
            }

            return VisualMatchGuide(
                id: index,
                reference: point,
                current: CGPoint(
                    x: min(max(normalizedProjected.x, 0), 1),
                    y: min(max(normalizedProjected.y, 0), 1)
                )
            )
        }
    }

    nonisolated private static func averageGuideLength(_ guides: [VisualMatchGuide]) -> CGFloat {
        guard !guides.isEmpty else { return .greatestFiniteMagnitude }

        let total = guides.reduce(CGFloat(0)) { result, guide in
            let dx = guide.current.x - guide.reference.x
            let dy = guide.current.y - guide.reference.y
            return result + sqrt(dx * dx + dy * dy)
        }

        return total / CGFloat(guides.count)
    }

    nonisolated private static func visualRotationDegrees(from transform: simd_float3x3) -> Double? {
        let radians = atan2(Double(transform.columns.0.y), Double(transform.columns.0.x))
        guard radians.isFinite else { return nil }

        var degrees = radians * 180 / .pi
        while degrees > 180 { degrees -= 360 }
        while degrees < -180 { degrees += 360 }
        return degrees
    }

    nonisolated private static func inverted(_ transform: simd_float3x3) -> simd_float3x3? {
        let determinant = simd_determinant(transform)
        guard determinant.isFinite, abs(determinant) > 0.0001 else {
            return nil
        }

        let invertedTransform = simd_inverse(transform)
        guard invertedTransform.columns.0.x.isFinite,
              invertedTransform.columns.1.y.isFinite,
              invertedTransform.columns.2.z.isFinite else {
            return nil
        }

        return invertedTransform
    }

    nonisolated private static func projectedPoint(
        _ point: CGPoint,
        using transform: simd_float3x3
    ) -> CGPoint? {
        let x = Float(point.x)
        let y = Float(point.y)
        let denominator = transform.columns.0.z * x + transform.columns.1.z * y + transform.columns.2.z
        guard denominator.isFinite, abs(denominator) > 0.0001 else { return nil }

        let projectedX = (transform.columns.0.x * x + transform.columns.1.x * y + transform.columns.2.x) / denominator
        let projectedY = (transform.columns.0.y * x + transform.columns.1.y * y + transform.columns.2.y) / denominator
        guard projectedX.isFinite, projectedY.isFinite else { return nil }

        return CGPoint(x: CGFloat(projectedX), y: CGFloat(projectedY))
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
        countdownLabel = "-"
        stackProgressLabel = "-"
        if frameCount > 0 {
            completedSession = currentSession
            status = "Timelapse concluido"
        } else {
            status = "Timelapse parado"
        }
    }

    private func runTimelapseWithCountdown(interval: Double) async {
        for second in stride(from: 3, through: 1, by: -1) {
            guard !Task.isCancelled else { return }
            countdownLabel = "\(second)s"
            status = "Comecando em \(second)s"
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        guard !Task.isCancelled else { return }
        countdownLabel = "-"
        status = "Capturando timelapse"
        await runTimelapse(interval: interval)
    }

    private func runTimelapse(interval: Double) async {
        let clampedInterval = min(max(interval, 2), 10)
        let intervalNanos = UInt64(clampedInterval * 1_000_000_000)

        while !Task.isCancelled {
            do {
                try await captureAndSaveFrame()
            } catch {
                status = "Frame falhou: \(error.localizedDescription)"
            }

            if !Task.isCancelled {
                status = "Aguardando \(Self.formatInterval(clampedInterval))"
                try? await Task.sleep(nanoseconds: intervalNanos)
            }
        }
    }

    private func startVideoRecording() async {
        guard !isTimelapseRunning, !isSinglePhotoCaptureRunning, !isVideoRecording else { return }

        do {
            try await configureIfNeeded()
            guard movieOutput.isRecording == false else { return }

            let videoSession = try store.createSession(captureKind: .video)
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
            isVideoRecording = true
            status = "Gravando video"

            let delegate = MovieRecordingDelegate { [weak self] result in
                Task { @MainActor in
                    await self?.finishVideoRecording(result: result)
                }
            }
            MovieRecordingDelegateRetainer.shared.retain(delegate)
            movieOutput.startRecording(to: outputURL, recordingDelegate: delegate)
        } catch {
            isVideoRecording = false
            status = "Video falhou: \(error.localizedDescription)"
        }
    }

    private func stopVideoRecording() {
        guard isVideoRecording else { return }
        status = "Finalizando video"
        movieOutput.stopRecording()
    }

    private func finishVideoRecording(result: Result<URL, Error>) async {
        isVideoRecording = false

        do {
            let outputURL = try result.get()
            guard let currentSession else { throw CameraError.missingSession }
            try saveFirstVideoFrame(from: outputURL, in: currentSession)
            frameCount = store.frameCount(in: currentSession)
            completedSession = currentSession
            status = "Video salvo"
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

    private func captureAndSaveFrame() async throws {
        guard let currentSession else { throw CameraError.missingSession }
        applyOutputRotation(for: currentSession.referenceOrientation)
        let photo = try await captureOriginalPhoto()
        let savedURL = try store.saveFrame(photo.data, in: currentSession, index: frameCount + 1)

        if frameCount == 0 {
            self.currentSession = try saveReferencePoseIfAvailable(for: currentSession)
        }

        frameCount += 1
        lastCapturedExposureLabel = photo.exposureLabel
        stackProgressLabel = "Original"
        status = "Salvo \(savedURL.lastPathComponent)"
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
        try await withCheckedThrowingContinuation { continuation in
            captureQueue.async {
                do {
                    guard !self.configured else {
                        if !self.session.isRunning {
                            self.session.startRunning()
                        }
                        continuation.resume(returning: ())
                        return
                    }

                    self.isConfiguring = true
                    self.session.beginConfiguration()

                    if self.session.canSetSessionPreset(.photo) {
                        self.session.sessionPreset = .photo
                    }

                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                        throw CameraError.noCamera
                    }

                    let input = try AVCaptureDeviceInput(device: device)
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
                    self.device = device
                    self.configured = true

                    self.session.commitConfiguration()
                    self.isConfiguring = false
                    self.session.startRunning()

                    let baseExposure = try self.prepareCapture(device: device)
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
                    if self.isConfiguring {
                        self.session.commitConfiguration()
                        self.isConfiguring = false
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
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
        try captureQueue.syncSafeCapture(photoOutput: photoOutput)
    }

    nonisolated private func prepareCapture(device: AVCaptureDevice) throws -> Double {
        switch captureMode {
        case .astro:
            return try prepareLongExposureCapture(device: device)
        case .repeatable:
            try applyRepeatableAutoConfiguration(device: device)
            return CMTimeGetSeconds(device.exposureDuration)
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

        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        } else if device.isFocusModeSupported(.autoFocus) {
            device.focusMode = .autoFocus
        }

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

    nonisolated private func prepareLongExposureCapture(device: AVCaptureDevice) throws -> Double {
        let exposureDuration = Self.supportedExposureDuration(for: device, targetSeconds: 1.0)
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
        if seconds >= 1 {
            return String(format: "%.1fs", seconds)
        }

        return String(format: "%.2fs", seconds)
    }

    private static func formatInterval(_ seconds: Double) -> String {
        String(format: "%.0fs", seconds)
    }

    private static func formatEV(_ value: Double) -> String {
        if abs(value) < 0.05 {
            return "0 EV"
        }

        return String(format: "%+.0f EV", value)
    }
}

enum CameraCaptureMode {
    case astro
    case repeatable
}

struct VisualAlignmentEstimate: Equatable {
    let scale: Double
    let confidence: Double
    let horizontalOffset: Double
    let verticalOffset: Double
    let matchGuides: [VisualMatchGuide]
    let visualRotationDegrees: Double?

    init(
        scale: Double,
        confidence: Double,
        horizontalOffset: Double,
        verticalOffset: Double,
        matchGuides: [VisualMatchGuide] = [],
        visualRotationDegrees: Double? = nil
    ) {
        self.scale = scale
        self.confidence = confidence
        self.horizontalOffset = horizontalOffset
        self.verticalOffset = verticalOffset
        self.matchGuides = matchGuides
        self.visualRotationDegrees = visualRotationDegrees
    }

    var isFineAdjustment: Bool {
        confidence > 0.05 && abs(scale - 1) <= 0.06
    }

    var distanceHint: VisualDistanceHint {
        guard confidence > 0.05 else {
            return .searching
        }

        if scale < 0.96 {
            return .moveBack
        }

        if scale > 1.04 {
            return .moveForward
        }

        return .matched
    }
}

struct VisualMatchGuide: Equatable, Identifiable {
    let id: Int
    let reference: CGPoint
    let current: CGPoint
}

enum VisualDistanceHint {
    case searching
    case moveForward
    case moveBack
    case matched
}

private struct CapturedPhoto {
    let data: Data
    let exposureLabel: String
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

    init(completion: @escaping (Result<CapturedPhoto, Error>) -> Void) {
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

        completion(.success(CapturedPhoto(data: data, exposureLabel: Self.exposureLabel(from: photo.metadata))))
    }

    private static func exposureLabel(from metadata: [String: Any]) -> String {
        guard let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any],
              let exposureTime = exif[kCGImagePropertyExifExposureTime as String] as? Double else {
            return "-"
        }

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
    func syncSafeCapture(photoOutput: AVCapturePhotoOutput) throws -> CapturedPhoto {
        let semaphore = DispatchSemaphore(value: 0)
        var capturedResult: Result<CapturedPhoto, Error>?

        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        settings.photoQualityPrioritization = .speed
        settings.flashMode = .off

        let delegate = PhotoCaptureDelegate { result in
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

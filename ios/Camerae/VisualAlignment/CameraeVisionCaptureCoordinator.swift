import CoreVideo
import Foundation

struct CameraeVisionShadowSnapshot: Sendable {
    let marker: UInt8
    let schemaVersion: Int
    let decision: Int
    let score: Double
    let overlapRatio: Double
    let reprojectionRMSE: Double
    let edgeAlignmentError: Double
    let latencyMilliseconds: Double
    let selectedModel: String
    let reasonCodes: [String]
    let transform3x3: [Double]

    init(
        marker: UInt8 = 0,
        schemaVersion: Int = 1,
        decision: Int = 0,
        score: Double = 0,
        overlapRatio: Double = 0,
        reprojectionRMSE: Double = 0,
        edgeAlignmentError: Double = 0,
        latencyMilliseconds: Double = 0,
        selectedModel: String = "unavailable",
        reasonCodes: [String] = [],
        transform3x3: [Double] = []
    ) {
        self.marker = marker
        self.schemaVersion = schemaVersion
        self.decision = decision
        self.score = score
        self.overlapRatio = overlapRatio
        self.reprojectionRMSE = reprojectionRMSE
        self.edgeAlignmentError = edgeAlignmentError
        self.latencyMilliseconds = latencyMilliseconds
        self.selectedModel = selectedModel
        self.reasonCodes = reasonCodes
        self.transform3x3 = transform3x3
    }
}

final class CameraeVisionFrame: @unchecked Sendable {
    let id: UInt64
    let generation: UInt64
    let pixelBuffer: CVPixelBuffer
    let orientation: CEVImageOrientation
    let timestamp: TimeInterval

    init(
        id: UInt64,
        generation: UInt64,
        pixelBuffer: CVPixelBuffer,
        orientation: CEVImageOrientation,
        timestamp: TimeInterval
    ) {
        self.id = id
        self.generation = generation
        self.pixelBuffer = pixelBuffer
        self.orientation = orientation
        self.timestamp = timestamp
    }
}

protocol CameraeVisionCaptureBackend: AnyObject {
    func evaluate(_ frame: CameraeVisionFrame) throws -> CameraeVisionShadowSnapshot?
    func cancel()
    func resume()
}

protocol CameraeVisionWorkExecuting: AnyObject {
    func execute(_ operation: @escaping () -> Void)
}

final class DispatchCameraeVisionExecutor: CameraeVisionWorkExecuting {
    private let queue: DispatchQueue

    init(queue: DispatchQueue = DispatchQueue(
        label: "camerae.vision.capture-fast",
        qos: .utility
    )) {
        self.queue = queue
    }

    func execute(_ operation: @escaping () -> Void) {
        queue.async(execute: operation)
    }
}

typealias CameraeVisionBackendFactory = (
    _ reference: CVPixelBuffer,
    _ orientation: CEVImageOrientation
) throws -> any CameraeVisionCaptureBackend

/// Owns cadence, backpressure and lifecycle for CaptureFast. It never runs OpenCV
/// on the AVCapture callback queue.
final class CameraeVisionCaptureCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private let executor: any CameraeVisionWorkExecuting
    private let backendFactory: CameraeVisionBackendFactory
    private let resultHandler: (CameraeVisionShadowSnapshot) -> Void

    private var policy: CameraeVisionSchedulingPolicy
    private var backend: (any CameraeVisionCaptureBackend)?
    private var retainedFrames: [UInt64: CameraeVisionFrame] = [:]
    private var nextFrameID: UInt64 = 0
    private var storedLatestSnapshot: CameraeVisionShadowSnapshot?

    init(
        configuration: CameraeVisionSchedulerConfiguration,
        executor: any CameraeVisionWorkExecuting = DispatchCameraeVisionExecutor(),
        backendFactory: @escaping CameraeVisionBackendFactory,
        resultHandler: @escaping (CameraeVisionShadowSnapshot) -> Void = { _ in }
    ) {
        policy = CameraeVisionSchedulingPolicy(configuration: configuration)
        self.executor = executor
        self.backendFactory = backendFactory
        self.resultHandler = resultHandler
    }

    var diagnostics: CameraeVisionSchedulerDiagnostics {
        lock.withLock { policy.diagnostics }
    }

    var isEnabled: Bool {
        lock.withLock { policy.configuration.enabled }
    }

    var latestSnapshot: CameraeVisionShadowSnapshot? {
        lock.withLock { storedLatestSnapshot }
    }

    func updateReference(_ reference: CVPixelBuffer?, orientation: CEVImageOrientation) {
        let oldBackend: (any CameraeVisionCaptureBackend)? = lock.withLock {
            policy.advanceGeneration()
            storedLatestSnapshot = nil
            retainedFrames = retainedFrames.filter { $0.key == policy.activeFrameID }
            let old = backend
            backend = nil
            if reference == nil { policy.pause(.referenceUnavailable) }
            return old
        }
        oldBackend?.cancel()

        guard let reference else { return }
        lock.withLock { policy.resume(.referenceUnavailable) }
        guard lock.withLock({ policy.configuration.enabled }) else { return }

        do {
            let newBackend = try backendFactory(reference, orientation)
            lock.withLock { backend = newBackend }
        } catch {
            lock.withLock { policy.pause(.referenceUnavailable) }
        }
    }

    func submit(
        _ pixelBuffer: CVPixelBuffer,
        orientation: CEVImageOrientation,
        at timestamp: TimeInterval
    ) {
        var action = CameraeVisionSchedulerAction.none
        lock.withLock {
            nextFrameID &+= 1
            let frameID = nextFrameID
            action = policy.submit(frameID: frameID, at: timestamp)
            switch action {
            case .start, .pending:
                retainedFrames[frameID] = CameraeVisionFrame(
                    id: frameID,
                    generation: policy.generation,
                    pixelBuffer: pixelBuffer,
                    orientation: orientation,
                    timestamp: timestamp
                )
                if case let .pending(_, replacedFrameID) = action, let replacedFrameID {
                    retainedFrames.removeValue(forKey: replacedFrameID)
                }
            case .discarded, .none:
                break
            }
        }
        scheduleIfNeeded(action)
    }

    func pause(_ reason: CameraeVisionPauseReason) {
        let currentBackend = lock.withLock { () -> (any CameraeVisionCaptureBackend)? in
            policy.pause(reason)
            retainedFrames = retainedFrames.filter { $0.key == policy.activeFrameID }
            return backend
        }
        currentBackend?.cancel()
    }

    func invalidateResults() {
        lock.withLock {
            policy.advanceGeneration()
            storedLatestSnapshot = nil
            retainedFrames = retainedFrames.filter { $0.key == policy.activeFrameID }
        }
    }

    func updateCadence(_ cadence: CameraeVisionCadence) {
        lock.withLock {
            var configuration = policy.configuration
            configuration.cadence = cadence
            policy.updateConfiguration(configuration)
        }
    }

    func resume(_ reason: CameraeVisionPauseReason) {
        let currentBackend = lock.withLock { () -> (any CameraeVisionCaptureBackend)? in
            policy.resume(reason)
            return backend
        }
        currentBackend?.resume()
    }

    private func scheduleIfNeeded(_ action: CameraeVisionSchedulerAction) {
        guard case let .start(frameID, generation) = action else { return }
        let work = lock.withLock { () -> (CameraeVisionFrame, any CameraeVisionCaptureBackend)? in
            guard let frame = retainedFrames[frameID], let backend else { return nil }
            return (frame, backend)
        }
        guard let (frame, backend) = work else { return }

        executor.execute { [self] in
            do {
                let snapshot = try backend.evaluate(frame)
                finish(frameID: frameID, generation: generation, timestamp: frame.timestamp, snapshot: snapshot)
            } catch {
                fail(frameID: frameID, generation: generation, timestamp: frame.timestamp)
            }
        }
    }

    private func finish(
        frameID: UInt64,
        generation: UInt64,
        timestamp: TimeInterval,
        snapshot: CameraeVisionShadowSnapshot?
    ) {
        var nextAction = CameraeVisionSchedulerAction.none
        var shouldPublish = false
        lock.withLock {
            retainedFrames.removeValue(forKey: frameID)
            let generationWasCurrent = generation == policy.generation
            nextAction = policy.complete(frameID: frameID, generation: generation, at: timestamp)
            shouldPublish = generationWasCurrent && snapshot != nil
            if shouldPublish { storedLatestSnapshot = snapshot }
        }
        if shouldPublish, let snapshot { resultHandler(snapshot) }
        scheduleIfNeeded(nextAction)
    }

    private func fail(frameID: UInt64, generation: UInt64, timestamp: TimeInterval) {
        var nextAction = CameraeVisionSchedulerAction.none
        lock.withLock {
            retainedFrames.removeValue(forKey: frameID)
            nextAction = policy.fail(frameID: frameID, generation: generation, at: timestamp)
        }
        scheduleIfNeeded(nextAction)
    }

}

private extension NSLock {
    func withLock<Result>(_ operation: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try operation()
    }
}

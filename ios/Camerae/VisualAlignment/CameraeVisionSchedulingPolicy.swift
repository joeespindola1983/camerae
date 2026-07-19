import Foundation

enum CameraeVisionCadence: Sendable {
    case conservative
    case balanced
    case responsive

    var interval: TimeInterval {
        switch self {
        case .conservative: 1
        case .balanced: 0.5
        case .responsive: 0.25
        }
    }
}

struct CameraeVisionSchedulerConfiguration: Equatable, Sendable {
    var enabled: Bool
    var cadence: CameraeVisionCadence
    var consecutiveFailureLimit: Int
    var cooldownDuration: TimeInterval

    static let disabled = Self(enabled: false, cadence: .balanced)

    init(
        enabled: Bool,
        cadence: CameraeVisionCadence,
        consecutiveFailureLimit: Int = 3,
        cooldownDuration: TimeInterval = 5
    ) {
        self.enabled = enabled
        self.cadence = cadence
        self.consecutiveFailureLimit = max(1, consecutiveFailureLimit)
        self.cooldownDuration = max(0, cooldownDuration)
    }
}

enum CameraeVisionPauseReason: Hashable, Sendable {
    case photoCapture
    case videoRecording
    case astroProcessing
    case lensChange
    case lifecycle
    case thermal
    case memoryPressure
    case referenceUnavailable
}

enum CameraeVisionDiscardReason: Equatable, Sendable {
    case disabled
    case cadence
    case paused
    case cooldown
}

enum CameraeVisionSchedulerAction: Equatable, Sendable {
    case start(frameID: UInt64, generation: UInt64)
    case pending(frameID: UInt64, replacedFrameID: UInt64?)
    case discarded(CameraeVisionDiscardReason)
    case none
}

struct CameraeVisionSchedulerDiagnostics: Equatable, Sendable {
    var admitted = 0
    var analyzed = 0
    var replaced = 0
    var failed = 0
    var stale = 0
    var maximumBacklog = 0
}

/// Pure scheduling state. Time is supplied by the caller so tests never sleep.
struct CameraeVisionSchedulingPolicy: Sendable {
    private(set) var configuration: CameraeVisionSchedulerConfiguration
    private(set) var diagnostics = CameraeVisionSchedulerDiagnostics()
    private(set) var generation: UInt64 = 0
    private(set) var activeFrameID: UInt64?
    private(set) var pendingFrameID: UInt64?

    private var pauseReasons: Set<CameraeVisionPauseReason> = []
    private var lastAdmissionTime: TimeInterval?
    private var consecutiveFailures = 0
    private var cooldownUntil: TimeInterval?

    init(configuration: CameraeVisionSchedulerConfiguration) {
        self.configuration = configuration
    }

    mutating func submit(frameID: UInt64, at timestamp: TimeInterval) -> CameraeVisionSchedulerAction {
        guard configuration.enabled else { return .discarded(.disabled) }
        guard pauseReasons.isEmpty else { return .discarded(.paused) }
        if let cooldownUntil, timestamp < cooldownUntil {
            return .discarded(.cooldown)
        }
        if let lastAdmissionTime,
           timestamp - lastAdmissionTime < configuration.cadence.interval {
            return .discarded(.cadence)
        }

        lastAdmissionTime = timestamp
        diagnostics.admitted += 1
        if activeFrameID == nil {
            activeFrameID = frameID
            diagnostics.maximumBacklog = max(diagnostics.maximumBacklog, 1)
            return .start(frameID: frameID, generation: generation)
        }

        let replaced = pendingFrameID
        pendingFrameID = frameID
        if replaced != nil { diagnostics.replaced += 1 }
        diagnostics.maximumBacklog = max(diagnostics.maximumBacklog, 2)
        return .pending(frameID: frameID, replacedFrameID: replaced)
    }

    mutating func complete(
        frameID: UInt64,
        generation completedGeneration: UInt64,
        at timestamp: TimeInterval
    ) -> CameraeVisionSchedulerAction {
        guard activeFrameID == frameID else {
            diagnostics.stale += 1
            return .none
        }
        activeFrameID = nil

        guard completedGeneration == generation else {
            diagnostics.stale += 1
            return .none
        }
        diagnostics.analyzed += 1
        consecutiveFailures = 0
        cooldownUntil = nil
        return startPendingIfAvailable()
    }

    mutating func fail(
        frameID: UInt64,
        generation failedGeneration: UInt64,
        at timestamp: TimeInterval
    ) -> CameraeVisionSchedulerAction {
        guard activeFrameID == frameID else {
            diagnostics.stale += 1
            return .none
        }
        activeFrameID = nil
        guard failedGeneration == generation else {
            diagnostics.stale += 1
            return .none
        }

        diagnostics.failed += 1
        consecutiveFailures += 1
        if consecutiveFailures >= configuration.consecutiveFailureLimit {
            cooldownUntil = timestamp + configuration.cooldownDuration
            pendingFrameID = nil
            return .none
        }
        return startPendingIfAvailable()
    }

    mutating func advanceGeneration() {
        generation &+= 1
        pendingFrameID = nil
        lastAdmissionTime = nil
        consecutiveFailures = 0
        cooldownUntil = nil
    }

    mutating func pause(_ reason: CameraeVisionPauseReason) {
        pauseReasons.insert(reason)
        pendingFrameID = nil
    }

    mutating func resume(_ reason: CameraeVisionPauseReason) {
        pauseReasons.remove(reason)
    }

    mutating func updateConfiguration(_ configuration: CameraeVisionSchedulerConfiguration) {
        self.configuration = configuration
        if !configuration.enabled {
            pendingFrameID = nil
        }
    }

    private mutating func startPendingIfAvailable() -> CameraeVisionSchedulerAction {
        guard pauseReasons.isEmpty, let pendingFrameID else { return .none }
        self.pendingFrameID = nil
        activeFrameID = pendingFrameID
        return .start(frameID: pendingFrameID, generation: generation)
    }
}

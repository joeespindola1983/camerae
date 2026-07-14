import Foundation

public enum CaptureWorkflow: String, Codable, CaseIterable, Hashable, Sendable {
    case repeatableVideo
    case repeatableTimelapse
    case astro
}

public enum CaptureSourceFormat: String, Codable, CaseIterable, Hashable, Sendable {
    case heic
    case jpeg
    case dng
}

public enum CaptureResolution: String, Codable, CaseIterable, Hashable, Sendable {
    case highDefinition
    case fullHD
    case ultraHD
    case fullSensor
}

public enum AstroPipelineProfile: String, Codable, CaseIterable, Hashable, Sendable {
    case full
    case reduced
    case starsTimelapse
}

public enum RepeatableVideoDurationPreset: String, Codable, CaseIterable, Sendable {
    case thirtySeconds
    case oneMinute

    public var duration: TimeInterval {
        switch self {
        case .thirtySeconds: 30
        case .oneMinute: 60
        }
    }
}

public enum RepeatableTimelapseDurationPreset: String, Codable, CaseIterable, Sendable {
    case fiveMinutes
    case tenMinutes
    case thirtyMinutes

    public var duration: TimeInterval {
        switch self {
        case .fiveMinutes: 5 * 60
        case .tenMinutes: 10 * 60
        case .thirtyMinutes: 30 * 60
        }
    }
}

public enum AstroDurationPreset: String, Codable, CaseIterable, Sendable {
    case thirtyMinutes
    case oneHour
    case threeHours

    public var duration: TimeInterval {
        switch self {
        case .thirtyMinutes: 30 * 60
        case .oneHour: 60 * 60
        case .threeHours: 3 * 60 * 60
        }
    }
}

public enum CaptureDurationPreset: Equatable, Sendable {
    case repeatableVideo(RepeatableVideoDurationPreset)
    case repeatableTimelapse(RepeatableTimelapseDurationPreset)
    case astro(AstroDurationPreset)

    public var workflow: CaptureWorkflow {
        switch self {
        case .repeatableVideo: .repeatableVideo
        case .repeatableTimelapse: .repeatableTimelapse
        case .astro: .astro
        }
    }

    public var duration: TimeInterval {
        switch self {
        case .repeatableVideo(let preset): preset.duration
        case .repeatableTimelapse(let preset): preset.duration
        case .astro(let preset): preset.duration
        }
    }
}

public enum CapturePlanError: Error, Equatable, Sendable {
    case invalidDuration
    case invalidCaptureInterval
    case invalidCaptureFPS
    case invalidRenderFPS
    case unexpectedCaptureInterval
    case unexpectedRenderFPS
    case unexpectedAstroPipeline
    case missingAstroPipeline
    case arithmeticOverflow
    case missingSizeEstimate
}

public struct CapturePlan: Codable, Equatable, Hashable, Sendable {
    public let workflow: CaptureWorkflow
    public let plannedDuration: TimeInterval
    public let captureInterval: TimeInterval?
    public let sourceFormat: CaptureSourceFormat
    public let captureFPS: Int?
    public let renderFPS: Int?
    public let resolution: CaptureResolution
    public let astroPipeline: AstroPipelineProfile?

    public init(
        workflow: CaptureWorkflow,
        plannedDuration: TimeInterval,
        captureInterval: TimeInterval?,
        sourceFormat: CaptureSourceFormat,
        captureFPS: Int?,
        renderFPS: Int?,
        resolution: CaptureResolution,
        astroPipeline: AstroPipelineProfile?
    ) throws {
        guard plannedDuration.isFinite, plannedDuration > 0 else { throw CapturePlanError.invalidDuration }
        switch workflow {
        case .repeatableVideo:
            guard captureInterval == nil else { throw CapturePlanError.unexpectedCaptureInterval }
            guard let captureFPS, captureFPS > 0 else { throw CapturePlanError.invalidCaptureFPS }
            guard renderFPS == nil else { throw CapturePlanError.unexpectedRenderFPS }
            guard astroPipeline == nil else { throw CapturePlanError.unexpectedAstroPipeline }
        case .repeatableTimelapse:
            guard let captureInterval, captureInterval.isFinite, captureInterval > 0 else {
                throw CapturePlanError.invalidCaptureInterval
            }
            guard captureFPS == nil else { throw CapturePlanError.invalidCaptureFPS }
            guard let renderFPS, renderFPS > 0 else { throw CapturePlanError.invalidRenderFPS }
            guard astroPipeline == nil else { throw CapturePlanError.unexpectedAstroPipeline }
        case .astro:
            guard let captureInterval, captureInterval.isFinite, captureInterval > 0 else {
                throw CapturePlanError.invalidCaptureInterval
            }
            guard captureFPS == nil else { throw CapturePlanError.invalidCaptureFPS }
            guard let renderFPS, renderFPS > 0 else { throw CapturePlanError.invalidRenderFPS }
            guard astroPipeline != nil else { throw CapturePlanError.missingAstroPipeline }
        }
        self.workflow = workflow
        self.plannedDuration = plannedDuration
        self.captureInterval = captureInterval
        self.sourceFormat = sourceFormat
        self.captureFPS = captureFPS
        self.renderFPS = renderFPS
        self.resolution = resolution
        self.astroPipeline = astroPipeline
    }

    public static func preset(
        _ preset: CaptureDurationPreset,
        sourceFormat: CaptureSourceFormat,
        captureInterval: TimeInterval? = nil,
        captureFPS: Int? = nil,
        renderFPS: Int? = nil,
        resolution: CaptureResolution,
        astroPipeline: AstroPipelineProfile? = nil
    ) throws -> CapturePlan {
        try CapturePlan(
            workflow: preset.workflow,
            plannedDuration: preset.duration,
            captureInterval: captureInterval,
            sourceFormat: sourceFormat,
            captureFPS: captureFPS,
            renderFPS: renderFPS,
            resolution: resolution,
            astroPipeline: astroPipeline
        )
    }
}

public struct CaptureSizeProfile: Equatable, Sendable {
    public let bytesPerFrameUpperBound: UInt64?
    public let videoBitsPerSecondUpperBound: UInt64?
    public let processingOverheadFraction: Double
    public let publicationOverheadFraction: Double

    public init(
        bytesPerFrameUpperBound: UInt64? = nil,
        videoBitsPerSecondUpperBound: UInt64? = nil,
        processingOverheadFraction: Double = 0,
        publicationOverheadFraction: Double = 0
    ) {
        self.bytesPerFrameUpperBound = bytesPerFrameUpperBound
        self.videoBitsPerSecondUpperBound = videoBitsPerSecondUpperBound
        self.processingOverheadFraction = max(processingOverheadFraction, 0)
        self.publicationOverheadFraction = max(publicationOverheadFraction, 0)
    }
}

public struct CaptureEstimate: Equatable, Sendable {
    public let expectedFrameCount: UInt64
    public let captureBytes: UInt64
    public let processingBytes: UInt64
    public let publicationBytes: UInt64
    public let renderedDuration: TimeInterval?

    public init(
        expectedFrameCount: UInt64,
        captureBytes: UInt64,
        processingBytes: UInt64,
        publicationBytes: UInt64,
        renderedDuration: TimeInterval?
    ) {
        self.expectedFrameCount = expectedFrameCount
        self.captureBytes = captureBytes
        self.processingBytes = processingBytes
        self.publicationBytes = publicationBytes
        self.renderedDuration = renderedDuration
    }
}

public struct CapturePlanEstimator: Sendable {
    public init() {}

    public func estimate(plan: CapturePlan, sizeProfile: CaptureSizeProfile) throws -> CaptureEstimate {
        let frameCount: UInt64
        let captureBytes: UInt64
        let renderedDuration: TimeInterval?

        switch plan.workflow {
        case .repeatableVideo:
            guard let fps = plan.captureFPS, let bitrate = sizeProfile.videoBitsPerSecondUpperBound else {
                throw CapturePlanError.missingSizeEstimate
            }
            frameCount = try conservativeCount(plan.plannedDuration * Double(fps))
            captureBytes = try conservativeCount(plan.plannedDuration * Double(bitrate) / 8)
            renderedDuration = plan.plannedDuration
        case .repeatableTimelapse, .astro:
            guard let interval = plan.captureInterval, let bytesPerFrame = sizeProfile.bytesPerFrameUpperBound else {
                throw CapturePlanError.missingSizeEstimate
            }
            frameCount = try conservativeCount(plan.plannedDuration / interval)
            let multiplication = frameCount.multipliedReportingOverflow(by: bytesPerFrame)
            guard !multiplication.overflow else { throw CapturePlanError.arithmeticOverflow }
            captureBytes = multiplication.partialValue
            renderedDuration = plan.renderFPS.map { Double(frameCount) / Double($0) }
        }

        return CaptureEstimate(
            expectedFrameCount: frameCount,
            captureBytes: captureBytes,
            processingBytes: try overheadBytes(base: captureBytes, fraction: sizeProfile.processingOverheadFraction),
            publicationBytes: try overheadBytes(base: captureBytes, fraction: sizeProfile.publicationOverheadFraction),
            renderedDuration: renderedDuration
        )
    }

    private func conservativeCount(_ value: Double) throws -> UInt64 {
        guard value.isFinite, value >= 0, value < 18_446_744_073_709_551_616 else {
            throw CapturePlanError.arithmeticOverflow
        }
        return UInt64(ceil(value))
    }

    private func overheadBytes(base: UInt64, fraction: Double) throws -> UInt64 {
        try conservativeCount(Double(base) * fraction)
    }
}

public enum CaptureAdmissionDecision: String, Equatable, Sendable {
    case allowed
    case warning
    case blocked
    case unknown
}

public enum CaptureAdmissionReason: String, Equatable, Sendable {
    case sufficientCapacity
    case lowStorageMargin
    case insufficientStorage
    case capacityUnavailable
    case arithmeticOverflow
}

public struct CaptureAdmissionResult: Equatable, Sendable {
    public let decision: CaptureAdmissionDecision
    public let reason: CaptureAdmissionReason
    public let requiredBytes: UInt64?
    public let availableBytes: UInt64?
    public let shortfallBytes: UInt64
}

public struct CaptureAdmissionConfiguration: Equatable, Sendable {
    public let minimumOperationalReserve: UInt64
    public let planReserveFraction: Double
    public let warningMarginFraction: Double

    public init(
        minimumOperationalReserve: UInt64 = 2 * 1_024 * 1_024 * 1_024,
        planReserveFraction: Double = 0.10,
        warningMarginFraction: Double = 0.15
    ) {
        self.minimumOperationalReserve = minimumOperationalReserve
        self.planReserveFraction = max(planReserveFraction, 0)
        self.warningMarginFraction = max(warningMarginFraction, 0)
    }
}

public struct CaptureAdmissionPolicy: Sendable {
    public let configuration: CaptureAdmissionConfiguration

    public init(configuration: CaptureAdmissionConfiguration = .init()) {
        self.configuration = configuration
    }

    public func evaluate(estimate: CaptureEstimate, availableBytes: UInt64?) -> CaptureAdmissionResult {
        guard let availableBytes else {
            return .init(decision: .unknown, reason: .capacityUnavailable, requiredBytes: nil, availableBytes: nil, shortfallBytes: 0)
        }
        guard let required = requiredBytes(for: estimate) else {
            return .init(decision: .blocked, reason: .arithmeticOverflow, requiredBytes: nil, availableBytes: availableBytes, shortfallBytes: 0)
        }
        guard availableBytes >= required else {
            return .init(
                decision: .blocked,
                reason: .insufficientStorage,
                requiredBytes: required,
                availableBytes: availableBytes,
                shortfallBytes: required - availableBytes
            )
        }

        let warningMargin = UInt64(ceil(Double(required) * configuration.warningMarginFraction))
        let warningThreshold = required.addingReportingOverflow(warningMargin)
        let isWarning = warningThreshold.overflow || availableBytes < warningThreshold.partialValue
        return .init(
            decision: isWarning ? .warning : .allowed,
            reason: isWarning ? .lowStorageMargin : .sufficientCapacity,
            requiredBytes: required,
            availableBytes: availableBytes,
            shortfallBytes: 0
        )
    }

    private func requiredBytes(for estimate: CaptureEstimate) -> UInt64? {
        let reserveValue = ceil(Double(estimate.captureBytes) * configuration.planReserveFraction)
        guard reserveValue.isFinite, reserveValue >= 0, reserveValue < 18_446_744_073_709_551_616 else {
            return nil
        }
        let planReserve = UInt64(reserveValue)
        let reserve = max(configuration.minimumOperationalReserve, planReserve)
        var total: UInt64 = 0
        for value in [estimate.captureBytes, estimate.processingBytes, estimate.publicationBytes, reserve] {
            let result = total.addingReportingOverflow(value)
            guard !result.overflow else { return nil }
            total = result.partialValue
        }
        return total
    }
}

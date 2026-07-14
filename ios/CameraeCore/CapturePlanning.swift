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

public enum StorageCapacitySource: String, Codable, Equatable, Sendable {
    case importantUsage
    case testFixture
}

public struct StorageCapacitySnapshot: Equatable, Sendable {
    public let availableForImportantUsage: UInt64?
    public let capturedAt: Date
    public let source: StorageCapacitySource

    public init(
        availableForImportantUsage: UInt64?,
        capturedAt: Date,
        source: StorageCapacitySource
    ) {
        self.availableForImportantUsage = availableForImportantUsage
        self.capturedAt = capturedAt
        self.source = source
    }
}

public protocol StorageCapacityProviding: Sendable {
    func snapshot() async -> StorageCapacitySnapshot
}

public enum BatteryState: String, Codable, Equatable, Sendable {
    case unknown
    case unplugged
    case charging
    case full
}

public enum CaptureThermalState: String, Codable, Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical
    case unknown
}

public struct BatterySnapshot: Equatable, Sendable {
    public let level: Double?
    public let state: BatteryState
    public let isLowPowerModeEnabled: Bool
    public let thermalState: CaptureThermalState
    public let capturedAt: Date

    public init(
        level: Double?,
        state: BatteryState,
        isLowPowerModeEnabled: Bool,
        thermalState: CaptureThermalState,
        capturedAt: Date
    ) {
        self.level = level.map { min(max($0, 0), 1) }
        self.state = state
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.thermalState = thermalState
        self.capturedAt = capturedAt
    }

    public static func unknown(at date: Date) -> BatterySnapshot {
        BatterySnapshot(
            level: nil,
            state: .unknown,
            isLowPowerModeEnabled: false,
            thermalState: .unknown,
            capturedAt: date
        )
    }
}

public protocol BatterySnapshotProviding: Sendable {
    func snapshot() async -> BatterySnapshot
}

public struct DeviceCapabilityProfile: Equatable, Sendable {
    public let supportedSourceFormats: Set<CaptureSourceFormat>
    public let supportedAstroPipelines: Set<AstroPipelineProfile>

    public init(
        supportedSourceFormats: Set<CaptureSourceFormat>,
        supportedAstroPipelines: Set<AstroPipelineProfile>
    ) {
        self.supportedSourceFormats = supportedSourceFormats
        self.supportedAstroPipelines = supportedAstroPipelines
    }
}

public enum CaptureFormatFallbackReason: String, Equatable, Sendable {
    case preferredFormatUnavailable
}

public struct CaptureFormatResolution: Equatable, Sendable {
    public let selectedFormat: CaptureSourceFormat
    public let fallbackReason: CaptureFormatFallbackReason?
}

public enum CaptureFormatResolutionError: Error, Equatable, Sendable {
    case noSupportedProcessedFormat
}

public struct CaptureFormatResolver: Sendable {
    public init() {}

    public func resolve(
        preferred: CaptureSourceFormat,
        profile: DeviceCapabilityProfile
    ) throws -> CaptureFormatResolution {
        if profile.supportedSourceFormats.contains(preferred) {
            return CaptureFormatResolution(selectedFormat: preferred, fallbackReason: nil)
        }
        if profile.supportedSourceFormats.contains(.jpeg) {
            return CaptureFormatResolution(
                selectedFormat: .jpeg,
                fallbackReason: .preferredFormatUnavailable
            )
        }
        if profile.supportedSourceFormats.contains(.heic) {
            return CaptureFormatResolution(
                selectedFormat: .heic,
                fallbackReason: .preferredFormatUnavailable
            )
        }
        throw CaptureFormatResolutionError.noSupportedProcessedFormat
    }
}

public enum CaptureEnergyDecision: String, Equatable, Sendable {
    case sufficient
    case warning
    case critical
    case unknown
}

public enum EstimateConfidence: String, Equatable, Sendable {
    case low
    case medium
    case high
}

public struct CaptureEnergyEstimate: Equatable, Sendable {
    public let decision: CaptureEnergyDecision
    public let estimatedEndLevel: ClosedRange<Double>
    public let externalPowerRecommended: Bool
    public let confidence: EstimateConfidence
}

public struct CaptureEnergyEstimator: Sendable {
    public init() {}

    public func estimate(
        plan: CapturePlan,
        snapshot: BatterySnapshot,
        observedDrainPerHour: Double?,
        uncertaintyFraction: Double = 0.25
    ) -> CaptureEnergyEstimate {
        guard
            let level = snapshot.level,
            let drainPerHour = observedDrainPerHour,
            drainPerHour.isFinite,
            drainPerHour >= 0
        else {
            return CaptureEnergyEstimate(
                decision: .unknown,
                estimatedEndLevel: 0...1,
                externalPowerRecommended: plan.workflow == .astro,
                confidence: .low
            )
        }

        let durationHours = plan.plannedDuration / 3_600
        let expectedDrain = drainPerHour * durationHours
        let uncertainty = expectedDrain * max(uncertaintyFraction, 0)
        let center = level - expectedDrain
        let range = min(max(center - uncertainty, 0), 1)...min(max(center + uncertainty, 0), 1)
        let isExternallyPowered = snapshot.state == .charging || snapshot.state == .full
        let externalPowerRecommended = plan.workflow == .astro &&
            plan.plannedDuration >= 30 * 60 &&
            !isExternallyPowered

        let decision: CaptureEnergyDecision
        if snapshot.thermalState == .critical || range.lowerBound <= 0.05 {
            decision = .critical
        } else if snapshot.thermalState == .serious ||
                    snapshot.isLowPowerModeEnabled ||
                    range.lowerBound <= 0.20 ||
                    externalPowerRecommended {
            decision = .warning
        } else {
            decision = .sufficient
        }

        return CaptureEnergyEstimate(
            decision: decision,
            estimatedEndLevel: range,
            externalPowerRecommended: externalPowerRecommended,
            confidence: .medium
        )
    }
}

public struct CapturePlanDocument: Equatable, Sendable {
    public let schemaVersion: Int
    public let plan: CapturePlan

    public init(schemaVersion: Int = 1, plan: CapturePlan) {
        self.schemaVersion = schemaVersion
        self.plan = plan
    }
}

public enum CapturePlanCodecError: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
}

public struct CapturePlanCodec: Sendable {
    public static let currentSchemaVersion = 1

    public init() {}

    public func encode(_ plan: CapturePlan) throws -> Data {
        let envelope = Envelope(
            schemaVersion: Self.currentSchemaVersion,
            plan: Payload(plan: plan)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(envelope)
    }

    public func decode(_ data: Data) throws -> CapturePlanDocument {
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.schemaVersion == Self.currentSchemaVersion else {
            throw CapturePlanCodecError.unsupportedSchema(envelope.schemaVersion)
        }
        let payload = envelope.plan
        let plan = try CapturePlan(
            workflow: payload.workflow,
            plannedDuration: payload.plannedDuration,
            captureInterval: payload.captureInterval,
            sourceFormat: payload.sourceFormat,
            captureFPS: payload.captureFPS,
            renderFPS: payload.renderFPS,
            resolution: payload.resolution,
            astroPipeline: payload.astroPipeline
        )
        return CapturePlanDocument(schemaVersion: envelope.schemaVersion, plan: plan)
    }

    private struct Envelope: Codable {
        let schemaVersion: Int
        let plan: Payload
    }

    private struct Payload: Codable {
        let workflow: CaptureWorkflow
        let plannedDuration: TimeInterval
        let captureInterval: TimeInterval?
        let sourceFormat: CaptureSourceFormat
        let captureFPS: Int?
        let renderFPS: Int?
        let resolution: CaptureResolution
        let astroPipeline: AstroPipelineProfile?

        init(plan: CapturePlan) {
            workflow = plan.workflow
            plannedDuration = plan.plannedDuration
            captureInterval = plan.captureInterval
            sourceFormat = plan.sourceFormat
            captureFPS = plan.captureFPS
            renderFPS = plan.renderFPS
            resolution = plan.resolution
            astroPipeline = plan.astroPipeline
        }
    }
}

public struct CapturePreflightResult: Equatable, Sendable {
    public let resolvedPlan: CapturePlan
    public let formatFallbackReason: CaptureFormatFallbackReason?
    public let estimate: CaptureEstimate
    public let storageSnapshot: StorageCapacitySnapshot
    public let storage: CaptureAdmissionResult
    public let batterySnapshot: BatterySnapshot
    public let energy: CaptureEnergyEstimate
}

public struct CapturePreflightService: Sendable {
    private let storageProvider: any StorageCapacityProviding
    private let batteryProvider: any BatterySnapshotProviding
    private let estimator: CapturePlanEstimator
    private let formatResolver: CaptureFormatResolver
    private let admissionPolicy: CaptureAdmissionPolicy
    private let energyEstimator: CaptureEnergyEstimator

    public init(
        storageProvider: any StorageCapacityProviding,
        batteryProvider: any BatterySnapshotProviding,
        estimator: CapturePlanEstimator = .init(),
        formatResolver: CaptureFormatResolver = .init(),
        admissionPolicy: CaptureAdmissionPolicy = .init(),
        energyEstimator: CaptureEnergyEstimator = .init()
    ) {
        self.storageProvider = storageProvider
        self.batteryProvider = batteryProvider
        self.estimator = estimator
        self.formatResolver = formatResolver
        self.admissionPolicy = admissionPolicy
        self.energyEstimator = energyEstimator
    }

    public func evaluate(
        plan: CapturePlan,
        sizeProfile: CaptureSizeProfile,
        capabilityProfile: DeviceCapabilityProfile,
        observedDrainPerHour: Double?
    ) async throws -> CapturePreflightResult {
        let format = try formatResolver.resolve(
            preferred: plan.sourceFormat,
            profile: capabilityProfile
        )
        let resolvedPlan = try plan.replacingSourceFormat(format.selectedFormat)
        let estimate = try estimator.estimate(plan: resolvedPlan, sizeProfile: sizeProfile)
        async let storageSnapshot = storageProvider.snapshot()
        async let batterySnapshot = batteryProvider.snapshot()
        let (storage, battery) = await (storageSnapshot, batterySnapshot)

        return CapturePreflightResult(
            resolvedPlan: resolvedPlan,
            formatFallbackReason: format.fallbackReason,
            estimate: estimate,
            storageSnapshot: storage,
            storage: admissionPolicy.evaluate(
                estimate: estimate,
                availableBytes: storage.availableForImportantUsage
            ),
            batterySnapshot: battery,
            energy: energyEstimator.estimate(
                plan: resolvedPlan,
                snapshot: battery,
                observedDrainPerHour: observedDrainPerHour
            )
        )
    }
}

private extension CapturePlan {
    func replacingSourceFormat(_ format: CaptureSourceFormat) throws -> CapturePlan {
        try CapturePlan(
            workflow: workflow,
            plannedDuration: plannedDuration,
            captureInterval: captureInterval,
            sourceFormat: format,
            captureFPS: captureFPS,
            renderFPS: renderFPS,
            resolution: resolution,
            astroPipeline: astroPipeline
        )
    }
}

import Foundation

enum SpatialGuidancePerformanceClass: String, Codable, Equatable, Sendable {
    case constrained
    case standard
    case high
}

struct SpatialGuidanceDeviceCapabilities: Equatable, Sendable {
    let supportsWorldTracking: Bool
    let supportsSceneReconstruction: Bool
    let supportsSceneDepth: Bool
    let performanceClass: SpatialGuidancePerformanceClass
}

enum SpatialGuidanceThermalState: Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical
}

enum SpatialGuidanceAvailability: Equatable, Sendable {
    case available
    case moduleUnavailable
    case hardwareUnavailable
    case performanceUnavailable
    case temporarilyUnavailable
}

enum SpatialGuidanceAvailabilityPolicy {
    static func resolve(
        module: CameraModule,
        capabilities: SpatialGuidanceDeviceCapabilities,
        thermalState: SpatialGuidanceThermalState
    ) -> SpatialGuidanceAvailability {
        guard module == .repeatable else { return .moduleUnavailable }
        guard thermalState != .serious, thermalState != .critical else {
            return .temporarilyUnavailable
        }
        guard capabilities.supportsWorldTracking,
              capabilities.supportsSceneReconstruction,
              capabilities.supportsSceneDepth else {
            return .hardwareUnavailable
        }
        guard capabilities.performanceClass == .high else {
            return .performanceUnavailable
        }
        return .available
    }
}

enum SpatialMappingRequirement: String, CaseIterable, Equatable, Sendable {
    case duration
    case tracking
    case coverage
    case detail
    case keyframes
}

struct SpatialMappingMetrics: Equatable, Sendable {
    let elapsedSeconds: TimeInterval
    let trackingIsNormal: Bool
    let mappedAreaSquareMeters: Double
    let featurePointCount: Int
    let keyframeCount: Int
}

enum SpatialMappingQualityLevel: Equatable, Sendable {
    case insufficient
    case ready
}

struct SpatialMappingQuality: Equatable, Sendable {
    let level: SpatialMappingQualityLevel
    let progress: Double
    let missingRequirements: Set<SpatialMappingRequirement>

    var canSave: Bool { level == .ready }

    static let insufficient = Self(
        level: .insufficient,
        progress: 0,
        missingRequirements: Set(SpatialMappingRequirement.allCases)
    )
    static let ready = Self(level: .ready, progress: 1, missingRequirements: [])
}

enum SpatialMappingQualityEvaluator {
    private static let minimumDuration: TimeInterval = 20
    private static let minimumAreaSquareMeters = 6.0
    private static let minimumFeaturePoints = 900
    private static let minimumKeyframes = 4

    static func evaluate(_ metrics: SpatialMappingMetrics) -> SpatialMappingQuality {
        var missing: Set<SpatialMappingRequirement> = []
        if metrics.elapsedSeconds < minimumDuration { missing.insert(.duration) }
        if !metrics.trackingIsNormal { missing.insert(.tracking) }
        if metrics.mappedAreaSquareMeters < minimumAreaSquareMeters { missing.insert(.coverage) }
        if metrics.featurePointCount < minimumFeaturePoints { missing.insert(.detail) }
        if metrics.keyframeCount < minimumKeyframes { missing.insert(.keyframes) }

        let scores = [
            min(metrics.elapsedSeconds / minimumDuration, 1),
            metrics.trackingIsNormal ? 1 : 0,
            min(metrics.mappedAreaSquareMeters / minimumAreaSquareMeters, 1),
            min(Double(metrics.featurePointCount) / Double(minimumFeaturePoints), 1),
            min(Double(metrics.keyframeCount) / Double(minimumKeyframes), 1)
        ]
        let progress = scores.reduce(0, +) / Double(scores.count)
        return SpatialMappingQuality(
            level: missing.isEmpty ? .ready : .insufficient,
            progress: missing.isEmpty ? 1 : progress,
            missingRequirements: missing
        )
    }
}

enum SpatialGuidanceFailure: String, Codable, Equatable, Sendable {
    case trackingUnavailable
    case relocalizationTimedOut
    case incompatibleReference
    case persistenceFailed
}

enum SpatialGuidancePhase: Equatable, Sendable {
    case idle
    case mapping
    case insufficientCoverage
    case readyToMount
    case saving
    case saved
    case relocalizing
    case positioning
    case aligned
    case failed(SpatialGuidanceFailure)

    var showsGhost: Bool {
        self == .positioning || self == .aligned
    }

    var canOpenCamera: Bool {
        self == .aligned
    }
}

enum SpatialGuidanceEvent: Equatable, Sendable {
    case startMapping
    case mappingEvaluated(SpatialMappingQualityLevel)
    case beginSaving
    case referenceSaved
    case startRelocalization
    case anchorRestored
    case poseEvaluated(isAligned: Bool)
    case fail(SpatialGuidanceFailure)
    case reset
}

enum SpatialGuidanceTransitionError: Error, Equatable {
    case invalid(phase: SpatialGuidancePhase, event: SpatialGuidanceEvent)
}

struct SpatialGuidanceStateMachine: Equatable, Sendable {
    private(set) var phase: SpatialGuidancePhase = .idle

    mutating func send(_ event: SpatialGuidanceEvent) throws {
        let next: SpatialGuidancePhase? = switch (phase, event) {
        case (_, .reset): .idle
        case (.idle, .startMapping), (.saved, .startMapping), (.failed, .startMapping): .mapping
        case (.mapping, .mappingEvaluated(.insufficient)),
             (.insufficientCoverage, .mappingEvaluated(.insufficient)): .insufficientCoverage
        case (.mapping, .mappingEvaluated(.ready)),
             (.insufficientCoverage, .mappingEvaluated(.ready)): .readyToMount
        case (.readyToMount, .mappingEvaluated(.insufficient)): .insufficientCoverage
        case (.readyToMount, .mappingEvaluated(.ready)): .readyToMount
        case (.readyToMount, .beginSaving): .saving
        case (.readyToMount, .referenceSaved), (.saving, .referenceSaved): .saved
        case (.idle, .startRelocalization),
             (.saved, .startRelocalization),
             (.failed, .startRelocalization): .relocalizing
        case (.relocalizing, .anchorRestored): .positioning
        case (.positioning, .poseEvaluated(true)): .aligned
        case (.positioning, .poseEvaluated(false)), (.aligned, .poseEvaluated(false)): .positioning
        case (.aligned, .poseEvaluated(true)): .aligned
        case (_, .fail(let failure)): .failed(failure)
        default: nil
        }
        guard let next else {
            throw SpatialGuidanceTransitionError.invalid(phase: phase, event: event)
        }
        phase = next
    }
}

struct SpatialVector3: Codable, Equatable, Hashable, Sendable {
    var x: Double
    var y: Double
    var z: Double

    static let zero = Self(x: 0, y: 0, z: 0)
}

struct SpatialPoseSample: Codable, Equatable, Hashable, Sendable {
    var translationMeters: SpatialVector3
    var eulerDegrees: SpatialVector3

    static let zero = Self(translationMeters: .zero, eulerDegrees: .zero)
}

struct SpatialPoseEvaluation: Equatable, Sendable {
    let translationDeltaMeters: SpatialVector3
    let rotationDeltaDegrees: SpatialVector3
    let horizontalDistanceMeters: Double
    let verticalDistanceMeters: Double
    let maximumRotationDegrees: Double
    let isAligned: Bool
}

enum SpatialPoseGuidance {
    static let maximumHorizontalDistanceMeters = 0.02
    static let maximumVerticalDistanceMeters = 0.02
    static let maximumRotationDegrees = 1.0

    static func evaluate(
        current: SpatialPoseSample,
        target: SpatialPoseSample
    ) -> SpatialPoseEvaluation {
        let translation = SpatialVector3(
            x: target.translationMeters.x - current.translationMeters.x,
            y: target.translationMeters.y - current.translationMeters.y,
            z: target.translationMeters.z - current.translationMeters.z
        )
        let rotation = SpatialVector3(
            x: shortestAngle(target.eulerDegrees.x - current.eulerDegrees.x),
            y: shortestAngle(target.eulerDegrees.y - current.eulerDegrees.y),
            z: shortestAngle(target.eulerDegrees.z - current.eulerDegrees.z)
        )
        let horizontal = hypot(translation.x, translation.z)
        let vertical = abs(translation.y)
        let maximumRotation = max(abs(rotation.x), abs(rotation.y), abs(rotation.z))
        return SpatialPoseEvaluation(
            translationDeltaMeters: translation,
            rotationDeltaDegrees: rotation,
            horizontalDistanceMeters: horizontal,
            verticalDistanceMeters: vertical,
            maximumRotationDegrees: maximumRotation,
            isAligned: horizontal < maximumHorizontalDistanceMeters
                && vertical < maximumVerticalDistanceMeters
                && maximumRotation < maximumRotationDegrees
        )
    }

    private static func shortestAngle(_ degrees: Double) -> Double {
        var result = degrees.truncatingRemainder(dividingBy: 360)
        if result > 180 { result -= 360 }
        if result < -180 { result += 360 }
        return result
    }
}

enum SpatialCaptureOrientation: String, Codable, Equatable, Sendable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight
}

struct SpatialReferenceManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    let createdAt: Date
    let module: CameraModule
    let deviceModelIdentifier: String
    let cameraLens: RepeatableCameraLens
    let cameraZoomFactor: Double
    let orientation: SpatialCaptureOrientation
    let targetPose: SpatialPoseSample
    let worldMapFileName: String
    let keyframeFileNames: [String]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: UUID,
        createdAt: Date,
        module: CameraModule,
        deviceModelIdentifier: String,
        cameraLens: RepeatableCameraLens,
        cameraZoomFactor: Double,
        orientation: SpatialCaptureOrientation,
        targetPose: SpatialPoseSample,
        worldMapFileName: String,
        keyframeFileNames: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.createdAt = createdAt
        self.module = module
        self.deviceModelIdentifier = deviceModelIdentifier
        self.cameraLens = cameraLens
        self.cameraZoomFactor = cameraZoomFactor
        self.orientation = orientation
        self.targetPose = targetPose
        self.worldMapFileName = worldMapFileName
        self.keyframeFileNames = keyframeFileNames
    }
}

enum SpatialGuidanceVisualState: Equatable, Sendable {
    case noReference
    case referenceSaved
    case unsupported
    case mapping
    case insufficientCoverage
    case readyToMount
    case relocalizing
    case positioning
    case aligned
    case relocalizationFailed
    case incompatibleReference
    case confirmRemap
}

enum SpatialGuidanceAction: Equatable, Sendable {
    case createReference
    case reviewReference
    case remapReference
    case continueWithoutReference
    case retryRelocalization
    case saveReference
    case openCamera
    case cancel
}

enum SpatialGuidanceInterfaceCapabilityPolicy {
    static func actions(for state: SpatialGuidanceVisualState) -> [SpatialGuidanceAction] {
        switch state {
        case .noReference:
            [.createReference, .continueWithoutReference]
        case .referenceSaved:
            [.reviewReference, .remapReference, .continueWithoutReference]
        case .unsupported:
            [.continueWithoutReference]
        case .mapping, .insufficientCoverage:
            [.cancel]
        case .readyToMount:
            [.saveReference, .cancel]
        case .relocalizing:
            [.cancel]
        case .positioning:
            [.cancel]
        case .aligned:
            [.openCamera, .cancel]
        case .relocalizationFailed:
            [.retryRelocalization, .remapReference, .cancel]
        case .incompatibleReference:
            [.remapReference, .continueWithoutReference]
        case .confirmRemap:
            [.remapReference, .cancel]
        }
    }
}

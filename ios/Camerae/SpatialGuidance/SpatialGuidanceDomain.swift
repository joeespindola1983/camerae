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

enum SpatialTripodVisualizationComponent: Equatable, Hashable, Sendable {
    case axis
}

enum SpatialTripodVisualizationPolicy {
    static let visibleComponents: Set<SpatialTripodVisualizationComponent> = [.axis]
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

struct SpatialGuidanceProjectStatusPresentation: Equatable, Sendable {
    let status: String
    let title: String
    let detail: String

    init(availability: SpatialGuidanceAvailability, hasReference: Bool) {
        switch availability {
        case .available:
            status = hasReference ? "POSIÇÃO SALVA" : "NÃO CONFIGURADO"
            title = hasReference ? "Tripé de referência" : "Mapeamento espacial"
            detail = hasReference
                ? "Navegue pela cena para reencontrar a base e a direção da câmera."
                : "Mapeie o local, marque o centro da base e indique a direção da câmera."
        case .temporarilyUnavailable:
            status = "PAUSA TEMPORÁRIA"
            title = "Aguarde o iPhone esfriar"
            detail = hasReference
                ? "A referência continua salva. A navegação será liberada quando o iPhone esfriar."
                : "O mapeamento será liberado quando o iPhone esfriar."
        case .hardwareUnavailable, .performanceUnavailable:
            status = "INCOMPATÍVEL"
            title = "Este iPhone não pode usar o guia"
            detail = hasReference
                ? "A referência continua salva. Use um iPhone compatível ou prossiga sem o guia."
                : "O timelapse continua disponível sem orientação espacial."
        case .moduleUnavailable:
            status = "INDISPONÍVEL"
            title = "Orientação espacial indisponível"
            detail = "Por enquanto, este recurso está disponível somente no Repeatable."
        }
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
    let canDefineScene: Bool

    var canSave: Bool { level == .ready }

    static let insufficient = Self(
        level: .insufficient,
        progress: 0,
        missingRequirements: Set(SpatialMappingRequirement.allCases),
        canDefineScene: false
    )
    static let ready = Self(
        level: .ready,
        progress: 1,
        missingRequirements: [],
        canDefineScene: true
    )
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
            missingRequirements: missing,
            canDefineScene: metrics.elapsedSeconds >= 12
                && metrics.trackingIsNormal
                && metrics.mappedAreaSquareMeters >= 2
                && metrics.featurePointCount >= 500
                && metrics.keyframeCount >= 3
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
    case initializingMapping
    case readyToStartMapping
    case mapping
    case insufficientCoverage
    case reviewingScene
    case selectingTripodBase
    case tripodBaseSelected
    case selectingTripodDirection
    case tripodDirectionSelected
    case readyToMount
    case saving
    case saved
    case relocalizing
    case positioning
    case aligned
    case failed(SpatialGuidanceFailure)

    var showsGhost: Bool {
        false
    }

    var canOpenCamera: Bool {
        self == .aligned
    }

    var showsLiveCamera: Bool {
        switch self {
        case .readyToStartMapping, .mapping, .insufficientCoverage, .reviewingScene,
             .selectingTripodBase, .tripodBaseSelected, .readyToMount,
             .selectingTripodDirection, .tripodDirectionSelected,
             .relocalizing, .positioning, .aligned:
            true
        default:
            false
        }
    }

    var visualState: SpatialGuidanceVisualState {
        switch self {
        case .idle, .initializingMapping:
            .noReference
        case .readyToStartMapping:
            .readyToStartMapping
        case .mapping:
            .mapping
        case .insufficientCoverage:
            .insufficientCoverage
        case .reviewingScene:
            .reviewingScene
        case .selectingTripodBase:
            .selectingTripodBase
        case .tripodBaseSelected:
            .tripodBaseSelected
        case .selectingTripodDirection:
            .selectingTripodDirection
        case .tripodDirectionSelected:
            .tripodDirectionSelected
        case .readyToMount, .saving:
            .readyToMount
        case .saved:
            .referenceSaved
        case .relocalizing:
            .relocalizing
        case .positioning:
            .positioning
        case .aligned:
            .aligned
        case .failed(.incompatibleReference):
            .incompatibleReference
        case .failed:
            .relocalizationFailed
        }
    }
}

enum SpatialGuidanceEvent: Equatable, Sendable {
    case startMapping
    case mappingSessionReady
    case beginSceneCapture
    case mappingEvaluated(SpatialMappingQualityLevel)
    case freezeScene
    case tripodBaseSelected
    case confirmTripodBase
    case tripodDirectionSelected
    case confirmTripodDirection
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
        case (.idle, .startMapping), (.saved, .startMapping),
             (.failed, .startMapping): .initializingMapping
        case (.initializingMapping, .mappingSessionReady): .readyToStartMapping
        case (.readyToStartMapping, .beginSceneCapture): .mapping
        case (.mapping, .mappingEvaluated(.insufficient)),
             (.insufficientCoverage, .mappingEvaluated(.insufficient)): .insufficientCoverage
        case (.mapping, .mappingEvaluated(.ready)),
             (.insufficientCoverage, .mappingEvaluated(.ready)): .reviewingScene
        case (.mapping, .freezeScene),
             (.insufficientCoverage, .freezeScene): .selectingTripodBase
        case (.reviewingScene, .mappingEvaluated(.insufficient)): .insufficientCoverage
        case (.reviewingScene, .mappingEvaluated(.ready)): .reviewingScene
        case (.reviewingScene, .freezeScene): .selectingTripodBase
        case (.selectingTripodBase, .tripodBaseSelected),
             (.tripodBaseSelected, .tripodBaseSelected): .tripodBaseSelected
        case (.tripodBaseSelected, .confirmTripodBase): .selectingTripodDirection
        case (.selectingTripodDirection, .tripodDirectionSelected),
             (.tripodDirectionSelected, .tripodDirectionSelected): .tripodDirectionSelected
        case (.tripodDirectionSelected, .confirmTripodDirection): .readyToMount
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

struct SpatialRGBAColor: Codable, Equatable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    func clamped() -> Self {
        .init(
            red: min(max(red, 0), 1),
            green: min(max(green, 0), 1),
            blue: min(max(blue, 0), 1),
            opacity: min(max(opacity, 0.05), 1)
        )
    }

    static func white(opacity: Double) -> Self {
        .init(red: 1, green: 1, blue: 1, opacity: opacity)
    }

    static func black(opacity: Double) -> Self {
        .init(red: 0, green: 0, blue: 0, opacity: opacity)
    }

    var restricted: Self {
        let isWhite = (red + green + blue) / 3 >= 0.5
        let restrictedOpacity: Double = if opacity < 0.375 {
            0.25
        } else if opacity < 0.75 {
            0.5
        } else {
            1
        }
        return isWhite
            ? .white(opacity: restrictedOpacity)
            : .black(opacity: restrictedOpacity)
    }
}

struct SpatialGuidanceAppearance: Codable, Equatable, Hashable, Sendable {
    var mesh: SpatialRGBAColor
    var tripod: SpatialRGBAColor
    var camera: SpatialRGBAColor

    static let `default` = Self(
        mesh: .white(opacity: 0.5),
        tripod: .black(opacity: 0.5),
        camera: .black(opacity: 1)
    )

    var restricted: Self {
        .init(
            mesh: mesh.restricted,
            tripod: tripod.restricted,
            camera: camera.restricted
        )
    }
}

enum SpatialCreationContrast: Equatable, Sendable {
    case lightMesh
    case darkMesh

    init(appearance: SpatialGuidanceAppearance) {
        self = appearance.mesh.red >= 0.5 ? .lightMesh : .darkMesh
    }

    var appearance: SpatialGuidanceAppearance {
        switch self {
        case .lightMesh:
            .init(
                mesh: .white(opacity: 0.5),
                tripod: .black(opacity: 0.5),
                camera: .black(opacity: 1)
            )
        case .darkMesh:
            .init(
                mesh: .black(opacity: 0.5),
                tripod: .white(opacity: 0.5),
                camera: .white(opacity: 1)
            )
        }
    }

    var toggled: Self {
        self == .lightMesh ? .darkMesh : .lightMesh
    }
}

enum SpatialTripodDirection {
    static let handleDistanceMeters = 0.45

    static func point(
        base: SpatialVector3,
        toward candidate: SpatialVector3
    ) -> SpatialVector3? {
        let dx = candidate.x - base.x
        let dz = candidate.z - base.z
        let distance = hypot(dx, dz)
        guard distance > 0.001 else { return nil }
        return SpatialVector3(
            x: base.x + (dx / distance) * handleDistanceMeters,
            y: base.y,
            z: base.z + (dz / distance) * handleDistanceMeters
        )
    }
}

enum SpatialStandardTripod {
    static let heightMeters = 1.0
    static let legRadiusMeters = 0.38
    static let legHubHeightMeters = 0.72

    static func footPoints(
        base: SpatialVector3,
        direction: SpatialVector3,
        legRadius: Double = legRadiusMeters
    ) -> [SpatialVector3]? {
        let dx = direction.x - base.x
        let dz = direction.z - base.z
        guard hypot(dx, dz) > 0.001 else { return nil }
        let heading = atan2(dz, dx)
        return (0..<3).map { index in
            let angle = heading + Double(index) * (2 * .pi / 3)
            return SpatialVector3(
                x: base.x + cos(angle) * legRadius,
                y: base.y,
                z: base.z + sin(angle) * legRadius
            )
        }
    }
}

enum SpatialTripodHeightEstimator {
    static let sampleRadiusMeters = 0.24
    static let minimumHeightMeters = 0.55
    static let maximumHeightMeters = 1.65
    static let minimumSampleCount = 12

    static func estimate(
        base: SpatialVector3,
        points: [SpatialVector3]
    ) -> Double? {
        let heights = points.compactMap { point -> Double? in
            guard hypot(point.x - base.x, point.z - base.z) <= sampleRadiusMeters else {
                return nil
            }
            let height = point.y - base.y
            return height >= 0.08 ? height : nil
        }.sorted()
        guard heights.count >= minimumSampleCount else { return nil }
        let percentileIndex = min(
            heights.count - 1,
            Int((Double(heights.count - 1) * 0.95).rounded())
        )
        return min(max(heights[percentileIndex], minimumHeightMeters), maximumHeightMeters)
    }
}

enum SpatialTripodFootEstimator {
    private static let sectorCount = 24
    private static let minimumPointsPerFoot = 4
    private static let minimumRadiusMeters = 0.10
    private static let maximumRadiusMeters = 0.55
    private static let minimumHeightMeters = 0.025
    private static let maximumHeightMeters = 0.16

    static func estimate(
        base: SpatialVector3,
        points: [SpatialVector3]
    ) -> [SpatialVector3]? {
        let candidates = points.compactMap { point -> (point: SpatialVector3, sector: Int)? in
            let height = point.y - base.y
            let dx = point.x - base.x
            let dz = point.z - base.z
            let radius = hypot(dx, dz)
            guard height >= minimumHeightMeters,
                  height <= maximumHeightMeters,
                  radius >= minimumRadiusMeters,
                  radius <= maximumRadiusMeters else {
                return nil
            }
            let normalizedAngle = (atan2(dz, dx) + 2 * .pi)
                .truncatingRemainder(dividingBy: 2 * .pi)
            let sector = min(
                sectorCount - 1,
                Int((normalizedAngle / (2 * .pi)) * Double(sectorCount))
            )
            return (point, sector)
        }
        guard candidates.count >= minimumPointsPerFoot * 3 else { return nil }

        var counts = Array(repeating: 0, count: sectorCount)
        candidates.forEach { counts[$0.sector] += 1 }
        let rankedSectors = counts.indices.sorted { counts[$0] > counts[$1] }
        var selected: [Int] = []
        for sector in rankedSectors where counts[sector] >= minimumPointsPerFoot {
            guard selected.allSatisfy({
                circularSectorDistance($0, sector) >= 4
            }) else {
                continue
            }
            selected.append(sector)
            if selected.count == 3 { break }
        }
        guard selected.count == 3 else { return nil }

        let feet = selected.compactMap { sector -> SpatialVector3? in
            let cluster = candidates.filter {
                circularSectorDistance($0.sector, sector) <= 1
            }.map(\.point)
            guard cluster.count >= minimumPointsPerFoot else { return nil }
            return SpatialVector3(
                x: cluster.map(\.x).reduce(0, +) / Double(cluster.count),
                y: base.y,
                z: cluster.map(\.z).reduce(0, +) / Double(cluster.count)
            )
        }
        return feet.count == 3 ? feet : nil
    }

    private static func circularSectorDistance(_ lhs: Int, _ rhs: Int) -> Int {
        let direct = abs(lhs - rhs)
        return min(direct, sectorCount - direct)
    }
}

enum SpatialMeshVisibilityPolicy {
    static func showsWireframe(during phase: SpatialGuidancePhase) -> Bool {
        switch phase {
        case .readyToStartMapping, .mapping, .insufficientCoverage, .reviewingScene:
            true
        default:
            false
        }
    }
}

struct SpatialTripodDetection: Equatable, Sendable {
    let center: SpatialVector3
    let feet: [SpatialVector3]
    let heightMeters: Double
    let confidence: Double
}

struct SpatialObservationRay: Equatable, Sendable {
    let origin: SpatialVector3
    let direction: SpatialVector3
}

struct SpatialTripodCenterEstimate: Equatable, Sendable {
    let center: SpatialVector3
    let confidence: Double
    let supportingRayCount: Int
}

enum SpatialTripodCenterEvidence: Equatable, Sendable {
    case mesh
    case viewingRays
    case cameraPath
}

struct SpatialTripodCenterSuggestion: Equatable, Sendable {
    let center: SpatialVector3
    let feet: [SpatialVector3]?
    let heightMeters: Double
    let confidence: Double
    let evidence: SpatialTripodCenterEvidence
}

enum SpatialTripodCenterResolver {
    static func resolve(
        meshDetection: SpatialTripodDetection?,
        rayEstimate: SpatialTripodCenterEstimate?,
        traversalCenter: SpatialVector3?,
        floorY: Double
    ) -> SpatialTripodCenterSuggestion? {
        if let meshDetection {
            return .init(
                center: meshDetection.center,
                feet: meshDetection.feet,
                heightMeters: meshDetection.heightMeters,
                confidence: meshDetection.confidence,
                evidence: .mesh
            )
        }
        if let rayEstimate {
            return .init(
                center: .init(
                    x: rayEstimate.center.x,
                    y: floorY,
                    z: rayEstimate.center.z
                ),
                feet: nil,
                heightMeters: SpatialStandardTripod.heightMeters,
                confidence: rayEstimate.confidence,
                evidence: .viewingRays
            )
        }
        guard let traversalCenter else { return nil }
        return .init(
            center: .init(x: traversalCenter.x, y: floorY, z: traversalCenter.z),
            feet: nil,
            heightMeters: SpatialStandardTripod.heightMeters,
            confidence: 0.35,
            evidence: .cameraPath
        )
    }
}

enum SpatialTripodCenterEstimator {
    private static let minimumRayCount = 6
    private static let minimumIntersectionAngle = 10 * Double.pi / 180
    private static let inlierDistanceMeters = 0.28

    static func estimate(
        rays: [SpatialObservationRay],
        floorY: Double
    ) -> SpatialTripodCenterEstimate? {
        let normalized = rays.compactMap(normalizedRay)
        guard normalized.count >= minimumRayCount else { return nil }
        var bestPoint: SpatialVector3?
        var bestInliers: [NormalizedRay] = []
        var bestResidual = Double.greatestFiniteMagnitude

        for first in 0..<(normalized.count - 1) {
            for second in (first + 1)..<normalized.count {
                guard let point = intersection(normalized[first], normalized[second]) else {
                    continue
                }
                let inliers = normalized.filter { ray in
                    isInFront(point, of: ray)
                        && perpendicularDistance(from: point, to: ray) <= inlierDistanceMeters
                }
                let residual = median(
                    inliers.map { perpendicularDistance(from: point, to: $0) }
                )
                if inliers.count > bestInliers.count
                    || (inliers.count == bestInliers.count && residual < bestResidual) {
                    bestPoint = point
                    bestInliers = inliers
                    bestResidual = residual
                }
            }
        }

        let minimumInliers = max(5, Int(ceil(Double(normalized.count) * 0.45)))
        guard bestPoint != nil,
              bestInliers.count >= minimumInliers,
              let refined = leastSquaresIntersection(bestInliers, floorY: floorY) else {
            return nil
        }
        let residual = median(
            bestInliers.map { perpendicularDistance(from: refined, to: $0) }
        )
        let inlierRatio = Double(bestInliers.count) / Double(normalized.count)
        let residualScore = max(0, 1 - residual / inlierDistanceMeters)
        return SpatialTripodCenterEstimate(
            center: refined,
            confidence: min(1, inlierRatio * 0.70 + residualScore * 0.30),
            supportingRayCount: bestInliers.count
        )
    }

    private static func normalizedRay(_ ray: SpatialObservationRay) -> NormalizedRay? {
        let length = hypot(ray.direction.x, ray.direction.z)
        guard length > 0.001 else { return nil }
        return NormalizedRay(
            originX: ray.origin.x,
            originZ: ray.origin.z,
            directionX: ray.direction.x / length,
            directionZ: ray.direction.z / length
        )
    }

    private static func intersection(
        _ lhs: NormalizedRay,
        _ rhs: NormalizedRay
    ) -> SpatialVector3? {
        let cross = lhs.directionX * rhs.directionZ - lhs.directionZ * rhs.directionX
        guard abs(cross) >= sin(minimumIntersectionAngle) else { return nil }
        let deltaX = rhs.originX - lhs.originX
        let deltaZ = rhs.originZ - lhs.originZ
        let lhsDistance = (deltaX * rhs.directionZ - deltaZ * rhs.directionX) / cross
        let rhsDistance = (deltaX * lhs.directionZ - deltaZ * lhs.directionX) / cross
        guard lhsDistance >= 0.25,
              rhsDistance >= 0.25,
              lhsDistance <= 4.5,
              rhsDistance <= 4.5 else {
            return nil
        }
        return .init(
            x: lhs.originX + lhs.directionX * lhsDistance,
            y: 0,
            z: lhs.originZ + lhs.directionZ * lhsDistance
        )
    }

    private static func leastSquaresIntersection(
        _ rays: [NormalizedRay],
        floorY: Double
    ) -> SpatialVector3? {
        var a00 = 0.0
        var a01 = 0.0
        var a11 = 0.0
        var b0 = 0.0
        var b1 = 0.0
        for ray in rays {
            let normalX = -ray.directionZ
            let normalZ = ray.directionX
            let constant = normalX * ray.originX + normalZ * ray.originZ
            a00 += normalX * normalX
            a01 += normalX * normalZ
            a11 += normalZ * normalZ
            b0 += normalX * constant
            b1 += normalZ * constant
        }
        let determinant = a00 * a11 - a01 * a01
        guard abs(determinant) > 0.0001 else { return nil }
        return .init(
            x: (b0 * a11 - b1 * a01) / determinant,
            y: floorY,
            z: (a00 * b1 - a01 * b0) / determinant
        )
    }

    private static func perpendicularDistance(
        from point: SpatialVector3,
        to ray: NormalizedRay
    ) -> Double {
        let deltaX = point.x - ray.originX
        let deltaZ = point.z - ray.originZ
        return abs(deltaX * ray.directionZ - deltaZ * ray.directionX)
    }

    private static func isInFront(
        _ point: SpatialVector3,
        of ray: NormalizedRay
    ) -> Bool {
        let deltaX = point.x - ray.originX
        let deltaZ = point.z - ray.originZ
        let distance = deltaX * ray.directionX + deltaZ * ray.directionZ
        return distance >= 0.25 && distance <= 4.5
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return .greatestFiniteMagnitude }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    private struct NormalizedRay {
        let originX: Double
        let originZ: Double
        let directionX: Double
        let directionZ: Double
    }
}

enum SpatialTripodDetector {
    private static let clusterCellMeters = 0.055
    private static let minimumClusterPoints = 4
    private static let searchRadiusMeters = 1.35
    private static let columnRadiusMeters = 0.17

    static func detect(
        points: [SpatialVector3],
        floorY: Double,
        searchCenter: SpatialVector3?
    ) -> SpatialTripodDetection? {
        let lowPoints = points.filter { point in
            let height = point.y - floorY
            guard height >= 0.025, height <= 0.18 else { return false }
            guard let searchCenter else { return true }
            return hypot(point.x - searchCenter.x, point.z - searchCenter.z)
                <= searchRadiusMeters
        }
        let candidates = Array(
            clusters(from: lowPoints, floorY: floorY)
                .filter { $0.pointCount >= minimumClusterPoints && $0.radiusMeters <= 0.10 }
                .sorted { lhs, rhs in
                    let lhsDistance = searchCenter.map {
                        hypot(lhs.center.x - $0.x, lhs.center.z - $0.z)
                    } ?? 0
                    let rhsDistance = searchCenter.map {
                        hypot(rhs.center.x - $0.x, rhs.center.z - $0.z)
                    } ?? 0
                    return abs(lhsDistance - rhsDistance) > 0.08
                        ? lhsDistance < rhsDistance
                        : lhs.pointCount > rhs.pointCount
                }
                .prefix(18)
        )
        guard candidates.count >= 3 else { return nil }

        var best: SpatialTripodDetection?
        for first in 0..<(candidates.count - 2) {
            for second in (first + 1)..<(candidates.count - 1) {
                for third in (second + 1)..<candidates.count {
                    let feet = [
                        candidates[first].center,
                        candidates[second].center,
                        candidates[third].center,
                    ]
                    guard let detection = evaluate(
                        feet: feet,
                        points: points,
                        floorY: floorY,
                        searchCenter: searchCenter
                    ) else { continue }
                    if best == nil || detection.confidence > best?.confidence ?? 0 {
                        best = detection
                    }
                }
            }
        }
        return best
    }

    private static func evaluate(
        feet: [SpatialVector3],
        points: [SpatialVector3],
        floorY: Double,
        searchCenter: SpatialVector3?
    ) -> SpatialTripodDetection? {
        let center = SpatialVector3(
            x: feet.map(\.x).reduce(0, +) / 3,
            y: floorY,
            z: feet.map(\.z).reduce(0, +) / 3
        )
        let radii = feet.map { hypot($0.x - center.x, $0.z - center.z) }
        let meanRadius = radii.reduce(0, +) / 3
        guard meanRadius >= 0.15, meanRadius <= 0.62 else { return nil }
        let radiusSpread = (radii.max() ?? meanRadius) - (radii.min() ?? meanRadius)
        guard radiusSpread <= meanRadius * 0.30 else { return nil }

        let angles = feet.map {
            (atan2($0.z - center.z, $0.x - center.x) + 2 * .pi)
                .truncatingRemainder(dividingBy: 2 * .pi)
        }.sorted()
        let gaps = [
            angles[1] - angles[0],
            angles[2] - angles[1],
            angles[0] + 2 * .pi - angles[2],
        ]
        let minimumGap = 75 * Double.pi / 180
        let maximumGap = 165 * Double.pi / 180
        guard gaps.allSatisfy({ $0 >= minimumGap && $0 <= maximumGap }) else { return nil }

        let columnPoints = points.filter { point in
            let height = point.y - floorY
            return height >= 0.08
                && height <= SpatialTripodHeightEstimator.maximumHeightMeters
                && hypot(point.x - center.x, point.z - center.z) <= columnRadiusMeters
        }
        guard columnPoints.count >= SpatialTripodHeightEstimator.minimumSampleCount,
              let height = SpatialTripodHeightEstimator.estimate(base: center, points: points),
              height >= 0.55 else {
            return nil
        }

        let radiusScore = max(0, 1 - radiusSpread / meanRadius)
        let idealGap = 2 * Double.pi / 3
        let angleError = gaps.map { abs($0 - idealGap) / idealGap }.reduce(0, +) / 3
        let angleScore = max(0, 1 - angleError)
        let columnScore = min(Double(columnPoints.count) / 48, 1)
        let proximityScore: Double = if let searchCenter {
            max(
                0,
                1 - hypot(center.x - searchCenter.x, center.z - searchCenter.z)
                    / searchRadiusMeters
            )
        } else {
            0.5
        }
        let confidence = radiusScore * 0.30
            + angleScore * 0.20
            + columnScore * 0.35
            + proximityScore * 0.15
        guard confidence >= 0.72 else { return nil }
        return SpatialTripodDetection(
            center: center,
            feet: feet.map { .init(x: $0.x, y: floorY, z: $0.z) },
            heightMeters: height,
            confidence: confidence
        )
    }

    private static func clusters(
        from points: [SpatialVector3],
        floorY: Double
    ) -> [FootCluster] {
        let buckets = Dictionary(grouping: points) { point in
            GridCell(
                x: Int(floor(point.x / clusterCellMeters)),
                z: Int(floor(point.z / clusterCellMeters))
            )
        }
        var unvisited = Set(buckets.keys)
        var result: [FootCluster] = []
        while let seed = unvisited.first {
            var pending = [seed]
            var clusterPoints: [SpatialVector3] = []
            unvisited.remove(seed)
            while let cell = pending.popLast() {
                clusterPoints.append(contentsOf: buckets[cell] ?? [])
                for xOffset in -1...1 {
                    for zOffset in -1...1 {
                        let neighbor = GridCell(x: cell.x + xOffset, z: cell.z + zOffset)
                        if unvisited.remove(neighbor) != nil {
                            pending.append(neighbor)
                        }
                    }
                }
            }
            guard clusterPoints.count >= minimumClusterPoints else { continue }
            let centerX = clusterPoints.map(\.x).reduce(0, +) / Double(clusterPoints.count)
            let centerZ = clusterPoints.map(\.z).reduce(0, +) / Double(clusterPoints.count)
            let radius = clusterPoints.map {
                hypot($0.x - centerX, $0.z - centerZ)
            }.max() ?? 0
            result.append(
                FootCluster(
                    center: .init(x: centerX, y: floorY, z: centerZ),
                    pointCount: clusterPoints.count,
                    radiusMeters: radius
                )
            )
        }
        return result
    }

    private struct GridCell: Hashable {
        let x: Int
        let z: Int
    }

    private struct FootCluster {
        let center: SpatialVector3
        let pointCount: Int
        let radiusMeters: Double
    }
}

struct SpatialPoseSample: Codable, Equatable, Hashable, Sendable {
    var translationMeters: SpatialVector3
    var eulerDegrees: SpatialVector3

    static let zero = Self(translationMeters: .zero, eulerDegrees: .zero)
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
    let tripodBaseCenter: SpatialVector3?
    let tripodDirectionPoint: SpatialVector3?
    let tripodHeightMeters: Double?
    let tripodLegRadiusMeters: Double?
    let tripodFootPoints: [SpatialVector3]?
    let appearance: SpatialGuidanceAppearance?
    let targetPose: SpatialPoseSample?
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
        tripodBaseCenter: SpatialVector3? = nil,
        tripodDirectionPoint: SpatialVector3? = nil,
        tripodHeightMeters: Double? = nil,
        tripodLegRadiusMeters: Double? = nil,
        tripodFootPoints: [SpatialVector3]? = nil,
        appearance: SpatialGuidanceAppearance? = nil,
        targetPose: SpatialPoseSample? = nil,
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
        self.tripodBaseCenter = tripodBaseCenter
        self.tripodDirectionPoint = tripodDirectionPoint
        self.tripodHeightMeters = tripodHeightMeters
        self.tripodLegRadiusMeters = tripodLegRadiusMeters
        self.tripodFootPoints = tripodFootPoints
        self.appearance = appearance
        self.targetPose = targetPose
        self.worldMapFileName = worldMapFileName
        self.keyframeFileNames = keyframeFileNames
    }

    func replacingAppearance(
        _ appearance: SpatialGuidanceAppearance
    ) -> SpatialReferenceManifest {
        .init(
            schemaVersion: schemaVersion,
            id: id,
            createdAt: createdAt,
            module: module,
            deviceModelIdentifier: deviceModelIdentifier,
            cameraLens: cameraLens,
            cameraZoomFactor: cameraZoomFactor,
            orientation: orientation,
            tripodBaseCenter: tripodBaseCenter,
            tripodDirectionPoint: tripodDirectionPoint,
            tripodHeightMeters: tripodHeightMeters,
            tripodLegRadiusMeters: tripodLegRadiusMeters,
            tripodFootPoints: tripodFootPoints,
            appearance: appearance.restricted,
            targetPose: targetPose,
            worldMapFileName: worldMapFileName,
            keyframeFileNames: keyframeFileNames
        )
    }
}

enum SpatialGuidanceVisualState: Equatable, Sendable {
    case noReference
    case referenceSaved
    case unsupported
    case readyToStartMapping
    case mapping
    case insufficientCoverage
    case reviewingScene
    case selectingTripodBase
    case tripodBaseSelected
    case selectingTripodDirection
    case tripodDirectionSelected
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
    case navigateScene
    case reviewReference
    case remapReference
    case beginSceneCapture
    case restartSceneCapture
    case continueWithoutReference
    case retryRelocalization
    case saveReference
    case defineScene
    case continueMapping
    case selectTripodBase
    case adjustTripodBase
    case confirmTripodBase
    case selectTripodDirection
    case adjustTripodDirection
    case confirmTripodDirection
    case openCamera
    case completeNavigation
    case cancel
}

enum SpatialGuidanceInterfaceCapabilityPolicy {
    static func actions(for state: SpatialGuidanceVisualState) -> [SpatialGuidanceAction] {
        switch state {
        case .noReference:
            [.createReference, .continueWithoutReference]
        case .referenceSaved:
            [.navigateScene, .reviewReference, .remapReference]
        case .unsupported:
            [.continueWithoutReference]
        case .readyToStartMapping:
            [.beginSceneCapture, .restartSceneCapture, .cancel]
        case .mapping, .insufficientCoverage:
            [.cancel]
        case .reviewingScene:
            [.defineScene, .continueMapping, .cancel]
        case .selectingTripodBase:
            [.selectTripodBase, .cancel]
        case .tripodBaseSelected:
            [.adjustTripodBase, .confirmTripodBase, .cancel]
        case .selectingTripodDirection:
            [.selectTripodDirection, .cancel]
        case .tripodDirectionSelected:
            [.adjustTripodDirection, .confirmTripodDirection, .cancel]
        case .readyToMount:
            [.saveReference, .cancel]
        case .relocalizing:
            [.cancel]
        case .positioning:
            [.completeNavigation, .cancel]
        case .aligned:
            [.completeNavigation, .cancel]
        case .relocalizationFailed:
            [.retryRelocalization, .remapReference, .cancel]
        case .incompatibleReference:
            [.remapReference, .continueWithoutReference]
        case .confirmRemap:
            [.remapReference, .cancel]
        }
    }
}

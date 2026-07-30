import ARKit
import Foundation
import SceneKit
import SwiftUI
import UIKit

private let spatialGuidanceTargetAnchorName = "camerae.spatial.target"

enum SpatialGuidanceSystemCapabilityProvider {
    static var capabilities: SpatialGuidanceDeviceCapabilities {
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let performanceClass: SpatialGuidancePerformanceClass =
            ProcessInfo.processInfo.processorCount >= 6 && physicalMemory >= 4_000_000_000
                ? .high
                : .constrained
        return SpatialGuidanceDeviceCapabilities(
            supportsWorldTracking: ARWorldTrackingConfiguration.isSupported,
            supportsSceneReconstruction: ARWorldTrackingConfiguration.supportsSceneReconstruction(
                .meshWithClassification
            ),
            supportsSceneDepth: ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
                || ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth),
            performanceClass: performanceClass
        )
    }

    static var thermalState: SpatialGuidanceThermalState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .critical
        }
    }

    static func availability(for module: CameraModule) -> SpatialGuidanceAvailability {
        SpatialGuidanceAvailabilityPolicy.resolve(
            module: module,
            capabilities: capabilities,
            thermalState: thermalState
        )
    }
}

enum SpatialGuidanceFlowMode: Identifiable {
    case createReference
    case relocalize(SpatialReferenceBundle)

    var id: String {
        switch self {
        case .createReference: "create"
        case .relocalize(let reference): "relocalize-\(reference.manifest.id.uuidString)"
        }
    }
}

@MainActor
final class SpatialGuidanceSessionModel: NSObject, ObservableObject {
    @Published private(set) var phase: SpatialGuidancePhase = .idle
    @Published private(set) var mappingQuality = SpatialMappingQuality.insufficient
    @Published private(set) var poseEvaluation: SpatialPoseEvaluation?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isBusy = false

    let sceneView: ARSCNView

    private var machine = SpatialGuidanceStateMachine()
    private var mappingStartedAt: Date?
    private var observedCameraPositions: [SIMD3<Float>] = []
    private var keyframes: [Data] = []
    private var lastKeyframeAt: Date?
    private var reference: SpatialReferenceBundle?
    private var targetAnchorRestored = false
    private var ghostNode: SCNNode?

    override init() {
        sceneView = ARSCNView(frame: .zero)
        super.init()
        sceneView.automaticallyUpdatesLighting = true
        sceneView.antialiasingMode = .multisampling4X
        sceneView.scene = SCNScene()
        sceneView.session.delegate = self
        sceneView.delegate = self
    }

    func startMapping() {
        resetRuntime()
        do {
            try machine.send(.startMapping)
            phase = machine.phase
        } catch {
            fail(.trackingUnavailable, message: error.localizedDescription)
            return
        }
        mappingStartedAt = .now
        let configuration = makeConfiguration()
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func startRelocalization(reference: SpatialReferenceBundle) {
        resetRuntime()
        self.reference = reference
        do {
            try machine.send(.startRelocalization)
            phase = machine.phase
            let worldMap = try Self.decodeWorldMap(reference.worldMapData)
            let configuration = makeConfiguration()
            configuration.initialWorldMap = worldMap
            sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            mappingStartedAt = .now
        } catch {
            fail(.incompatibleReference, message: "O mapa espacial salvo não pôde ser carregado.")
        }
    }

    func saveReference(
        store: SpatialReferenceStore,
        configuration: CameraeNextCaptureConfiguration,
        orientation: SpatialCaptureOrientation
    ) async throws -> SpatialReferenceManifest {
        guard mappingQuality.canSave,
              let frame = sceneView.session.currentFrame else {
            throw SpatialGuidanceRuntimeError.mappingNotReady
        }
        isBusy = true
        defer { isBusy = false }
        try machine.send(.beginSaving)
        phase = machine.phase

        let targetTransform = frame.camera.transform
        sceneView.session.add(
            anchor: ARAnchor(name: spatialGuidanceTargetAnchorName, transform: targetTransform)
        )
        try await Task.sleep(for: .milliseconds(300))
        let worldMap = try await currentWorldMap()
        let mapData = try NSKeyedArchiver.archivedData(
            withRootObject: worldMap,
            requiringSecureCoding: true
        )
        if let snapshot = snapshotJPEG(), !keyframes.contains(snapshot) {
            keyframes.append(snapshot)
        }
        let names = keyframes.indices.map { index in
            String(format: "guide-%04d.jpg", index + 1)
        }
        let manifest = SpatialReferenceManifest(
            id: UUID(),
            createdAt: .now,
            module: .repeatable,
            deviceModelIdentifier: Self.deviceModelIdentifier,
            cameraLens: configuration.cameraLens,
            cameraZoomFactor: configuration.cameraZoomFactor,
            orientation: orientation,
            targetPose: Self.poseSample(from: targetTransform),
            worldMapFileName: "world_map.bin",
            keyframeFileNames: names
        )
        try store.save(
            manifest: manifest,
            worldMapData: mapData,
            keyframes: keyframes
        )
        try machine.send(.referenceSaved)
        phase = machine.phase
        return manifest
    }

    func stop() {
        sceneView.session.pause()
        sceneView.delegate = nil
        sceneView.session.delegate = nil
    }

    func reportPersistenceFailure(_ error: Error) {
        fail(
            .persistenceFailed,
            message: "Não foi possível salvar o guia espacial: \(error.localizedDescription)"
        )
    }

    private func makeConfiguration() -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = [.horizontal]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            configuration.sceneReconstruction = .meshWithClassification
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }
        configuration.environmentTexturing = .automatic
        return configuration
    }

    private func resetRuntime() {
        sceneView.session.pause()
        sceneView.scene.rootNode.childNodes.forEach { $0.removeFromParentNode() }
        machine = SpatialGuidanceStateMachine()
        phase = .idle
        mappingQuality = .insufficient
        poseEvaluation = nil
        errorMessage = nil
        mappingStartedAt = nil
        observedCameraPositions = []
        keyframes = []
        lastKeyframeAt = nil
        reference = nil
        targetAnchorRestored = false
        ghostNode = nil
        sceneView.delegate = self
        sceneView.session.delegate = self
    }

    private func updateMapping(frame: ARFrame) {
        let position = SIMD3<Float>(
            frame.camera.transform.columns.3.x,
            frame.camera.transform.columns.3.y,
            frame.camera.transform.columns.3.z
        )
        observedCameraPositions.append(position)
        if observedCameraPositions.count > 600 {
            observedCameraPositions.removeFirst(observedCameraPositions.count - 600)
        }
        let xs = observedCameraPositions.map(\.x)
        let zs = observedCameraPositions.map(\.z)
        let width = Double((xs.max() ?? position.x) - (xs.min() ?? position.x))
        let depth = Double((zs.max() ?? position.z) - (zs.min() ?? position.z))
        let traversedArea = max(width * depth * 6, max(width, depth) * 3)
        let metrics = SpatialMappingMetrics(
            elapsedSeconds: Date.now.timeIntervalSince(mappingStartedAt ?? .now),
            trackingIsNormal: frame.camera.trackingState.isNormal,
            mappedAreaSquareMeters: traversedArea,
            featurePointCount: frame.rawFeaturePoints?.points.count ?? 0,
            keyframeCount: keyframes.count
        )
        mappingQuality = SpatialMappingQualityEvaluator.evaluate(metrics)
        try? machine.send(.mappingEvaluated(mappingQuality.level))
        phase = machine.phase
        captureKeyframeIfNeeded(frame: frame)
    }

    private func captureKeyframeIfNeeded(frame: ARFrame) {
        guard frame.camera.trackingState.isNormal, keyframes.count < 6 else { return }
        let now = Date.now
        guard now.timeIntervalSince(lastKeyframeAt ?? .distantPast) >= 4 else { return }
        guard let data = snapshotJPEG() else { return }
        keyframes.append(data)
        lastKeyframeAt = now
    }

    private func updateRelocalization(frame: ARFrame) {
        if Date.now.timeIntervalSince(mappingStartedAt ?? .now) > 35,
           !targetAnchorRestored {
            fail(.relocalizationTimedOut, message: "Não reconhecemos a cena a tempo.")
            return
        }
        guard targetAnchorRestored,
              frame.camera.trackingState.isNormal,
              let target = reference?.manifest.targetPose else {
            return
        }
        let current = Self.poseSample(from: frame.camera.transform)
        let evaluation = SpatialPoseGuidance.evaluate(current: current, target: target)
        poseEvaluation = evaluation
        try? machine.send(.poseEvaluated(isAligned: evaluation.isAligned))
        phase = machine.phase
        updateGhostColor(isAligned: evaluation.isAligned)
    }

    private func fail(_ failure: SpatialGuidanceFailure, message: String) {
        try? machine.send(.fail(failure))
        phase = machine.phase
        errorMessage = message
    }

    private func currentWorldMap() async throws -> ARWorldMap {
        try await withCheckedThrowingContinuation { continuation in
            sceneView.session.getCurrentWorldMap { map, error in
                if let map {
                    continuation.resume(returning: map)
                } else {
                    continuation.resume(
                        throwing: error ?? SpatialGuidanceRuntimeError.worldMapUnavailable
                    )
                }
            }
        }
    }

    private func snapshotJPEG() -> Data? {
        let image = sceneView.snapshot().resizedForSpatialGuide(maxLongEdge: 1_920)
        return image.jpegData(compressionQuality: 0.75)
    }

    private static func decodeWorldMap(_ data: Data) throws -> ARWorldMap {
        guard let map = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: ARWorldMap.self,
            from: data
        ) else {
            throw SpatialGuidanceRuntimeError.invalidWorldMap
        }
        return map
    }

    private static func poseSample(from transform: simd_float4x4) -> SpatialPoseSample {
        let orientation = simd_quatf(transform)
        let euler = orientation.eulerAngles
        return SpatialPoseSample(
            translationMeters: SpatialVector3(
                x: Double(transform.columns.3.x),
                y: Double(transform.columns.3.y),
                z: Double(transform.columns.3.z)
            ),
            eulerDegrees: SpatialVector3(
                x: Double(euler.x.radiansToDegrees),
                y: Double(euler.y.radiansToDegrees),
                z: Double(euler.z.radiansToDegrees)
            )
        )
    }

    private static var deviceModelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }

    private func makeGhostRigNode() -> SCNNode {
        let root = SCNNode()
        root.name = "Ghost Rig"

        let material = SCNMaterial()
        material.diffuse.contents = UIColor.systemYellow.withAlphaComponent(0.62)
        material.emission.contents = UIColor.systemYellow.withAlphaComponent(0.18)
        material.isDoubleSided = true

        let phone = SCNBox(width: 0.075, height: 0.15, length: 0.012, chamferRadius: 0.012)
        phone.materials = [material]
        let phoneNode = SCNNode(geometry: phone)
        phoneNode.position = SCNVector3(0, 0, -0.08)
        root.addChildNode(phoneNode)

        let hub = SCNCylinder(radius: 0.018, height: 0.045)
        hub.materials = [material]
        let hubNode = SCNNode(geometry: hub)
        hubNode.position = SCNVector3(0, -0.115, -0.08)
        root.addChildNode(hubNode)

        for angle in [-0.7, 0, 0.7] as [Float] {
            let leg = SCNCylinder(radius: 0.006, height: 0.32)
            leg.materials = [material]
            let legNode = SCNNode(geometry: leg)
            legNode.position = SCNVector3(sin(angle) * 0.09, -0.27, -0.08)
            legNode.eulerAngles.z = angle
            root.addChildNode(legNode)
        }
        root.opacity = 0.72
        return root
    }

    private func updateGhostColor(isAligned: Bool) {
        let color = isAligned ? UIColor.systemGreen : UIColor.systemYellow
        ghostNode?.enumerateChildNodes { node, _ in
            node.geometry?.materials.forEach {
                $0.diffuse.contents = color.withAlphaComponent(0.62)
                $0.emission.contents = color.withAlphaComponent(0.18)
            }
        }
    }
}

extension SpatialGuidanceSessionModel: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch phase {
            case .mapping, .insufficientCoverage, .readyToMount:
                updateMapping(frame: frame)
            case .relocalizing, .positioning, .aligned:
                updateRelocalization(frame: frame)
            default:
                break
            }
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.fail(.trackingUnavailable, message: error.localizedDescription)
        }
    }
}

extension SpatialGuidanceSessionModel: ARSCNViewDelegate {
    nonisolated func renderer(
        _ renderer: SCNSceneRenderer,
        didAdd node: SCNNode,
        for anchor: ARAnchor
    ) {
        guard anchor.name == spatialGuidanceTargetAnchorName else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            targetAnchorRestored = true
            ghostNode = makeGhostRigNode()
            if let ghostNode {
                node.addChildNode(ghostNode)
            }
            try? machine.send(.anchorRestored)
            phase = machine.phase
        }
    }
}

struct SpatialGuidanceARView: UIViewRepresentable {
    let model: SpatialGuidanceSessionModel

    func makeUIView(context: Context) -> ARSCNView {
        model.sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

enum SpatialGuidanceRuntimeError: Error {
    case mappingNotReady
    case worldMapUnavailable
    case invalidWorldMap
}

private extension ARCamera.TrackingState {
    var isNormal: Bool {
        if case .normal = self { return true }
        return false
    }
}

private extension simd_quatf {
    var eulerAngles: SIMD3<Float> {
        let matrix = simd_float3x3(self)
        let pitch = asin(-matrix[2][1])
        let yaw = atan2(matrix[2][0], matrix[2][2])
        let roll = atan2(matrix[0][1], matrix[1][1])
        return SIMD3<Float>(pitch, yaw, roll)
    }
}

private extension Float {
    var radiansToDegrees: Float { self * 180 / .pi }
}

private extension UIImage {
    func resizedForSpatialGuide(maxLongEdge: CGFloat) -> UIImage {
        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge else { return self }
        let scale = maxLongEdge / longEdge
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

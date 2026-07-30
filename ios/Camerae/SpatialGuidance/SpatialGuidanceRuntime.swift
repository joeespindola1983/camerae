import ARKit
import Foundation
import SceneKit
import SwiftUI
import UIKit

private let spatialGuidanceBaseAnchorName = "camerae.spatial.tripod-base-anchor"
private let spatialGuidanceDirectionAnchorName = "camerae.spatial.tripod-direction-anchor"
private let spatialGuidanceMeshNodeName = "camerae.spatial.mesh"
private let spatialGuidanceBaseNodeName = "camerae.spatial.tripod-base"
private let spatialGuidanceDirectionNodeName = "camerae.spatial.tripod-direction"

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
    @Published private(set) var errorMessage: String?
    @Published private(set) var isBusy = false
    @Published private(set) var tripodBaseCenter: SpatialVector3?
    @Published private(set) var tripodDirectionPoint: SpatialVector3?

    let sceneView: ARSCNView

    private var machine = SpatialGuidanceStateMachine()
    private var mappingStartedAt: Date?
    private var observedCameraPositions: [SIMD3<Float>] = []
    private var keyframes: [Data] = []
    private var lastKeyframeAt: Date?
    private var reference: SpatialReferenceBundle?
    private var targetAnchorRestored = false
    private var sceneMeshIsFrozen = false

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
        guard mappingQuality.canDefineScene,
              sceneMeshIsFrozen,
              let tripodBaseCenter,
              let tripodDirectionPoint else {
            throw SpatialGuidanceRuntimeError.mappingNotReady
        }
        isBusy = true
        defer { isBusy = false }
        try machine.send(.beginSaving)
        phase = machine.phase

        var baseTransform = matrix_identity_float4x4
        baseTransform.columns.3 = SIMD4<Float>(
            Float(tripodBaseCenter.x),
            Float(tripodBaseCenter.y),
            Float(tripodBaseCenter.z),
            1
        )
        sceneView.session.add(
            anchor: ARAnchor(name: spatialGuidanceBaseAnchorName, transform: baseTransform)
        )
        var directionTransform = matrix_identity_float4x4
        directionTransform.columns.3 = SIMD4<Float>(
            Float(tripodDirectionPoint.x),
            Float(tripodDirectionPoint.y),
            Float(tripodDirectionPoint.z),
            1
        )
        sceneView.session.add(
            anchor: ARAnchor(
                name: spatialGuidanceDirectionAnchorName,
                transform: directionTransform
            )
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
            tripodBaseCenter: tripodBaseCenter,
            tripodDirectionPoint: tripodDirectionPoint,
            targetPose: nil,
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

    var acceptsTripodBaseSelection: Bool {
        phase == .selectingTripodBase || phase == .tripodBaseSelected
    }

    var acceptsTripodDirectionSelection: Bool {
        phase == .selectingTripodDirection || phase == .tripodDirectionSelected
    }

    func freezeMappedScene() {
        guard mappingQuality.canDefineScene,
              phase == .mapping
                || phase == .insufficientCoverage
                || phase == .reviewingScene else {
            return
        }
        sceneMeshIsFrozen = true
        try? machine.send(.freezeScene)
        phase = machine.phase
    }

    func selectTripodBase(at point: CGPoint) {
        guard acceptsTripodBaseSelection else {
            return
        }
        guard let result = horizontalRaycast(at: point) else { return }
        let transform = result.worldTransform
        tripodBaseCenter = SpatialVector3(
            x: Double(transform.columns.3.x),
            y: Double(transform.columns.3.y),
            z: Double(transform.columns.3.z)
        )
        showTripodBaseMarker(at: transform)
        try? machine.send(.tripodBaseSelected)
        phase = machine.phase
    }

    func selectSpatialPoint(at point: CGPoint) {
        if acceptsTripodBaseSelection {
            selectTripodBase(at: point)
        } else if acceptsTripodDirectionSelection {
            selectTripodDirection(at: point)
        }
    }

    func selectTripodDirection(at point: CGPoint) {
        guard acceptsTripodDirectionSelection,
              let base = tripodBaseCenter,
              let result = horizontalRaycast(at: point) else {
            return
        }
        let candidate = SpatialVector3(
            x: Double(result.worldTransform.columns.3.x),
            y: base.y,
            z: Double(result.worldTransform.columns.3.z)
        )
        guard hypot(candidate.x - base.x, candidate.z - base.z) >= 0.25 else {
            return
        }
        tripodDirectionPoint = candidate
        showTripodDirection(base: base, direction: candidate)
        try? machine.send(.tripodDirectionSelected)
        phase = machine.phase
    }

    private func horizontalRaycast(at point: CGPoint) -> ARRaycastResult? {
        let existingQuery = sceneView.raycastQuery(
            from: point,
            allowing: .existingPlaneGeometry,
            alignment: .horizontal
        )
        let estimatedQuery = sceneView.raycastQuery(
            from: point,
            allowing: .estimatedPlane,
            alignment: .horizontal
        )
        let result = existingQuery.flatMap { sceneView.session.raycast($0).first }
            ?? estimatedQuery.flatMap { sceneView.session.raycast($0).first }
        return result
    }

    func confirmTripodBase() {
        guard tripodBaseCenter != nil, phase == .tripodBaseSelected else { return }
        try? machine.send(.confirmTripodBase)
        phase = machine.phase
    }

    func confirmTripodDirection() {
        guard tripodDirectionPoint != nil, phase == .tripodDirectionSelected else { return }
        try? machine.send(.confirmTripodDirection)
        phase = machine.phase
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
        errorMessage = nil
        mappingStartedAt = nil
        observedCameraPositions = []
        keyframes = []
        lastKeyframeAt = nil
        reference = nil
        targetAnchorRestored = false
        sceneMeshIsFrozen = false
        tripodBaseCenter = nil
        tripodDirectionPoint = nil
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
        if mappingQuality.canDefineScene {
            freezeMappedScene()
        }
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
              frame.camera.trackingState.isNormal else {
            return
        }
        if phase == .relocalizing {
            try? machine.send(.anchorRestored)
            phase = machine.phase
        }
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

    private static var deviceModelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }

    private func showTripodBaseMarker(at transform: simd_float4x4) {
        sceneView.scene.rootNode.childNode(
            withName: spatialGuidanceBaseNodeName,
            recursively: true
        )?.removeFromParentNode()

        let marker = makeTripodBaseMarkerNode()
        marker.name = spatialGuidanceBaseNodeName
        marker.simdTransform = transform
        marker.position.y += 0.006
        sceneView.scene.rootNode.addChildNode(marker)
    }

    private func makeTripodBaseMarkerNode() -> SCNNode {
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.systemOrange.withAlphaComponent(0.62)
        material.emission.contents = UIColor.systemOrange.withAlphaComponent(0.2)
        material.isDoubleSided = true
        let marker = SCNNode(geometry: SCNCylinder(radius: 0.035, height: 0.006))
        marker.geometry?.materials = [material]
        let center = SCNNode(geometry: SCNSphere(radius: 0.01))
        center.geometry?.materials = [material]
        center.position.y = 0.018
        marker.addChildNode(center)
        return marker
    }

    private func showTripodDirection(base: SpatialVector3, direction: SpatialVector3) {
        sceneView.scene.rootNode.childNode(
            withName: spatialGuidanceDirectionNodeName,
            recursively: true
        )?.removeFromParentNode()
        let vertices = [
            SCNVector3(base.x, base.y + 0.012, base.z),
            SCNVector3(direction.x, direction.y + 0.012, direction.z)
        ]
        let source = SCNGeometrySource(vertices: vertices)
        let element = SCNGeometryElement(
            indices: [UInt16(0), UInt16(1)],
            primitiveType: .line
        )
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.systemOrange
        material.emission.contents = UIColor.systemOrange.withAlphaComponent(0.35)
        geometry.materials = [material]
        let line = SCNNode(geometry: geometry)
        line.name = spatialGuidanceDirectionNodeName
        let endpoint = SCNNode(geometry: SCNSphere(radius: 0.012))
        endpoint.geometry?.materials = [material]
        endpoint.position = vertices[1]
        line.addChildNode(endpoint)
        sceneView.scene.rootNode.addChildNode(line)
    }

    private func updateSceneMesh(node: SCNNode, anchor: ARMeshAnchor) {
        guard !sceneMeshIsFrozen else { return }
        node.name = spatialGuidanceMeshNodeName
        node.geometry = SCNGeometry.spatialWireframe(from: anchor.geometry)
    }
}

extension SpatialGuidanceSessionModel: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch phase {
            case .initializingMapping:
                try? machine.send(.mappingSessionReady)
                phase = machine.phase
                updateMapping(frame: frame)
            case .mapping, .insufficientCoverage, .reviewingScene:
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let mesh = anchor as? ARMeshAnchor {
                updateSceneMesh(node: node, anchor: mesh)
                return
            }
            if anchor.name == spatialGuidanceBaseAnchorName {
                let marker = makeTripodBaseMarkerNode()
                marker.name = spatialGuidanceBaseNodeName
                node.addChildNode(marker)
                targetAnchorRestored = true
                return
            }
            if anchor.name == spatialGuidanceDirectionAnchorName,
               let base = reference?.manifest.tripodBaseCenter,
               let direction = reference?.manifest.tripodDirectionPoint {
                showTripodDirection(base: base, direction: direction)
                return
            }
            return
        }
    }

    nonisolated func renderer(
        _ renderer: SCNSceneRenderer,
        didUpdate node: SCNNode,
        for anchor: ARAnchor
    ) {
        guard let mesh = anchor as? ARMeshAnchor else { return }
        Task { @MainActor [weak self] in
            self?.updateSceneMesh(node: node, anchor: mesh)
        }
    }
}

struct SpatialGuidanceARView: UIViewRepresentable {
    let model: SpatialGuidanceSessionModel

    func makeUIView(context: Context) -> ARSCNView {
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        model.sceneView.addGestureRecognizer(tap)
        model.sceneView.addGestureRecognizer(pan)
        return model.sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    @MainActor
    final class Coordinator: NSObject {
        private let model: SpatialGuidanceSessionModel

        init(model: SpatialGuidanceSessionModel) {
            self.model = model
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            model.selectSpatialPoint(at: recognizer.location(in: model.sceneView))
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .began || recognizer.state == .changed else { return }
            model.selectSpatialPoint(at: recognizer.location(in: model.sceneView))
        }
    }
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

private extension SCNGeometry {
    static func spatialWireframe(from mesh: ARMeshGeometry) -> SCNGeometry {
        let vertices = SCNGeometrySource(
            buffer: mesh.vertices.buffer,
            vertexFormat: mesh.vertices.format,
            semantic: .vertex,
            vertexCount: mesh.vertices.count,
            dataOffset: mesh.vertices.offset,
            dataStride: mesh.vertices.stride
        )
        let normals = SCNGeometrySource(
            buffer: mesh.normals.buffer,
            vertexFormat: mesh.normals.format,
            semantic: .normal,
            vertexCount: mesh.normals.count,
            dataOffset: mesh.normals.offset,
            dataStride: mesh.normals.stride
        )
        let byteCount = mesh.faces.count
            * mesh.faces.indexCountPerPrimitive
            * mesh.faces.bytesPerIndex
        let faceData = Data(bytes: mesh.faces.buffer.contents(), count: byteCount)
        let faces = SCNGeometryElement(
            data: faceData,
            primitiveType: .triangles,
            primitiveCount: mesh.faces.count,
            bytesPerIndex: mesh.faces.bytesPerIndex
        )
        let geometry = SCNGeometry(sources: [vertices, normals], elements: [faces])
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.systemOrange.withAlphaComponent(0.72)
        material.emission.contents = UIColor.systemOrange.withAlphaComponent(0.12)
        material.fillMode = .lines
        material.isDoubleSided = true
        material.readsFromDepthBuffer = true
        material.writesToDepthBuffer = false
        geometry.materials = [material]
        return geometry
    }
}

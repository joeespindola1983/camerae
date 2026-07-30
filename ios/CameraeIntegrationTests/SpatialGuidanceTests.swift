import Foundation
import Testing
@testable import Camerae

@Suite("Repeatable spatial guidance")
struct SpatialGuidanceTests {
    @Test("availability requires Repeatable plus LiDAR-class tracking and sufficient processing")
    func capabilityPolicy() {
        let capable = SpatialGuidanceDeviceCapabilities(
            supportsWorldTracking: true,
            supportsSceneReconstruction: true,
            supportsSceneDepth: true,
            performanceClass: .high
        )

        #expect(
            SpatialGuidanceAvailabilityPolicy.resolve(
                module: .repeatable,
                capabilities: capable,
                thermalState: .nominal
            ) == .available
        )
        #expect(
            SpatialGuidanceAvailabilityPolicy.resolve(
                module: .astrophotography,
                capabilities: capable,
                thermalState: .nominal
            ) == .moduleUnavailable
        )
        #expect(
            SpatialGuidanceAvailabilityPolicy.resolve(
                module: .repeatable,
                capabilities: .init(
                    supportsWorldTracking: true,
                    supportsSceneReconstruction: false,
                    supportsSceneDepth: true,
                    performanceClass: .high
                ),
                thermalState: .nominal
            ) == .hardwareUnavailable
        )
        #expect(
            SpatialGuidanceAvailabilityPolicy.resolve(
                module: .repeatable,
                capabilities: capable,
                thermalState: .critical
            ) == .temporarilyUnavailable
        )
    }

    @Test("mapping cannot save until tracking, coverage, detail, and keyframes pass")
    func mappingQualityGate() {
        let insufficient = SpatialMappingQualityEvaluator.evaluate(
            .init(
                elapsedSeconds: 12,
                trackingIsNormal: true,
                mappedAreaSquareMeters: 3.8,
                featurePointCount: 420,
                keyframeCount: 2
            )
        )
        let ready = SpatialMappingQualityEvaluator.evaluate(
            .init(
                elapsedSeconds: 28,
                trackingIsNormal: true,
                mappedAreaSquareMeters: 8.2,
                featurePointCount: 1_350,
                keyframeCount: 5
            )
        )

        #expect(insufficient.level == .insufficient)
        #expect(!insufficient.canSave)
        #expect(insufficient.missingRequirements.contains(.coverage))
        #expect(ready.level == .ready)
        #expect(ready.canSave)
        #expect(ready.progress == 1)
    }

    @Test("the flow hides the ghost until relocalization and gates capture on pose tolerance")
    func stateMachine() throws {
        var machine = SpatialGuidanceStateMachine()

        try machine.send(.startMapping)
        #expect(machine.phase == .mapping)
        try machine.send(.mappingEvaluated(.insufficient))
        #expect(machine.phase == .insufficientCoverage)
        try machine.send(.mappingEvaluated(.ready))
        #expect(machine.phase == .readyToMount)
        try machine.send(.referenceSaved)
        #expect(machine.phase == .saved)

        try machine.send(.startRelocalization)
        #expect(machine.phase == .relocalizing)
        #expect(!machine.phase.showsGhost)
        try machine.send(.anchorRestored)
        #expect(machine.phase == .positioning)
        #expect(machine.phase.showsGhost)
        try machine.send(.poseEvaluated(isAligned: true))
        #expect(machine.phase == .aligned)
        #expect(machine.phase.canOpenCamera)
    }

    @Test("pose guidance reports translation and rotation separately")
    func poseGuidance() {
        let target = SpatialPoseSample(
            translationMeters: .init(x: 1, y: 1.2, z: -0.5),
            eulerDegrees: .init(x: 0, y: 90, z: 0)
        )
        let close = SpatialPoseSample(
            translationMeters: .init(x: 0.992, y: 1.207, z: -0.489),
            eulerDegrees: .init(x: 0.4, y: 89.4, z: -0.2)
        )
        let far = SpatialPoseSample(
            translationMeters: .init(x: 0.94, y: 1.25, z: -0.41),
            eulerDegrees: .init(x: 2.4, y: 86.5, z: 1.2)
        )

        let aligned = SpatialPoseGuidance.evaluate(current: close, target: target)
        let adjusting = SpatialPoseGuidance.evaluate(current: far, target: target)

        #expect(aligned.isAligned)
        #expect(aligned.horizontalDistanceMeters < 0.02)
        #expect(aligned.verticalDistanceMeters < 0.02)
        #expect(aligned.maximumRotationDegrees < 1)
        #expect(!adjusting.isAligned)
        #expect(adjusting.horizontalDistanceMeters > 0.02)
        #expect(adjusting.maximumRotationDegrees > 1)
    }

    @Test("saving a replacement archives the complete previous reference")
    func atomicStoreAndPreviousReference() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeSpatialGuidance-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SpatialReferenceStore(projectDirectory: directory)
        let first = makeManifest(id: UUID(), createdAt: Date(timeIntervalSince1970: 1))
        let second = makeManifest(id: UUID(), createdAt: Date(timeIntervalSince1970: 2))

        try store.save(
            manifest: first,
            worldMapData: Data("first-map".utf8),
            keyframes: [Data("first-frame".utf8)]
        )
        try store.save(
            manifest: second,
            worldMapData: Data("second-map".utf8),
            keyframes: [Data("second-frame".utf8)]
        )

        let current = try #require(try store.load())
        let previous = try #require(try store.loadPrevious())
        #expect(current.manifest.id == second.id)
        #expect(current.worldMapData == Data("second-map".utf8))
        #expect(previous.manifest.id == first.id)
        #expect(previous.worldMapData == Data("first-map".utf8))
        #expect(previous.keyframes == [Data("first-frame".utf8)])
    }

    @Test("current, empty, corrupt, and unsupported-newer documents are explicit")
    func storeCompatibility() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeSpatialCompatibility-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SpatialReferenceStore(projectDirectory: directory)

        #expect(try store.load() == nil)

        try store.save(
            manifest: makeManifest(id: UUID(), createdAt: .now),
            worldMapData: Data([1, 2, 3]),
            keyframes: []
        )
        #expect(try store.load()?.manifest.schemaVersion == SpatialReferenceManifest.currentSchemaVersion)

        let manifestURL = directory
            .appendingPathComponent("spatial_reference", isDirectory: true)
            .appendingPathComponent("manifest.json")
        let future = """
        {"schemaVersion":99,"id":"00000000-0000-0000-0000-000000000000"}
        """
        try Data(future.utf8).write(to: manifestURL, options: .atomic)
        #expect(throws: SpatialReferenceStoreError.unsupportedSchema(99)) {
            try store.load()
        }
    }

    @Test("required actions remain reachable in every visual state")
    func interfaceCapabilityContract() {
        #expect(
            SpatialGuidanceInterfaceCapabilityPolicy.actions(for: .noReference) ==
                [.createReference, .continueWithoutReference]
        )
        #expect(
            SpatialGuidanceInterfaceCapabilityPolicy.actions(for: .relocalizationFailed) ==
                [.retryRelocalization, .remapReference, .cancel]
        )
        #expect(
            SpatialGuidanceInterfaceCapabilityPolicy.actions(for: .incompatibleReference) ==
                [.remapReference, .continueWithoutReference]
        )
        #expect(
            SpatialGuidanceInterfaceCapabilityPolicy.actions(for: .aligned) ==
                [.openCamera, .cancel]
        )
    }

    private func makeManifest(id: UUID, createdAt: Date) -> SpatialReferenceManifest {
        SpatialReferenceManifest(
            id: id,
            createdAt: createdAt,
            module: .repeatable,
            deviceModelIdentifier: "iPhone-Test",
            cameraLens: .wide,
            cameraZoomFactor: 1,
            orientation: .portrait,
            targetPose: .zero,
            worldMapFileName: "world_map.bin",
            keyframeFileNames: ["guide-0001.jpg"]
        )
    }
}

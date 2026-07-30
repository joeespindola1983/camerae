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

    @Test("spatial appearance is restricted to black or white and three opacity levels")
    func restrictedAppearance() {
        #expect(SpatialGuidanceAppearance.default.mesh == .white(opacity: 0.5))
        #expect(SpatialGuidanceAppearance.default.tripod == .black(opacity: 0.5))
        #expect(SpatialGuidanceAppearance.default.camera == .white(opacity: 1))

        let restricted = SpatialGuidanceAppearance(
            mesh: .init(red: 0.8, green: 0.7, blue: 0.6, opacity: 0.38),
            tripod: .init(red: 0.1, green: 0.2, blue: 0.3, opacity: 0.76),
            camera: .init(red: 0.9, green: 0.1, blue: 0.1, opacity: 0.92)
        ).restricted

        #expect(restricted.mesh == .white(opacity: 0.5))
        #expect(restricted.tripod == .black(opacity: 1))
        #expect(restricted.camera == .black(opacity: 1))
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

    @Test("a minimally trustworthy map can be stopped manually before full coverage")
    func manualMappingCompletionGate() {
        let tooEarly = SpatialMappingQualityEvaluator.evaluate(
            .init(
                elapsedSeconds: 4,
                trackingIsNormal: true,
                mappedAreaSquareMeters: 0.4,
                featurePointCount: 120,
                keyframeCount: 1
            )
        )
        let reviewable = SpatialMappingQualityEvaluator.evaluate(
            .init(
                elapsedSeconds: 14,
                trackingIsNormal: true,
                mappedAreaSquareMeters: 2.4,
                featurePointCount: 620,
                keyframeCount: 3
            )
        )

        #expect(!tooEarly.canDefineScene)
        #expect(reviewable.canDefineScene)
        #expect(!reviewable.canSave)
    }

    @Test("scene capture and later navigation are separate from camera alignment")
    func stateMachine() throws {
        var machine = SpatialGuidanceStateMachine()

        try machine.send(.startMapping)
        #expect(machine.phase == .initializingMapping)
        try machine.send(.mappingSessionReady)
        try machine.send(.beginSceneCapture)
        #expect(machine.phase == .mapping)
        try machine.send(.mappingEvaluated(.insufficient))
        #expect(machine.phase == .insufficientCoverage)
        try machine.send(.freezeScene)
        #expect(machine.phase == .selectingTripodBase)
        try machine.send(.reset)
        try machine.send(.startMapping)
        try machine.send(.mappingSessionReady)
        try machine.send(.beginSceneCapture)
        try machine.send(.mappingEvaluated(.ready))
        #expect(machine.phase == .reviewingScene)
        try machine.send(.freezeScene)
        #expect(machine.phase == .selectingTripodBase)
        try machine.send(.tripodBaseSelected)
        #expect(machine.phase == .tripodBaseSelected)
        try machine.send(.confirmTripodBase)
        #expect(machine.phase == .selectingTripodDirection)
        try machine.send(.tripodDirectionSelected)
        #expect(machine.phase == .tripodDirectionSelected)
        try machine.send(.confirmTripodDirection)
        #expect(machine.phase == .readyToMount)
        try machine.send(.referenceSaved)
        #expect(machine.phase == .saved)

        try machine.send(.startRelocalization)
        #expect(machine.phase == .relocalizing)
        #expect(!machine.phase.showsGhost)
        try machine.send(.anchorRestored)
        #expect(machine.phase == .positioning)
        #expect(!machine.phase.showsGhost)
        #expect(!machine.phase.canOpenCamera)
    }

    @Test("mapping never presents the live-scanning state before the AR session is ready")
    func mappingStartupState() throws {
        var machine = SpatialGuidanceStateMachine()

        try machine.send(.startMapping)
        #expect(machine.phase == .initializingMapping)
        #expect(!machine.phase.showsLiveCamera)

        try machine.send(.mappingSessionReady)
        #expect(machine.phase == .readyToStartMapping)
        #expect(machine.phase.showsLiveCamera)

        try machine.send(.beginSceneCapture)
        #expect(machine.phase == .mapping)
        #expect(machine.phase.showsLiveCamera)
    }

    @Test("scene review and tripod-base selection keep their required actions reachable")
    func sceneDefinitionCapabilityContract() {
        #expect(
            SpatialGuidanceInterfaceCapabilityPolicy.actions(for: .readyToStartMapping) ==
                [.beginSceneCapture, .restartSceneCapture, .cancel]
        )
        #expect(
            SpatialGuidanceInterfaceCapabilityPolicy.actions(for: .reviewingScene) ==
                [.defineScene, .continueMapping, .cancel]
        )
        #expect(
            SpatialGuidanceInterfaceCapabilityPolicy.actions(for: .selectingTripodBase) ==
                [.selectTripodBase, .cancel]
        )
        #expect(
            SpatialGuidanceInterfaceCapabilityPolicy.actions(for: .tripodBaseSelected) ==
                [.adjustTripodBase, .confirmTripodBase, .cancel]
        )
        #expect(
            SpatialGuidanceInterfaceCapabilityPolicy.actions(for: .selectingTripodDirection) ==
                [.selectTripodDirection, .cancel]
        )
        #expect(
            SpatialGuidanceInterfaceCapabilityPolicy.actions(for: .tripodDirectionSelected) ==
                [.adjustTripodDirection, .confirmTripodDirection, .cancel]
        )
    }

    @Test("direction cannot be confirmed before its draggable point is selected")
    func directionSelectionGate() throws {
        var machine = SpatialGuidanceStateMachine()
        try machine.send(.startMapping)
        try machine.send(.mappingSessionReady)
        try machine.send(.beginSceneCapture)
        try machine.send(.mappingEvaluated(.ready))
        try machine.send(.freezeScene)
        try machine.send(.tripodBaseSelected)
        try machine.send(.confirmTripodBase)

        #expect(machine.phase == .selectingTripodDirection)
        #expect(throws: SpatialGuidanceTransitionError.self) {
            try machine.send(.confirmTripodDirection)
        }
    }

    @Test("direction handle keeps one fixed radius anywhere the scene is touched")
    func fixedDirectionHandleRadius() throws {
        let base = SpatialVector3(x: 2, y: 0.4, z: -1)
        let near = try #require(
            SpatialTripodDirection.point(base: base, toward: .init(x: 2.2, y: 8, z: -1))
        )
        let far = try #require(
            SpatialTripodDirection.point(base: base, toward: .init(x: 22, y: -5, z: -1))
        )

        #expect(
            abs(
                hypot(near.x - base.x, near.z - base.z)
                    - SpatialTripodDirection.handleDistanceMeters
            ) < 0.0001
        )
        #expect(
            abs(
                hypot(far.x - base.x, far.z - base.z)
                    - SpatialTripodDirection.handleDistanceMeters
            ) < 0.0001
        )
        #expect(SpatialTripodDirection.handleDistanceMeters == 0.45)
        #expect(near.y == base.y)
        #expect(far.y == base.y)
    }

    @Test("standard tripod mesh keeps three evenly spaced legs around the saved center")
    func standardTripodGeometry() throws {
        let base = SpatialVector3(x: 1, y: 0.2, z: -2)
        let direction = SpatialVector3(x: 1, y: 0.2, z: -3)
        let feet = try #require(
            SpatialStandardTripod.footPoints(base: base, direction: direction)
        )

        #expect(feet.count == 3)
        for foot in feet {
            #expect(
                abs(
                    hypot(foot.x - base.x, foot.z - base.z)
                        - SpatialStandardTripod.legRadiusMeters
                ) < 0.0001
            )
            #expect(foot.y == base.y)
        }
        #expect(feet[0].z < base.z)
        #expect(SpatialStandardTripod.heightMeters == 1)
    }

    @Test("tripod height uses nearby reconstructed volume and rejects distant scene geometry")
    func reconstructedTripodHeight() throws {
        let base = SpatialVector3(x: 0, y: 0, z: 0)
        let tube = (0..<30).map { index in
            SpatialVector3(x: 0.04, y: Double(index) * 0.04, z: 0.03)
        }
        let distantWall = [
            SpatialVector3(x: 1.2, y: 2.8, z: 0),
            SpatialVector3(x: 1.2, y: 3.2, z: 0),
        ]

        let height = try #require(
            SpatialTripodHeightEstimator.estimate(base: base, points: tube + distantWall)
        )

        #expect(height > 1)
        #expect(height < 1.3)
        #expect(SpatialTripodHeightEstimator.estimate(base: base, points: distantWall) == nil)
    }

    @Test("three low solid clusters become independent tripod feet")
    func reconstructedTripodFeet() throws {
        let base = SpatialVector3(x: 0, y: 0, z: 0)
        let expectedFeet = [
            SpatialVector3(x: 0, y: 0, z: -0.34),
            SpatialVector3(x: 0.29, y: 0, z: 0.17),
            SpatialVector3(x: -0.29, y: 0, z: 0.17),
        ]
        let footSamples = expectedFeet.flatMap { foot in
            (0..<10).map { index in
                SpatialVector3(
                    x: foot.x + Double(index % 3 - 1) * 0.008,
                    y: 0.04 + Double(index % 2) * 0.015,
                    z: foot.z + Double(index % 4 - 2) * 0.006
                )
            }
        }
        let unrelatedMass = (0..<20).map { index in
            SpatialVector3(x: 0.8, y: 0.06, z: Double(index) * 0.01)
        }

        let feet = try #require(
            SpatialTripodFootEstimator.estimate(
                base: base,
                points: footSamples + unrelatedMass
            )
        )

        #expect(feet.count == 3)
        for expected in expectedFeet {
            #expect(
                feet.contains {
                    hypot($0.x - expected.x, $0.z - expected.z) < 0.05
                }
            )
        }
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
        let visualizationAppearance = SpatialGuidanceAppearance(
            mesh: .black(opacity: 0.25),
            tripod: .white(opacity: 1),
            camera: .black(opacity: 0.5)
        )
        try store.updateAppearance(visualizationAppearance)

        let current = try #require(try store.load())
        let previous = try #require(try store.loadPrevious())
        #expect(current.manifest.id == second.id)
        #expect(current.worldMapData == Data("second-map".utf8))
        #expect(current.manifest.appearance == visualizationAppearance)
        #expect(previous.manifest.id == first.id)
        #expect(previous.worldMapData == Data("first-map".utf8))
        #expect(previous.keyframes == [Data("first-frame".utf8)])
    }

    @Test("current, legacy, empty, and unsupported-newer documents are explicit")
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
        let currentManifestData = try Data(contentsOf: manifestURL)
        var legacyManifest = try #require(
            JSONSerialization.jsonObject(with: currentManifestData) as? [String: Any]
        )
        legacyManifest.removeValue(forKey: "tripodDirectionPoint")
        legacyManifest.removeValue(forKey: "tripodHeightMeters")
        legacyManifest.removeValue(forKey: "tripodLegRadiusMeters")
        legacyManifest.removeValue(forKey: "tripodFootPoints")
        legacyManifest.removeValue(forKey: "appearance")
        try JSONSerialization.data(withJSONObject: legacyManifest)
            .write(to: manifestURL, options: .atomic)
        #expect(try store.load()?.manifest.tripodDirectionPoint == nil)
        #expect(try store.load()?.manifest.tripodHeightMeters == nil)
        #expect(try store.load()?.manifest.tripodLegRadiusMeters == nil)
        #expect(try store.load()?.manifest.tripodFootPoints == nil)
        #expect(try store.load()?.manifest.appearance == nil)

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
                [.completeNavigation, .cancel]
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
            tripodBaseCenter: .init(x: 0.4, y: 0, z: -1.2),
            tripodDirectionPoint: .init(x: 0.4, y: 0, z: -2.2),
            tripodHeightMeters: 1.18,
            tripodLegRadiusMeters: 0.41,
            tripodFootPoints: [
                .init(x: 0.4, y: 0, z: -1.6),
                .init(x: 0.72, y: 0, z: -1.0),
                .init(x: 0.08, y: 0, z: -1.0),
            ],
            appearance: .default,
            targetPose: nil,
            worldMapFileName: "world_map.bin",
            keyframeFileNames: ["guide-0001.jpg"]
        )
    }
}

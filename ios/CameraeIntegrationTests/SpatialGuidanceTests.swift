import Foundation
import Testing
import CameraeCore
@testable import Camerae

@Suite("Repeatable spatial guidance")
struct SpatialGuidanceTests {
    @Test("tripod visualization contains only its vertical axis")
    func axisOnlyTripodVisualization() {
        #expect(SpatialTripodVisualizationPolicy.visibleComponents == [.axis])
    }

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

    @Test("temporary thermal pressure is never presented as incompatible hardware")
    func temporaryAvailabilityPresentation() {
        let temporary = SpatialGuidanceProjectStatusPresentation(
            availability: .temporarilyUnavailable,
            hasReference: true
        )
        let incompatible = SpatialGuidanceProjectStatusPresentation(
            availability: .hardwareUnavailable,
            hasReference: true
        )

        #expect(temporary.title == "Aguarde o iPhone esfriar")
        #expect(temporary.status == "PAUSA TEMPORÁRIA")
        #expect(temporary.detail.contains("continua salva"))
        #expect(!temporary.title.localizedCaseInsensitiveContains("não pode"))
        #expect(incompatible.title == "Este iPhone não pode usar o guia")
        #expect(incompatible.status == "INCOMPATÍVEL")
    }

    @Test("spatial appearance is restricted to black or white and three opacity levels")
    func restrictedAppearance() {
        #expect(SpatialGuidanceAppearance.default.mesh == .white(opacity: 0.5))
        #expect(SpatialGuidanceAppearance.default.tripod == .black(opacity: 0.5))
        #expect(SpatialGuidanceAppearance.default.camera == .black(opacity: 1))

        let restricted = SpatialGuidanceAppearance(
            mesh: .init(red: 0.8, green: 0.7, blue: 0.6, opacity: 0.38),
            tripod: .init(red: 0.1, green: 0.2, blue: 0.3, opacity: 0.76),
            camera: .init(red: 0.9, green: 0.1, blue: 0.1, opacity: 0.92)
        ).restricted

        #expect(restricted.mesh == .white(opacity: 0.5))
        #expect(restricted.tripod == .black(opacity: 1))
        #expect(restricted.camera == .black(opacity: 1))
    }

    @Test("creation contrast toggles every tripod-related element against the mesh")
    func creationContrastToggle() {
        let lightMesh = SpatialCreationContrast.lightMesh.appearance
        let darkMesh = SpatialCreationContrast.darkMesh.appearance

        #expect(lightMesh.mesh == .white(opacity: 0.5))
        #expect(lightMesh.tripod == .black(opacity: 0.5))
        #expect(lightMesh.camera == .black(opacity: 1))
        #expect(darkMesh.mesh == .black(opacity: 0.5))
        #expect(darkMesh.tripod == .white(opacity: 0.5))
        #expect(darkMesh.camera == .white(opacity: 1))
        #expect(SpatialCreationContrast(appearance: lightMesh) == .lightMesh)
        #expect(SpatialCreationContrast(appearance: darkMesh) == .darkMesh)
    }

    @Test("mapping cannot save until tracking, coverage, detail, and keyframes pass")
    func mappingQualityGate() {
        let insufficient = SpatialMappingQualityEvaluator.evaluate(
            .init(
                elapsedSeconds: 12,
                trackingIsNormal: true,
                mappedAreaSquareMeters: 3.8,
                featurePointCount: 420,
                keyframeCount: 2,
                featureCellCoverage: 0.22,
                featureHeightRangeMeters: 0.18,
                cameraTravelDistanceMeters: 0.55
            )
        )
        let ready = SpatialMappingQualityEvaluator.evaluate(
            .init(
                elapsedSeconds: 28,
                trackingIsNormal: true,
                mappedAreaSquareMeters: 8.2,
                featurePointCount: 1_350,
                keyframeCount: 5,
                featureCellCoverage: 0.72,
                featureHeightRangeMeters: 1.4,
                cameraTravelDistanceMeters: 2.1
            )
        )

        #expect(insufficient.level == .insufficient)
        #expect(!insufficient.canSave)
        #expect(insufficient.missingRequirements.contains(.coverage))
        #expect(ready.level == .ready)
        #expect(ready.canSave)
        #expect(ready.progress == 1)
    }

    @Test("many points on a flat surface do not make a trustworthy map")
    func flatSurfaceQualityGate() {
        let flat = SpatialMappingQualityEvaluator.evaluate(
            .init(
                elapsedSeconds: 28,
                trackingIsNormal: true,
                mappedAreaSquareMeters: 8.2,
                featurePointCount: 1_650,
                keyframeCount: 5,
                featureCellCoverage: 0.76,
                featureHeightRangeMeters: 0.12,
                cameraTravelDistanceMeters: 2.0
            )
        )

        #expect(flat.level == .insufficient)
        #expect(flat.missingRequirements.contains(.geometryVariation))
        #expect(!flat.canDefineScene)
    }

    @Test("concentrated features and insufficient parallax remain actionable blockers")
    func distributedFeatureQualityGate() {
        let concentrated = SpatialMappingQualityEvaluator.evaluate(
            .init(
                elapsedSeconds: 28,
                trackingIsNormal: true,
                mappedAreaSquareMeters: 8.2,
                featurePointCount: 1_650,
                keyframeCount: 5,
                featureCellCoverage: 0.18,
                featureHeightRangeMeters: 1.2,
                cameraTravelDistanceMeters: 0.35
            )
        )

        #expect(concentrated.missingRequirements.contains(.featureDistribution))
        #expect(concentrated.missingRequirements.contains(.parallax))
        #expect(!concentrated.canSave)
    }

    @Test("the minimum trustworthy mapping threshold advances automatically")
    func automaticMappingCompletionGate() throws {
        var machine = SpatialGuidanceStateMachine()
        try machine.send(.startMapping)
        try machine.send(.mappingSessionReady)
        try machine.send(.beginSceneCapture)

        let ready = SpatialMappingQualityEvaluator.evaluate(
            .init(
                elapsedSeconds: 20,
                trackingIsNormal: true,
                mappedAreaSquareMeters: 6,
                featurePointCount: 900,
                keyframeCount: 4,
                featureCellCoverage: 0.55,
                featureHeightRangeMeters: 0.9,
                cameraTravelDistanceMeters: 1.5
            )
        )
        try machine.send(.mappingEvaluated(ready.level))

        #expect(ready.canSave)
        #expect(machine.phase == .reviewingScene)
        #expect(
            SpatialGuidanceInterfaceCapabilityPolicy.actions(for: machine.phase.visualState) ==
                [.cancel]
        )
    }

    @Test("a minimally trustworthy map can be stopped manually before full coverage")
    func manualMappingCompletionGate() {
        let tooEarly = SpatialMappingQualityEvaluator.evaluate(
            .init(
                elapsedSeconds: 4,
                trackingIsNormal: true,
                mappedAreaSquareMeters: 0.4,
                featurePointCount: 120,
                keyframeCount: 1,
                featureCellCoverage: 0.08,
                featureHeightRangeMeters: 0.08,
                cameraTravelDistanceMeters: 0.12
            )
        )
        let reviewable = SpatialMappingQualityEvaluator.evaluate(
            .init(
                elapsedSeconds: 14,
                trackingIsNormal: true,
                mappedAreaSquareMeters: 2.4,
                featurePointCount: 620,
                keyframeCount: 3,
                featureCellCoverage: 0.42,
                featureHeightRangeMeters: 0.65,
                cameraTravelDistanceMeters: 1.0
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
        #expect(throws: SpatialGuidanceTransitionError.self) {
            try machine.send(.freezeScene)
        }
        try machine.send(.reset)
        try machine.send(.startMapping)
        try machine.send(.mappingSessionReady)
        try machine.send(.beginSceneCapture)
        try machine.send(.mappingEvaluated(.ready))
        #expect(machine.phase == .reviewingScene)
        try machine.send(.freezeScene)
        #expect(machine.phase == .awaitingTripodPlacement)
        try machine.send(.tripodPlaced)
        #expect(machine.phase == .selectingTripodBase)
        try machine.send(.tripodBaseSelected)
        #expect(machine.phase == .tripodBaseSelected)
        try machine.send(.confirmTripodBase)
        #expect(machine.phase == .selectingTripodDirection)
        try machine.send(.tripodDirectionSelected)
        #expect(machine.phase == .tripodDirectionSelected)
        try machine.send(.confirmTripodDirection)
        #expect(machine.phase == .capturingReferencePhotos)
        try machine.send(.referencePhotoCaptured)
        #expect(machine.phase == .readyToMount)
        try machine.send(.reviewReference)
        #expect(machine.phase == .reviewingReference)
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
                [.cancel]
        )
        #expect(
            SpatialGuidanceInterfaceCapabilityPolicy.actions(for: .awaitingTripodPlacement) ==
                [.confirmTripodPlaced, .cancel]
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
                [.selectTripodDirection, .goBack, .cancel]
        )
        #expect(
            SpatialGuidanceInterfaceCapabilityPolicy.actions(for: .tripodDirectionSelected) ==
                [.adjustTripodDirection, .confirmTripodDirection, .goBack, .cancel]
        )
        #expect(
            SpatialGuidanceInterfaceCapabilityPolicy.actions(for: .capturingReferencePhotos) ==
                [.captureReferencePhoto, .goBack, .cancel]
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
        try machine.send(.tripodPlaced)
        try machine.send(.tripodBaseSelected)
        try machine.send(.confirmTripodBase)

        #expect(machine.phase == .selectingTripodDirection)
        #expect(throws: SpatialGuidanceTransitionError.self) {
            try machine.send(.confirmTripodDirection)
        }
    }

    @Test("creation progress groups the flow into four discoverable steps")
    func creationProgressPresentation() {
        #expect(SpatialGuidanceCreationProgress(phase: .mapping).activeStep == .map)
        #expect(
            SpatialGuidanceCreationProgress(phase: .tripodDirectionSelected).activeStep == .position
        )
        #expect(
            SpatialGuidanceCreationProgress(phase: .capturingReferencePhotos).activeStep == .reference
        )
        #expect(SpatialGuidanceCreationProgress(phase: .saving).activeStep == .finish)
        #expect(
            SpatialGuidanceCreationProgress(phase: .readyToMount).completedSteps ==
                [.map, .position]
        )
        #expect(
            SpatialGuidanceCreationProgress(phase: .saved).completedSteps ==
                Set(SpatialGuidanceCreationStep.allCases)
        )
    }

    @Test("confirmed tripod choices can be revisited without remapping the scene")
    func reversibleTripodConfirmation() throws {
        var machine = SpatialGuidanceStateMachine()
        try machine.send(.startMapping)
        try machine.send(.mappingSessionReady)
        try machine.send(.beginSceneCapture)
        try machine.send(.mappingEvaluated(.ready))
        try machine.send(.freezeScene)
        try machine.send(.tripodPlaced)
        try machine.send(.tripodBaseSelected)
        try machine.send(.confirmTripodBase)
        try machine.send(.tripodDirectionSelected)

        try machine.send(.goBack)
        #expect(machine.phase == .tripodBaseSelected)

        try machine.send(.confirmTripodBase)
        try machine.send(.tripodDirectionSelected)
        try machine.send(.confirmTripodDirection)
        #expect(machine.phase == .capturingReferencePhotos)

        try machine.send(.goBack)
        #expect(machine.phase == .tripodDirectionSelected)
    }

    @Test("one final scene photo is required and a second remains optional")
    func finalReferencePhotoGate() throws {
        var machine = SpatialGuidanceStateMachine()
        try machine.send(.startMapping)
        try machine.send(.mappingSessionReady)
        try machine.send(.beginSceneCapture)
        try machine.send(.mappingEvaluated(.ready))
        try machine.send(.freezeScene)
        try machine.send(.tripodPlaced)
        try machine.send(.tripodBaseSelected)
        try machine.send(.confirmTripodBase)
        try machine.send(.tripodDirectionSelected)
        try machine.send(.confirmTripodDirection)

        #expect(machine.phase == .capturingReferencePhotos)
        #expect(throws: SpatialGuidanceTransitionError.self) {
            try machine.send(.beginSaving)
        }

        try machine.send(.referencePhotoCaptured)
        #expect(machine.phase == .readyToMount)
        #expect(throws: SpatialGuidanceTransitionError.self) {
            try machine.send(.beginSaving)
        }
        try machine.send(.reviewReference)
        #expect(machine.phase == .reviewingReference)
        try machine.send(.goBack)
        #expect(machine.phase == .readyToMount)
        try machine.send(.referencePhotoRemoved)
        #expect(machine.phase == .capturingReferencePhotos)
    }

    @Test("reference photo capabilities preserve capture, retake, and save")
    func finalReferencePhotoCapabilityContract() {
        #expect(
            SpatialReferencePhotoCapabilityPolicy.actions(photoCount: 0) ==
                [.captureReferencePhoto, .cancel]
        )
        #expect(
            SpatialReferencePhotoCapabilityPolicy.actions(photoCount: 1) ==
                [.captureReferencePhoto, .retakeReferencePhoto, .saveReference, .cancel]
        )
        #expect(
            SpatialReferencePhotoCapabilityPolicy.actions(photoCount: 2) ==
                [.retakeReferencePhoto, .saveReference, .cancel]
        )
        #expect(SpatialReferenceThumbnailLayout(photoCount: 1) == .singleHero)
        #expect(SpatialReferenceThumbnailLayout(photoCount: 2) == .verticalPair)
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

    @Test("wireframe returns only for the final contextual tripod photos")
    func tripodVisualizationHidesWireframe() {
        #expect(SpatialMeshVisibilityPolicy.showsWireframe(during: .mapping))
        #expect(SpatialMeshVisibilityPolicy.showsWireframe(during: .reviewingScene))
        #expect(!SpatialMeshVisibilityPolicy.showsWireframe(during: .selectingTripodBase))
        #expect(!SpatialMeshVisibilityPolicy.showsWireframe(during: .tripodBaseSelected))
        #expect(!SpatialMeshVisibilityPolicy.showsWireframe(during: .selectingTripodDirection))
        #expect(SpatialMeshVisibilityPolicy.showsWireframe(during: .capturingReferencePhotos))
        #expect(SpatialMeshVisibilityPolicy.showsWireframe(during: .readyToMount))
        #expect(!SpatialMeshVisibilityPolicy.showsWireframe(during: .positioning))
    }

    @Test("three feet around a vertical column produce the tripod center despite scene clutter")
    func automaticTripodDetection() throws {
        let expectedCenter = SpatialVector3(x: 0.72, y: 0, z: -1.08)
        let expectedFeet = [
            SpatialVector3(x: 0.72, y: 0, z: -1.43),
            SpatialVector3(x: 1.02, y: 0, z: -0.90),
            SpatialVector3(x: 0.42, y: 0, z: -0.90),
        ]
        let footPoints = expectedFeet.flatMap { foot in
            (0..<14).map { index in
                SpatialVector3(
                    x: foot.x + Double(index % 4 - 2) * 0.007,
                    y: 0.035 + Double(index % 3) * 0.018,
                    z: foot.z + Double(index % 5 - 2) * 0.006
                )
            }
        }
        let column = (0..<34).flatMap { level in
            (0..<4).map { side in
                SpatialVector3(
                    x: expectedCenter.x + (side.isMultiple(of: 2) ? 0.025 : -0.025),
                    y: 0.10 + Double(level) * 0.032,
                    z: expectedCenter.z + (side < 2 ? 0.022 : -0.022)
                )
            }
        }
        let floor = (0..<80).map { index in
            SpatialVector3(
                x: -0.4 + Double(index % 10) * 0.18,
                y: 0,
                z: -1.9 + Double(index / 10) * 0.22
            )
        }
        let clutter = (0..<50).map { index in
            SpatialVector3(
                x: 2.2 + Double(index % 5) * 0.02,
                y: 0.04 + Double(index % 8) * 0.12,
                z: 0.8 + Double(index / 5) * 0.02
            )
        }

        let detection = try #require(
            SpatialTripodDetector.detect(
                points: footPoints + column + floor + clutter,
                floorY: 0,
                searchCenter: .init(x: 0.76, y: 1.1, z: -1.02)
            )
        )

        #expect(hypot(detection.center.x - expectedCenter.x, detection.center.z - expectedCenter.z) < 0.07)
        #expect(detection.feet.count == 3)
        #expect(detection.heightMeters > 0.9)
        #expect(detection.confidence >= 0.72)
    }

    @Test("tripod detection rejects three low clusters without a central column")
    func automaticTripodDetectionRejectsSceneObjects() {
        let clusters = [
            SpatialVector3(x: -0.3, y: 0.05, z: 0),
            SpatialVector3(x: 0.15, y: 0.05, z: 0.26),
            SpatialVector3(x: 0.15, y: 0.05, z: -0.26),
        ].flatMap { center in
            (0..<12).map { index in
                SpatialVector3(
                    x: center.x + Double(index % 3) * 0.006,
                    y: center.y,
                    z: center.z + Double(index % 4) * 0.006
                )
            }
        }

        #expect(
            SpatialTripodDetector.detect(
                points: clusters,
                floorY: 0,
                searchCenter: .zero
            ) == nil
        )
    }

    @Test("camera viewing rays triangulate the tripod center despite outliers")
    func viewingRayTriangulation() throws {
        let expected = SpatialVector3(x: 0.7, y: 0, z: -1.1)
        var rays = (0..<14).map { index in
            let angle = Double(index) * 2 * .pi / 14
            let origin = SpatialVector3(
                x: expected.x + cos(angle) * 1.25,
                y: 1.2,
                z: expected.z + sin(angle) * 1.25
            )
            let noise = Double(index % 3 - 1) * 0.008
            return SpatialObservationRay(
                origin: origin,
                direction: .init(
                    x: expected.x - origin.x + noise,
                    y: 0,
                    z: expected.z - origin.z - noise
                )
            )
        }
        rays.append(contentsOf: [
            .init(origin: .init(x: -1, y: 1.2, z: -1), direction: .init(x: -1, y: 0, z: 0)),
            .init(origin: .init(x: 2, y: 1.2, z: 1), direction: .init(x: 0, y: 0, z: 1)),
        ])

        let estimate = try #require(
            SpatialTripodCenterEstimator.estimate(rays: rays, floorY: 0)
        )

        #expect(hypot(estimate.center.x - expected.x, estimate.center.z - expected.z) < 0.05)
        #expect(estimate.supportingRayCount >= 12)
        #expect(estimate.confidence >= 0.75)
    }

    @Test("automatic center always falls back from mesh to viewing rays then camera path")
    func automaticTripodCenterFallbacks() throws {
        let rayEstimate = SpatialTripodCenterEstimate(
            center: .init(x: 0.4, y: 0, z: -0.8),
            confidence: 0.82,
            supportingRayCount: 11
        )
        let fromRay = try #require(
            SpatialTripodCenterResolver.resolve(
                meshDetection: nil,
                rayEstimate: rayEstimate,
                traversalCenter: .init(x: 2, y: 0, z: 2),
                floorY: 0.1
            )
        )
        let fromPath = try #require(
            SpatialTripodCenterResolver.resolve(
                meshDetection: nil,
                rayEstimate: nil,
                traversalCenter: .init(x: 0.6, y: 1.2, z: -1),
                floorY: 0.1
            )
        )

        #expect(fromRay.evidence == .viewingRays)
        #expect(fromRay.center == .init(x: 0.4, y: 0.1, z: -0.8))
        #expect(fromPath.evidence == .cameraPath)
        #expect(fromPath.center == .init(x: 0.6, y: 0.1, z: -1))
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

    @Test("recent tripod reference selects the newest compatible project and imports a distinct copy")
    func recentReferenceReuse() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeSpatialReuse-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let current = makeProject(name: "Current", directory: root.appendingPathComponent("current"))
        let older = makeProject(name: "Older", directory: root.appendingPathComponent("older"))
        let newest = makeProject(name: "Newest", directory: root.appendingPathComponent("newest"))
        let incompatible = makeProject(name: "Other iPhone", directory: root.appendingPathComponent("other"))

        try SpatialReferenceStore(projectDirectory: older.directoryURL).save(
            manifest: makeManifest(id: UUID(), createdAt: Date(timeIntervalSince1970: 1)),
            worldMapData: Data("older-map".utf8),
            keyframes: [Data("older-frame".utf8)]
        )
        try SpatialReferenceStore(projectDirectory: newest.directoryURL).save(
            manifest: makeManifest(id: UUID(), createdAt: Date(timeIntervalSince1970: 2)),
            worldMapData: Data("newest-map".utf8),
            keyframes: [Data("newest-frame".utf8)]
        )
        try SpatialReferenceStore(projectDirectory: incompatible.directoryURL).save(
            manifest: makeManifest(
                id: UUID(),
                createdAt: Date(timeIntervalSince1970: 3),
                deviceModelIdentifier: "Different-iPhone"
            ),
            worldMapData: Data("other-map".utf8),
            keyframes: [Data("other-frame".utf8)]
        )

        let candidate = try #require(
            SpatialReferenceReuseResolver.latest(
                projects: [older, newest, incompatible, current],
                excluding: current.id,
                deviceModelIdentifier: "iPhone-Test"
            )
        )
        let imported = try SpatialReferenceStore(projectDirectory: current.directoryURL)
            .importReference(candidate.bundle, id: UUID(), createdAt: Date(timeIntervalSince1970: 4))

        #expect(candidate.sourceProject.name == "Newest")
        #expect(imported.manifest.id != candidate.bundle.manifest.id)
        #expect(imported.manifest.createdAt == Date(timeIntervalSince1970: 4))
        #expect(imported.worldMapData == Data("newest-map".utf8))
        #expect(try SpatialReferenceStore(projectDirectory: current.directoryURL).load() == imported)
    }

    @Test("manual tripod photos persist separately from mapping keyframes and survive reuse")
    func manualReferencePhotosPersist() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeSpatialPhotos-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceStore = SpatialReferenceStore(projectDirectory: root.appendingPathComponent("source"))
        let targetStore = SpatialReferenceStore(projectDirectory: root.appendingPathComponent("target"))
        let keyframes = [Data("mapping-one".utf8)]
        let photos = [Data("hero".utf8), Data("context".utf8)]

        try sourceStore.save(
            manifest: makeManifest(id: UUID(), createdAt: .now),
            worldMapData: Data("map".utf8),
            keyframes: keyframes,
            thumbnailImages: photos
        )
        let source = try #require(try sourceStore.load())
        let imported = try targetStore.importReference(source)

        #expect(source.keyframes == keyframes)
        #expect(source.thumbnailImages == photos)
        #expect(imported.thumbnailImages == photos)
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
            keyframes: [Data("compatibility-frame".utf8)]
        )
        #expect(try store.load()?.manifest.schemaVersion == SpatialReferenceManifest.currentSchemaVersion)
        #expect(try store.load()?.thumbnailImages.isEmpty == true)

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
        #expect(
            SpatialGuidanceInterfaceCapabilityPolicy.actions(for: .referenceSaved) ==
                [.navigateScene, .reviewReference, .remapReference]
        )
        #expect(
            SpatialGuidanceInterfaceCapabilityPolicy.actions(for: .confirmRemap) ==
                [.remapReference, .cancel]
        )
    }

    @Test("tripod setup exposes recent-position reuse only when it can replace initial mapping")
    func projectTabCapabilityContract() {
        #expect(
            SpatialGuidanceProjectCapabilityPolicy.actions(
                availability: .available,
                hasReference: false,
                hasReusableReference: true
            ) == [.createReference, .reuseRecentReference, .watchTutorial]
        )
        #expect(
            SpatialGuidanceProjectCapabilityPolicy.actions(
                availability: .available,
                hasReference: true,
                hasReusableReference: true
            ) == [.navigateScene, .watchTutorial, .remapReference]
        )
        #expect(
            SpatialGuidanceProjectCapabilityPolicy.actions(
                availability: .hardwareUnavailable,
                hasReference: false,
                hasReusableReference: true
            ) == [.continueWithoutGuide]
        )
    }

    private func makeManifest(
        id: UUID,
        createdAt: Date,
        deviceModelIdentifier: String = "iPhone-Test"
    ) -> SpatialReferenceManifest {
        SpatialReferenceManifest(
            id: id,
            createdAt: createdAt,
            module: .repeatable,
            deviceModelIdentifier: deviceModelIdentifier,
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


    private func makeProject(name: String, directory: URL) -> CameraProject {
        CameraProject(
            record: ProjectRecord(
                id: UUID(),
                module: .repeatable,
                name: name,
                directoryURL: directory,
                createdAt: .distantPast,
                updatedAt: .distantPast,
                lastOpenedAt: nil,
                isArchived: false,
                sequenceNumber: 1
            ),
            summary: nil
        )
    }
}

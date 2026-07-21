import Testing
@testable import Camerae

struct CameraeNextCaptureToolCatalogTests {
    @Test func repeatableExposesEveryAlignmentGroupInStableOrder() {
        let catalog = CameraeNextCaptureToolCatalog(module: .repeatable)

        #expect(catalog.groups.map(\.id) == [.trace, .guides, .blink, .sensors, .information])
        #expect(catalog.groups.flatMap(\.tools).map(\.id) == [
            .referenceEdges, .edgeColor, .edgeStroke,
            .grid, .visualMatch, .scale, .magnifier,
            .referenceBlink, .blinkInterval, .referenceOpacity,
            .position, .motion,
            .captureInformation
        ])
    }

    @Test func astroUsesTheSharedGroupsButOnlyOffersRelevantCaptureTools() {
        let catalog = CameraeNextCaptureToolCatalog(module: .astrophotography)

        #expect(catalog.groups.map(\.id) == [.guides, .sensors, .information])
        #expect(catalog.groups.flatMap(\.tools).map(\.id) == [
            .grid, .position, .motion, .captureInformation
        ])
    }

    @Test func toolStripStaysCenteredAndHorizontalInBothCaptureOrientations() {
        let portrait = CameraeNextCaptureToolStripPresentation(
            module: .repeatable,
            orientation: .portrait
        )
        let landscape = CameraeNextCaptureToolStripPresentation(
            module: .repeatable,
            orientation: .landscape
        )

        #expect(portrait.axis == .horizontal)
        #expect(landscape.axis == .horizontal)
        #expect(portrait.groups == landscape.groups)
    }

    @Test func toolGroupsExposeTheFigmaVectorAssets() {
        #expect(CameraeNextCaptureToolGroupID.trace.assetName == "CameraeCaptureGlyphTrace")
        #expect(CameraeNextCaptureToolGroupID.guides.assetName == "CameraeCaptureGlyphGuides")
        #expect(CameraeNextCaptureToolGroupID.blink.assetName == "CameraeCaptureGlyphBlink")
        #expect(CameraeNextCaptureToolGroupID.sensors.assetName == "CameraeCaptureGlyphSensors")
        #expect(CameraeNextCaptureToolGroupID.information.assetName == "CameraeCaptureGlyphInfo")
    }

    @Test func expandedTrayUsesTheSelectedGroupAndModuleTheme() {
        let tray = CameraeNextCaptureToolTrayPresentation(
            module: .repeatable,
            selection: .guides
        )

        #expect(tray?.title == "GUIAS")
        #expect(tray?.theme == .repeatable)
        #expect(tray?.tools.map(\.id) == [.grid, .visualMatch, .scale, .magnifier])
    }

    @Test func informationIsADirectToggleInsteadOfATray() {
        #expect(CameraeNextCaptureToolGroupID.trace.opensTray)
        #expect(CameraeNextCaptureToolGroupID.guides.opensTray)
        #expect(CameraeNextCaptureToolGroupID.blink.opensTray)
        #expect(CameraeNextCaptureToolGroupID.sensors.opensTray)
        #expect(!CameraeNextCaptureToolGroupID.information.opensTray)
    }

    @Test func comparisonTrayOffersSharedReferenceOpacityPresets() {
        let tray = CameraeNextCaptureToolTrayPresentation(
            module: .repeatable,
            selection: .blink
        )

        #expect(tray?.title == "COMPARAÇÃO")
        #expect(tray?.tools.map(\.id) == [.referenceBlink, .blinkInterval, .referenceOpacity])
        #expect(CameraeNextReferenceOpacityOption.allCases.map(\.label) == ["25", "50", "100"])
        #expect(CameraeNextReferenceOpacityOption.allCases.map(\.opacity) == [0.25, 0.5, 1])
        #expect(CameraeNextReferenceOpacityOption.nearest(to: 0.45) == .half)
    }

    @Test func comparisonTrayUsesTheRequestedBlinkIntervals() {
        #expect(CameraeNextReferenceBlinkInterval.allCases.map(\.label) == ["1s", "2s", "4s", "8s"])
        #expect(CameraeNextReferenceBlinkInterval.allCases.map(\.seconds) == [1, 2, 4, 8])
    }

    @Test func motionSensorAlwaysExplainsItsVisibleState() {
        #expect(CameraeNextMotionHUDPresentation(
            isVisible: false,
            hasReferenceMotion: false,
            hasCurrentMotion: false
        ) == .hidden)
        #expect(CameraeNextMotionHUDPresentation(
            isVisible: true,
            hasReferenceMotion: true,
            hasCurrentMotion: true
        ) == .alignment)
        #expect(CameraeNextMotionHUDPresentation(
            isVisible: true,
            hasReferenceMotion: false,
            hasCurrentMotion: true
        ) == .referenceUnavailable)
        #expect(CameraeNextMotionHUDPresentation(
            isVisible: true,
            hasReferenceMotion: true,
            hasCurrentMotion: false
        ) == .sensorUnavailable)
    }

    @Test func opacityToolUsesTheFigmaHalfFilledCircleSymbol() {
        #expect(CameraeNextCaptureToolID.referenceOpacity.systemImage == "circle.lefthalf.filled")
    }

    @Test func liveCaptureStartsWithoutHeadingAndRespectsTheSafeArea() {
        #expect(!CameraeNextCaptureHUDDefaults.showsRepeatablePosition)
        #expect(!CameraeNextCaptureHUDDefaults.showsRepeatableMotion)
        #expect(CameraeNextCaptureHUDDefaults.repeatableSelectedGroup == nil)
        #expect(CameraeNextCaptureHUDLayout.topInset == 6)
    }
}

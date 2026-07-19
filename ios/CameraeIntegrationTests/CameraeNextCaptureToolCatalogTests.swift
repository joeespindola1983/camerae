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

    @Test func liveCaptureStartsWithoutHeadingAndRespectsTheSafeArea() {
        #expect(!CameraeNextCaptureHUDDefaults.showsRepeatablePosition)
        #expect(CameraeNextCaptureHUDDefaults.repeatableSelectedGroup == nil)
        #expect(CameraeNextCaptureHUDLayout.topInset == 6)
    }
}

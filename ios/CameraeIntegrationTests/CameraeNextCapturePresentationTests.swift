import Testing
@testable import Camerae

@Suite("Camerae Next capture presentation")
struct CameraeNextCapturePresentationTests {
    @Test("Repeatable and Astro keep their domain metrics behind one presentation type")
    func workflowMetrics() {
        let repeatable = CameraeNextCaptureSessionPresentation.repeatable(
            frameCount: 12,
            exposure: "0 EV",
            reference: "Praia",
            lastExposure: "1/60",
            countdown: "3s",
            gps: "OK",
            isRunning: false
        )
        let astro = CameraeNextCaptureSessionPresentation.astro(
            originalCount: 9,
            acceptedCount: 3,
            batch: "2/3",
            phase: "Expondo",
            baseExposure: "8s",
            lastExposure: "8s",
            isRunning: false
        )

        #expect(repeatable.theme == .repeatable)
        #expect(repeatable.metrics.map(\.title) == ["Frames", "EV", "Ref", "Última", "Início", "GPS"])
        #expect(repeatable.actionTitle == "Iniciar captura")
        #expect(!repeatable.showsLandscapePreview)
        #expect(astro.theme == .astro)
        #expect(astro.metrics.map(\.title) == ["Orig", "Bons", "Lote", "Fase", "Base", "Última"])
        #expect(astro.actionTitle == "Iniciar lotes Astro")
        #expect(astro.showsLandscapePreview)
    }

    @Test("running capture always exposes a destructive stop action")
    func runningAction() {
        let repeatable = CameraeNextCaptureSessionPresentation.repeatable(
            frameCount: 1,
            exposure: "0 EV",
            reference: "Ref",
            lastExposure: "—",
            countdown: "—",
            gps: "—",
            isRunning: true
        )
        let astro = CameraeNextCaptureSessionPresentation.astro(
            originalCount: 1,
            acceptedCount: 0,
            batch: "1/3",
            phase: "Expondo",
            baseExposure: "8s",
            lastExposure: "—",
            isRunning: true
        )

        #expect(repeatable.actionTitle == "Parar")
        #expect(repeatable.actionSystemImage == "stop.fill")
        #expect(astro.actionTitle == "Parar")
        #expect(astro.actionSystemImage == "stop.fill")
    }

    @Test("capture panel owns responsive portrait and landscape limits")
    func responsiveLimits() {
        #expect(CameraeCapturePanelOrientation.portrait.panelWidth == 366)
        #expect(CameraeCapturePanelOrientation.portrait.contentWidth == 342)
        #expect(CameraeCapturePanelOrientation.landscape.panelWidth == 300)
        #expect(CameraeCapturePanelOrientation.landscape.contentWidth == 276)
    }
}

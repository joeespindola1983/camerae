import Testing
@testable import Camerae

@Suite("Camerae Next workflow configuration")
struct CameraeNextWorkflowConfigurationTests {
    @Test("Repeatable starts from the Figma timelapse defaults")
    func repeatableDefaults() {
        let configuration = CameraeNextCaptureConfiguration.repeatableDefault

        #expect(configuration.module == .repeatable)
        #expect(configuration.repeatableKind == .timelapse)
        #expect(configuration.durationMinutes == 30)
        #expect(configuration.cameraLens == .wide)
        #expect(configuration.intervalSeconds == 5)
        #expect(configuration.referenceOpacity == 0.45)
    }

    @Test("Astro starts from the manual session defaults")
    func astroDefaults() {
        let configuration = CameraeNextCaptureConfiguration.astroDefault

        #expect(configuration.module == .astrophotography)
        #expect(!configuration.usesAutomaticAstroExposure)
        #expect(configuration.durationMinutes == 30)
        #expect(configuration.cameraLens == .wide)
        #expect(configuration.astroExposureSeconds == 8)
        #expect(configuration.intervalSeconds == 8)
        #expect(configuration.astroCapturesPerFrame == 3)
    }

    @Test("estimated frame count follows each workflow interval")
    func frameEstimate() {
        var repeatable = CameraeNextCaptureConfiguration.repeatableDefault
        repeatable.durationMinutes = 15
        repeatable.intervalSeconds = 5
        #expect(repeatable.estimatedFrameCount == 180)

        var astro = CameraeNextCaptureConfiguration.astroDefault
        astro.durationMinutes = 30
        astro.astroExposureSeconds = 8
        astro.astroCapturesPerFrame = 3
        #expect(astro.estimatedFrameCount == 75)
    }

    @Test("Repeatable presentation follows the approved configuration screen")
    func repeatablePresentation() {
        let presentation = CameraeNextWorkflowConfigurationPresentation(
            configuration: .repeatableDefault
        )

        #expect(presentation.navigationTitle == "Novo timelapse")
        #expect(presentation.primaryActionTitle == "Abrir alinhamento")
        #expect(presentation.captureSectionTitle == "CAPTURA")
        #expect(presentation.adjustmentsSectionTitle == "AJUSTES")
        #expect(presentation.adjustmentTitles == ["EV", "Opacidade", "Intervalo"])
        #expect(presentation.cameraPresentation == .selector)
    }

    @Test("Repeatable video and timelapse expose different configuration contracts")
    func repeatableModes() {
        var video = CameraeNextCaptureConfiguration.repeatableDefault
        video.repeatableKind = .video
        let videoPresentation = CameraeNextWorkflowConfigurationPresentation(configuration: video)
        let timelapsePresentation = CameraeNextWorkflowConfigurationPresentation(configuration: .repeatableDefault)

        #expect(videoPresentation.navigationTitle == "Novo vídeo")
        #expect(videoPresentation.durationLabels == ["30 s", "1 min", "2 min"])
        #expect(videoPresentation.adjustmentTitles == ["EV", "Opacidade"])
        #expect(videoPresentation.showsVideoSettings)
        #expect(!videoPresentation.showsInterval)
        #expect(video.estimatedFrameCount == video.videoDurationSeconds * video.videoSettings.fps)

        #expect(timelapsePresentation.navigationTitle == "Novo timelapse")
        #expect(!timelapsePresentation.showsVideoSettings)
        #expect(timelapsePresentation.showsInterval)
    }

    @Test("Astro presentation uses its compact locked camera status")
    func astroPresentation() {
        let presentation = CameraeNextWorkflowConfigurationPresentation(
            configuration: .astroDefault
        )

        #expect(presentation.navigationTitle == "Novo astro")
        #expect(presentation.primaryActionTitle == "Abrir câmera")
        #expect(presentation.captureSectionTitle == "SESSÃO")
        #expect(presentation.adjustmentsSectionTitle == "CAPTURA ASTRO")
        #expect(presentation.adjustmentTitles == ["Exposição", "Intervalo", "Capturas/frame"])
        #expect(presentation.cameraPresentation == .lockedStatus(lens: "Wide", zoom: "1×"))
    }

    @Test("Duration options preserve the Figma labels for each workflow")
    func durationLabels() {
        #expect(
            CameraeNextWorkflowConfigurationPresentation(configuration: .repeatableDefault)
                .durationLabels == ["15 min", "30 min", "1 h", "Custom"]
        )
        #expect(
            CameraeNextWorkflowConfigurationPresentation(configuration: .astroDefault)
                .durationLabels == ["15 min", "30 min", "1 h", "Personal."]
        )
    }
}

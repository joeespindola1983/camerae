import Testing
import CameraeCore
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

    @Test("Planning variants preserve the capture gate contract")
    func planningVariants() {
        let warning = CameraeNextCapturePlanningPresentation(
            storage: .init(
                decision: .warning,
                reason: .lowStorageMargin,
                requiredBytes: 1_400_000_000,
                availableBytes: 1_800_000_000,
                shortfallBytes: 0
            ),
            metricsDetail: "360 frames"
        )
        let blocked = CameraeNextCapturePlanningPresentation(
            storage: .init(
                decision: .blocked,
                reason: .insufficientStorage,
                requiredBytes: 2_200_000_000,
                availableBytes: 1_000_000_000,
                shortfallBytes: 1_200_000_000
            ),
            metricsDetail: "360 frames"
        )

        #expect(warning.state == .warning)
        #expect(warning.canStart)
        #expect(blocked.state == .blocked)
        #expect(!blocked.canStart)
    }

    @Test("Planning surfaces compatibility and power variants without blocking valid storage")
    func planningCompatibilityVariants() {
        let storage = CaptureAdmissionResult(
            decision: .allowed,
            reason: .sufficientCapacity,
            requiredBytes: 1_000,
            availableBytes: 10_000,
            shortfallBytes: 0
        )

        let adjusted = CameraeNextCapturePlanningPresentation(
            storage: storage,
            formatWasAdjusted: true,
            metricsDetail: "120 frames"
        )
        let power = CameraeNextCapturePlanningPresentation(
            storage: storage,
            externalPowerRecommended: true,
            metricsDetail: "120 frames"
        )

        #expect(adjusted.state == .adjusted)
        #expect(adjusted.canStart)
        #expect(power.state == .externalPower)
        #expect(power.canStart)
    }

    @Test("Camera availability resolves single, fallback and unavailable states")
    func cameraAvailability() {
        let single = CameraeNextCameraSetupPresentation(
            availableLenses: [.wide],
            selectedLens: .wide,
            preferredLens: .wide
        )
        let fallback = CameraeNextCameraSetupPresentation(
            availableLenses: [.wide],
            selectedLens: .wide,
            preferredLens: .telephoto
        )
        let userSelection = CameraeNextCameraSetupPresentation(
            availableLenses: [.ultraWide, .wide, .telephoto],
            selectedLens: .telephoto,
            preferredLens: .wide
        )
        let unavailable = CameraeNextCameraSetupPresentation(
            availableLenses: [],
            selectedLens: .wide,
            preferredLens: .wide
        )

        #expect(single.state == .single)
        #expect(fallback.state == .fallback)
        #expect(userSelection.state == .available)
        #expect(unavailable.state == .unavailable)
        #expect(!unavailable.canStart)
    }

    @Test("Reference card follows the actual project reference")
    func referenceState() {
        #expect(CameraeNextReferencePresentation(module: .repeatable, state: .missing).title == "Nenhuma referência definida")
        #expect(CameraeNextReferencePresentation(module: .astrophotography, state: .active).sectionTitle == "GUIA NOTURNO")
        #expect(CameraeNextReferencePresentation(module: .astrophotography, state: .unavailable).status == "INDISPONÍVEL")
    }

    @Test("Custom duration accepts the Figma hour-minute format")
    func customDuration() {
        #expect(CameraeNextCustomDuration.format(minutes: 150) == "02 h 30 min")
        #expect(CameraeNextCustomDuration.parse("02 h 30 min") == 150)
        #expect(CameraeNextCustomDuration.parse("4:15") == 255)
        #expect(CameraeNextCustomDuration.parse("0 h 00 min") == nil)
    }

    @Test("Automatic Astro mode disables only the manual exposure control")
    func automaticAstroExposure() {
        var automatic = CameraeNextCaptureConfiguration.astroDefault
        automatic.usesAutomaticAstroExposure = true
        let automaticPresentation = CameraeNextWorkflowConfigurationPresentation(configuration: automatic)
        let manualPresentation = CameraeNextWorkflowConfigurationPresentation(configuration: .astroDefault)

        #expect(!automaticPresentation.isAstroExposureControlEnabled)
        #expect(manualPresentation.isAstroExposureControlEnabled)
    }
}

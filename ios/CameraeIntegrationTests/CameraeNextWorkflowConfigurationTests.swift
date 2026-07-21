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
        #expect(configuration.cameraZoomFactor == 1)
        #expect(configuration.intervalSeconds == 5)
        #expect(configuration.referenceOpacity == 0.5)
    }

    @Test("Astro starts from the manual session defaults")
    func astroDefaults() {
        let configuration = CameraeNextCaptureConfiguration.astroDefault

        #expect(configuration.module == .astrophotography)
        #expect(!configuration.usesAutomaticAstroExposure)
        #expect(configuration.durationMinutes == 30)
        #expect(configuration.cameraLens == .wide)
        #expect(configuration.cameraZoomFactor == 1)
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
        #expect(presentation.primaryActionTitle == "Abrir câmera")
        #expect(presentation.captureSectionTitle == "CAPTURA")
        #expect(presentation.adjustmentsSectionTitle == "AJUSTES")
        #expect(presentation.adjustmentTitles == ["EV", "Intervalo"])
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
        #expect(videoPresentation.adjustmentTitles == ["EV"])
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
        let missing = CameraeNextReferencePresentation(module: .repeatable, state: .missing)
        let active = CameraeNextReferencePresentation(module: .astrophotography, state: .active)

        #expect(missing.showsPlaceholder)
        #expect(missing.primaryActionTitle == "Tirar foto")
        #expect(missing.secondaryActionTitle == "Importar")
        #expect(!active.showsPlaceholder)
        #expect(active.primaryActionTitle == "Substituir")
        #expect(active.secondaryActionTitle == "Remover")
    }

    @Test("an empty project keeps camera selection available")
    func emptyProjectCameraSelection() {
        let policy = CameraeNextProjectCameraPolicy(summaries: [])

        #expect(!policy.isLocked)
        #expect(policy.lockedLens == nil)
    }

    @Test("photo, timelapse, Astro and video media lock the project camera")
    func everyCapturedMediaKindLocksCamera() {
        let cases: [(RepeatableCaptureKind, CameraModule, Int, URL?, Bool)] = [
            (.photo, .repeatable, 1, nil, false),
            (.timelapse, .repeatable, 2, nil, false),
            (.timelapse, .astrophotography, 1, nil, true),
            (.video, .repeatable, 0, URL(fileURLWithPath: "/tmp/video.mov"), false)
        ]

        for (kind, module, frameCount, videoURL, isAstroProcessed) in cases {
            let policy = CameraeNextProjectCameraPolicy(summaries: [
                sessionSummary(
                    kind: kind,
                    module: module,
                    frameCount: frameCount,
                    videoClipURL: videoURL,
                    isAstroProcessed: isAstroProcessed,
                    lens: .telephoto
                )
            ])

            #expect(policy.isLocked)
            #expect(policy.lockedLens == .telephoto)
        }
    }

    @Test("the first captured lens remains authoritative for later captures")
    func firstCapturedLensWins() {
        let first = sessionSummary(
            kind: .photo,
            frameCount: 1,
            createdAt: Date(timeIntervalSince1970: 100),
            lens: .ultraWide
        )
        let later = sessionSummary(
            kind: .video,
            frameCount: 0,
            videoClipURL: URL(fileURLWithPath: "/tmp/video.mov"),
            createdAt: Date(timeIntervalSince1970: 200),
            lens: .wide
        )

        let policy = CameraeNextProjectCameraPolicy(summaries: [later, first])

        #expect(policy.lockedLens == .ultraWide)
    }

    @Test("a photographed reference locks its detected lens and zoom")
    func photographedReferenceLocksCameraAndZoom() {
        let reference = sessionSummary(
            kind: .photo,
            frameCount: 1,
            lens: .wide,
            zoomFactor: 2
        )

        let policy = CameraeNextProjectCameraPolicy(summaries: [reference])
        let presentation = CameraeNextCameraSetupPresentation(
            availableLenses: [.wide],
            selectedLens: .wide,
            preferredLens: .wide,
            lockedLens: policy.lockedLens,
            lockedZoomFactor: policy.lockedZoomFactor
        )

        #expect(policy.lockedLens == .wide)
        #expect(policy.lockedZoomFactor == 2)
        #expect(policy.accepts(lens: .wide, zoomFactor: 2))
        #expect(!policy.accepts(lens: .telephoto, zoomFactor: 2))
        #expect(!policy.accepts(lens: .wide, zoomFactor: 1))
        #expect(presentation.state == .locked)
        #expect(presentation.detail.contains("zoom 2×"))
    }

    @Test("an imported reference does not choose a camera for the project")
    func importedReferenceDoesNotLockCamera() {
        let importedReference = sessionSummary(
            kind: .photo,
            frameCount: 1,
            lens: nil
        )

        let policy = CameraeNextProjectCameraPolicy(summaries: [importedReference])

        #expect(!policy.isLocked)
    }

    @Test("reference photo metadata identifies the physical lens and digital zoom")
    func referencePhotoMetadata() {
        let ultraWide = CameraeNextReferenceCameraMetadataResolver.resolve(
            metadata: [
                "{Exif}": [
                    "LensModel": "iPhone back ultra wide camera 1.54mm f/2.4",
                    "FocalLenIn35mmFilm": 13,
                    "DigitalZoomRatio": 1
                ]
            ],
            fallbackLens: .wide
        )
        let croppedWide = CameraeNextReferenceCameraMetadataResolver.resolve(
            metadata: [
                "{Exif}": [
                    "LensModel": "iPhone back triple camera 6.765mm f/1.78",
                    "FocalLenIn35mmFilm": 48,
                    "DigitalZoomRatio": 2
                ]
            ],
            fallbackLens: .ultraWide
        )
        let telephoto = CameraeNextReferenceCameraMetadataResolver.resolve(
            metadata: [
                "{Exif}": [
                    "FocalLenIn35mmFilm": 77
                ]
            ],
            fallbackLens: .wide
        )

        #expect(ultraWide.lens == .ultraWide)
        #expect(ultraWide.zoomFactor == 1)
        #expect(croppedWide.lens == .wide)
        #expect(croppedWide.zoomFactor == 2)
        #expect(telephoto.lens == .telephoto)
        #expect(telephoto.zoomFactor == 1)
    }

    @Test("missing reference metadata keeps the selected camera safely")
    func missingReferencePhotoMetadata() {
        let selection = CameraeNextReferenceCameraMetadataResolver.resolve(
            metadata: [:],
            fallbackLens: .telephoto
        )

        #expect(selection.lens == .telephoto)
        #expect(selection.zoomFactor == 1)
    }

    @Test("a locked lens never falls back silently when unavailable")
    func unavailableLockedLensBlocksCapture() {
        let presentation = CameraeNextCameraSetupPresentation(
            availableLenses: [.wide],
            selectedLens: .telephoto,
            preferredLens: .wide,
            lockedLens: .telephoto
        )

        #expect(presentation.state == .lockedUnavailable)
        #expect(!presentation.canStart)
        #expect(presentation.status == "BLOQUEADA")
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

    private func sessionSummary(
        kind: RepeatableCaptureKind,
        module: CameraModule = .repeatable,
        frameCount: Int,
        videoClipURL: URL? = nil,
        isAstroProcessed: Bool = false,
        createdAt: Date = Date(),
        lens: RepeatableCameraLens?,
        zoomFactor: Double? = nil
    ) -> TimelapseSessionSummary {
        let session = TimelapseSession(
            id: UUID(),
            projectID: UUID(),
            module: module,
            captureKind: kind,
            referenceMotion: nil,
            referenceGeoPose: nil,
            referenceOrientation: nil,
            cameraLens: lens,
            cameraZoomFactor: zoomFactor,
            name: "fixture",
            directoryURL: URL(fileURLWithPath: "/tmp/fixture-\(UUID().uuidString)"),
            createdAt: createdAt
        )
        return TimelapseSessionSummary(
            session: session,
            captureKind: kind,
            frameCount: frameCount,
            captureDuration: nil,
            referenceFrameURL: frameCount > 0 ? session.directoryURL.appendingPathComponent("frame_000001.jpg") : nil,
            videoURL: nil,
            videoClipURL: videoClipURL,
            isAstroProcessed: isAstroProcessed,
            hasRenderedOutput: videoClipURL != nil
        )
    }
}

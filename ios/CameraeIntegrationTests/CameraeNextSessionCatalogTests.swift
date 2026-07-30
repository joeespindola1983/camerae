import Foundation
import Testing
@testable import Camerae

struct CameraeNextSessionCatalogTests {
    @Test func repeatableProjectStartsOnConfigurationWithPersistentTabs() {
        let state = CameraeNextRepeatableProjectWorkspaceState()

        #expect(state.section == .configuration)
        #expect(
            CameraeNextProjectSection.visibleSections(
                spatialGuidanceAvailability: .available,
                hasSpatialReference: false
            )
                .map(\.title) == ["Configurar", "Tripé", "Capturas"]
        )
        #expect(
            CameraeNextProjectSection.visibleSections(
                spatialGuidanceAvailability: .hardwareUnavailable,
                hasSpatialReference: false
            )
                .map(\.title) == ["Configurar", "Capturas"]
        )
    }

    @Test func savedSpatialGuideRemainsDiscoverableOnAnIncompatibleDevice() {
        #expect(
            CameraeNextProjectSection.visibleSections(
                spatialGuidanceAvailability: .hardwareUnavailable,
                hasSpatialReference: true
            ).map(\.title) == ["Configurar", "Tripé", "Capturas"]
        )
        #expect(
            SpatialGuidanceInterfaceCapabilityPolicy.actions(for: .incompatibleReference) ==
                [.remapReference, .continueWithoutReference]
        )
    }

    @Test func projectTabLabelsExposeTripodStatusAndCaptureCount() {
        #expect(
            CameraeNextProjectTabPresentation(
                section: .tripod,
                hasTripodReference: true,
                captureCount: 4
            ).systemImage == "checkmark.circle.fill"
        )
        #expect(
            CameraeNextProjectTabPresentation(
                section: .tripod,
                hasTripodReference: false,
                captureCount: 4
            ).systemImage == "circle.dashed"
        )
        #expect(
            CameraeNextProjectTabPresentation(
                section: .captures,
                hasTripodReference: true,
                captureCount: 4
            ).title == "Capturas (4)"
        )
    }

    @Test func completedRepeatableCaptureReturnsToCatalogWhileFinalizingInline() {
        var state = CameraeNextRepeatableProjectWorkspaceState()

        state.captureDidFinish()

        #expect(state.section == .captures)
        #expect(state.isFinalizingCapture)
        #expect(CameraeNextCaptureCompletionRoute(module: .repeatable) == .projectCaptures)
    }

    @Test func catalogReloadFinishesInlineProgressAndNewCaptureReturnsToConfiguration() {
        var state = CameraeNextRepeatableProjectWorkspaceState()
        state.captureDidFinish()

        state.catalogDidReload()
        #expect(!state.isFinalizingCapture)

        state.startNewCapture()
        #expect(state.section == .configuration)
    }

    @Test func astroStillUsesItsDedicatedCompletionFlow() {
        #expect(CameraeNextCaptureCompletionRoute(module: .astrophotography) == .completionScreen)
    }

    @Test func openingReadyRepeatableCaptureRoutesToFullScreenVideo() {
        let url = URL(fileURLWithPath: "/tmp/timelapse.mp4")
        let summary = fixture(frameCount: 8, videoURL: url)

        #expect(CameraeNextSessionOpenRoute(summary: summary) == .video(url))
    }

    @Test func openingRepeatablePhotoRoutesToFullScreenImage() {
        let url = URL(fileURLWithPath: "/tmp/photo.heic")
        let summary = fixture(
            frameCount: 1,
            captureKind: .photo,
            purpose: .capture,
            referenceFrameURL: url
        )

        #expect(CameraeNextSessionOpenRoute(summary: summary) == .image(url))
        let presentation = CameraeNextSessionCardPresentation(summary: summary)
        #expect(presentation.trailingAction == .share(url))
        #expect(presentation.captureType == .init(title: "Foto", systemImage: "camera.fill"))
    }

    @Test(
        "every capture card exposes an obvious typed icon independent of its layout",
        arguments: [
            (RepeatableCaptureKind.photo, "Foto", "camera.fill"),
            (RepeatableCaptureKind.video, "Vídeo", "video.fill"),
            (RepeatableCaptureKind.timelapse, "Timelapse", "timelapse"),
        ]
    )
    func captureTypeIcon(
        kind: RepeatableCaptureKind,
        title: String,
        systemImage: String
    ) {
        let presentation = CameraeNextSessionCardPresentation(
            summary: fixture(frameCount: 1, captureKind: kind, purpose: .capture)
        )

        #expect(presentation.captureType.title == title)
        #expect(presentation.captureType.systemImage == systemImage)
    }

    @Test func openingRepeatableCaptureWithoutRenderedVideoNeverStartsCamera() {
        let summary = fixture(frameCount: 8)

        #expect(CameraeNextSessionOpenRoute(summary: summary) == .generateVideo)
    }

    @Test func readyCaptureShowsPlaybackStatusAndSeparateShareAction() {
        let url = URL(fileURLWithPath: "/tmp/timelapse.mp4")
        let presentation = CameraeNextSessionCardPresentation(
            summary: fixture(frameCount: 8, videoURL: url)
        )

        #expect(presentation.statusText == "TOQUE PARA REPRODUZIR")
        #expect(presentation.trailingAction == .share(url))
    }

    @Test func recordedVideoKeepsPlaybackOnTheCardAndExposesAlignmentMenu() {
        let url = URL(fileURLWithPath: "/tmp/capture.mp4")
        let summary = fixture(
            frameCount: 1,
            videoClipURL: url,
            captureKind: .video,
            referenceFrameURL: URL(fileURLWithPath: "/tmp/reference.jpg")
        )

        #expect(CameraeNextSessionOpenRoute(summary: summary) == .video(url))
        let presentation = CameraeNextSessionCardPresentation(summary: summary)
        #expect(presentation.statusText == "TOQUE PARA REPRODUZIR")
        #expect(presentation.trailingAction == .videoMenu(url))
    }

    @Test func alignedVideoBecomesTheDefaultPlayerAndShareArtifact() {
        let originalURL = URL(fileURLWithPath: "/tmp/capture.mov")
        let alignedURL = URL(fileURLWithPath: "/tmp/aligned.mp4")
        let summary = fixture(
            frameCount: 1,
            videoClipURL: originalURL,
            alignedVideoURL: alignedURL,
            captureKind: .video
        )

        #expect(CameraeNextSessionOpenRoute(summary: summary) == .video(alignedURL))
        #expect(
            CameraeNextSessionCardPresentation(summary: summary).trailingAction ==
                .videoMenu(alignedURL)
        )
    }

    @Test func captureWithoutMP4ShowsGenerationStatusAndMenu() {
        let presentation = CameraeNextSessionCardPresentation(summary: fixture(frameCount: 8))

        #expect(presentation.statusText == "MP4 AINDA NÃO GERADO")
        #expect(presentation.trailingAction == .menu)
    }

    @Test func generateVideoPromptMatchesFigmaActions() {
        let prompt = CameraeNextGenerateVideoPrompt()

        #expect(prompt.title == "Configurar geração do MP4?")
        #expect(prompt.primaryActionTitle == "Configurar MP4")
        #expect(prompt.secondaryActionTitle == "Agora não")
        #expect(prompt.message.contains("frame de referência"))
        #expect(prompt.message.contains("sem correção"))
    }

    @Test func videoAlignmentPromptUsesTheProjectReferenceFrame() {
        let prompt = CameraeNextProcessVideoAlignmentPrompt()

        #expect(prompt.title == "Processar alinhamento do vídeo?")
        #expect(prompt.primaryActionTitle == "Processar alinhamento")
        #expect(prompt.secondaryActionTitle == "Agora não")
        #expect(prompt.message.contains("frame de referência do projeto"))
    }

    @Test func theReferenceVideoHidesAlignmentWhileLaterVideosRemainAlignable() {
        let first = fixture(
            frameCount: 1,
            videoClipURL: URL(fileURLWithPath: "/tmp/first.mov"),
            captureKind: .video
        )
        let second = fixture(
            frameCount: 1,
            videoClipURL: URL(fileURLWithPath: "/tmp/second.mov"),
            captureKind: .video
        )
        let referenceURL = URL(fileURLWithPath: "/tmp/reference.jpg")

        #expect(CameraeNextSessionAlignmentAvailability(
            summary: first,
            projectReferenceURL: referenceURL,
            referenceSessionID: first.id
        ) == .referenceClip)
        #expect(!CameraeNextSessionAlignmentAvailability(
            summary: first,
            projectReferenceURL: referenceURL,
            referenceSessionID: first.id
        ).showsAlignmentAction)
        #expect(CameraeNextSessionAlignmentAvailability(
            summary: second,
            projectReferenceURL: referenceURL,
            referenceSessionID: first.id
        ) == .available)
        #expect(CameraeNextSessionAlignmentAvailability(
            summary: second,
            projectReferenceURL: referenceURL,
            referenceSessionID: first.id
        ).showsAlignmentAction)
    }

    @Test func alignmentEligibilityNeverDependsOnAnotherVideo() {
        let video = fixture(
            frameCount: 1,
            videoClipURL: URL(fileURLWithPath: "/tmp/only.mov"),
            captureKind: .video
        )

        #expect(CameraeNextSessionAlignmentAvailability(
            summary: video,
            projectReferenceURL: URL(fileURLWithPath: "/tmp/reference.jpg")
        ) == .available)
        #expect(CameraeNextSessionAlignmentAvailability(
            summary: video,
            projectReferenceURL: nil
        ) == .referenceUnavailable)
    }

    @Test func visibleCatalogReferenceIsUsedWhenProjectSummaryHasNoReference() {
        let visibleReferenceURL = URL(fileURLWithPath: "/tmp/first-captured-frame.jpg")

        #expect(CameraeNextSessionAlignmentReference.resolve(
            projectReferenceURL: nil,
            catalogReferenceURL: visibleReferenceURL
        ) == visibleReferenceURL)
    }

    @Test func visibleCatalogReferenceWinsOverAStaleProjectSummaryReference() {
        let staleProjectURL = URL(fileURLWithPath: "/tmp/stale-reference.jpg")
        let visibleReferenceURL = URL(fileURLWithPath: "/tmp/current-reference.jpg")

        #expect(CameraeNextSessionAlignmentReference.resolve(
            projectReferenceURL: staleProjectURL,
            catalogReferenceURL: visibleReferenceURL
        ) == visibleReferenceURL)
    }

    @Test func videoAlignmentUsesTheOldestVideoFrameWithoutReplacingTheVisiblePhotoReference() {
        let photoURL = URL(fileURLWithPath: "/tmp/reference-photo.jpg")
        let firstVideoFrameURL = URL(fileURLWithPath: "/tmp/first-video-frame.jpg")
        let laterVideoFrameURL = URL(fileURLWithPath: "/tmp/later-video-frame.jpg")
        let photo = fixture(
            frameCount: 1,
            captureKind: .photo,
            referenceFrameURL: photoURL,
            createdAt: Date(timeIntervalSince1970: 300)
        )
        let firstVideo = fixture(
            frameCount: 1,
            videoClipURL: URL(fileURLWithPath: "/tmp/first.mov"),
            captureKind: .video,
            referenceFrameURL: firstVideoFrameURL,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let laterVideo = fixture(
            frameCount: 1,
            videoClipURL: URL(fileURLWithPath: "/tmp/later.mov"),
            captureKind: .video,
            referenceFrameURL: laterVideoFrameURL,
            createdAt: Date(timeIntervalSince1970: 200)
        )

        let catalog = CameraeNextSessionCatalogModel(
            summaries: [photo, laterVideo, firstVideo]
        )

        #expect(catalog.referenceFrameURL == photoURL)
        #expect(catalog.alignmentReferenceFrameURL == firstVideoFrameURL)
        #expect(catalog.alignmentReferenceSessionID == firstVideo.id)
        #expect(CameraeNextSessionAlignmentReference.resolve(
            projectReferenceURL: photoURL,
            catalogReferenceURL: catalog.referenceFrameURL,
            geometricReferenceURL: catalog.alignmentReferenceFrameURL
        ) == firstVideoFrameURL)
    }

    @Test func legacyVideoWithoutAReferenceFrameNeverBecomesTheAlignmentReference() {
        let legacyVideo = fixture(
            frameCount: 1,
            videoClipURL: URL(fileURLWithPath: "/tmp/legacy.mov"),
            captureKind: .video,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let usableReferenceURL = URL(fileURLWithPath: "/tmp/usable-reference.jpg")
        let usableVideo = fixture(
            frameCount: 1,
            videoClipURL: URL(fileURLWithPath: "/tmp/usable.mov"),
            captureKind: .video,
            referenceFrameURL: usableReferenceURL,
            createdAt: Date(timeIntervalSince1970: 200)
        )

        let catalog = CameraeNextSessionCatalogModel(
            summaries: [usableVideo, legacyVideo]
        )

        #expect(catalog.alignmentReferenceFrameURL == usableReferenceURL)
        #expect(catalog.alignmentReferenceSessionID == usableVideo.id)
    }

    @Test func astroCaptureKeepsProcessingDestination() {
        let summary = fixture(frameCount: 8, module: .astrophotography)

        #expect(CameraeNextSessionOpenRoute(summary: summary) == .astroProcessing)
    }

    @Test func astroCardKeepsProcessingLanguageInsteadOfMP4Prompt() {
        let presentation = CameraeNextSessionCardPresentation(
            summary: fixture(frameCount: 8, module: .astrophotography)
        )

        #expect(presentation.statusText == "ABRIR PROCESSAMENTO")
        #expect(presentation.trailingAction == .menu)
    }

    @Test func catalogHidesEmptyCaptureShells() {
        let summaries = [fixture(frameCount: 0), fixture(frameCount: 8)]
        let catalog = CameraeNextSessionCatalogModel(summaries: summaries)

        #expect(catalog.sessions.count == 1)
        #expect(catalog.totalFrames == 8)
    }

    @Test func explicitReferenceIsUniqueFirstAndExcludedFromCaptures() {
        let oldReferenceURL = URL(fileURLWithPath: "/tmp/reference-old.jpg")
        let newReferenceURL = URL(fileURLWithPath: "/tmp/reference-new.jpg")
        let capture = fixture(
            frameCount: 8,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let oldReference = fixture(
            frameCount: 1,
            captureKind: .photo,
            referenceFrameURL: oldReferenceURL,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let newReference = fixture(
            frameCount: 1,
            captureKind: .photo,
            referenceFrameURL: newReferenceURL,
            createdAt: Date(timeIntervalSince1970: 300)
        )

        let catalog = CameraeNextSessionCatalogModel(
            summaries: [oldReference, capture, newReference]
        )

        #expect(catalog.referenceFrameURL == newReferenceURL)
        #expect(catalog.sessions.map(\.captureKind) == [.timelapse])
        #expect(catalog.totalFrames == 8)
    }

    @Test func oldestCapturedFrameBecomesAutomaticReferenceWhenNoExplicitReferenceExists() {
        let firstURL = URL(fileURLWithPath: "/tmp/first.jpg")
        let laterURL = URL(fileURLWithPath: "/tmp/later.jpg")
        let first = fixture(
            frameCount: 4,
            referenceFrameURL: firstURL,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let later = fixture(
            frameCount: 4,
            referenceFrameURL: laterURL,
            createdAt: Date(timeIntervalSince1970: 200)
        )

        let catalog = CameraeNextSessionCatalogModel(summaries: [later, first])

        #expect(catalog.referenceFrameURL == firstURL)
        #expect(catalog.sessions.map(\.session.id) == [later.session.id, first.session.id])
    }

    @Test func summaryUsesModuleSpecificLanguage() {
        #expect(CameraeNextSessionCatalogPresentation(module: .repeatable).title == "Capturas Repeatable")
        #expect(CameraeNextSessionCatalogPresentation(module: .astrophotography).title == "Sessões Astro")
    }

    private func fixture(
        frameCount: Int,
        module: CameraModule = .repeatable,
        videoURL: URL? = nil,
        videoClipURL: URL? = nil,
        alignedVideoURL: URL? = nil,
        captureKind: RepeatableCaptureKind = .timelapse,
        purpose: TimelapseSession.Purpose? = nil,
        referenceFrameURL: URL? = nil,
        createdAt: Date = .now
    ) -> TimelapseSessionSummary {
        let session = TimelapseSession(
            id: UUID(),
            projectID: UUID(),
            module: module,
            captureKind: captureKind,
            purpose: purpose ?? (module == .repeatable && captureKind == .photo ? .projectReference : .capture),
            referenceMotion: nil,
            referenceGeoPose: nil,
            referenceOrientation: nil,
            cameraLens: nil,
            name: "Sessão",
            directoryURL: URL(fileURLWithPath: "/tmp/session"),
            createdAt: createdAt
        )
        return TimelapseSessionSummary(
            session: session,
            captureKind: captureKind,
            frameCount: frameCount,
            captureDuration: nil,
            referenceFrameURL: referenceFrameURL,
            videoURL: videoURL,
            videoClipURL: videoClipURL,
            alignedVideoURL: alignedVideoURL,
            isAstroProcessed: false,
            hasRenderedOutput: false
        )
    }
}

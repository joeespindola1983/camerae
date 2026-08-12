import Foundation
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

    @Test("project hardware stays provisional until captured media confirms the contract")
    func projectHardwareLockAndCaptureTypeDefaults() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeCaptureDefaults-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ProjectCaptureConfigurationStore(projectDirectory: directory)
        var initialVideo = CameraeNextCaptureConfiguration.repeatableDefault
        initialVideo.repeatableKind = .video
        initialVideo.videoDurationSeconds = 120
        initialVideo.videoSettings = WorkflowVideoSettings(resolution: .fourK, fps: 30, quality: .max)
        initialVideo.cameraLens = .telephoto
        initialVideo.cameraZoomFactor = 2
        var laterTimelapse = CameraeNextCaptureConfiguration.repeatableDefault
        laterTimelapse.durationMinutes = 15
        laterTimelapse.intervalSeconds = 3
        laterTimelapse.cameraLens = .wide
        laterTimelapse.cameraZoomFactor = 1

        let first = try store.saveDefaults(initialVideo)
        let provisional = try store.saveDefaults(laterTimelapse)
        let provisionalProfile = try #require(try store.loadProfile())

        #expect(first == initialVideo)
        #expect(provisional.repeatableKind == .timelapse)
        #expect(provisional.durationMinutes == 15)
        #expect(provisional.intervalSeconds == 3)
        #expect(provisional.cameraLens == .wide)
        #expect(provisional.cameraZoomFactor == 1)
        #expect(!provisionalProfile.isHardwareLocked)
        #expect(provisionalProfile.hardware == .init(cameraLens: .wide, cameraZoomFactor: 1))

        let firstCapture = makeLegacySummary(
            directory: directory,
            kind: .timelapse,
            frameCount: 1,
            duration: 0,
            lens: .wide,
            zoom: 1,
            fileExtension: "heic"
        )
        let lockedProfile = try #require(
            try store.loadProfileOrMigrate(module: .repeatable, summaries: [firstCapture])
        )
        var laterPhoto = CameraeNextCaptureConfiguration.repeatableDefault
        laterPhoto.repeatableKind = .photo
        laterPhoto.cameraLens = .telephoto
        laterPhoto.cameraZoomFactor = 2
        let normalizedPhoto = try store.saveDefaults(laterPhoto)
        let profile = try #require(try store.loadProfile())

        #expect(lockedProfile.isHardwareLocked)
        #expect(normalizedPhoto.cameraLens == .wide)
        #expect(normalizedPhoto.cameraZoomFactor == 1)
        #expect(profile.hardware == .init(cameraLens: .wide, cameraZoomFactor: 1))
        #expect(profile.configuration(for: .video).videoSettings == initialVideo.videoSettings)
        #expect(profile.configuration(for: .video).videoDurationSeconds == 120)
        #expect(profile.configuration(for: .timelapse).intervalSeconds == 3)
        #expect(profile.configuration(for: .photo).repeatableKind == .photo)
        #expect(profile.selectedKind == .photo)
    }

    @Test("captured legacy projects migrate once into hardware plus per-type defaults")
    func legacyProjectConfigurationMigration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeLegacyCapture-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ProjectCaptureConfigurationStore(projectDirectory: directory)
        let firstCapture = makeLegacySummary(
            directory: directory,
            kind: .timelapse,
            frameCount: 121,
            duration: 600,
            lens: .telephoto,
            zoom: 2,
            fileExtension: "jpg"
        )

        let migratedConfiguration = try store.loadOrMigrate(
            module: .repeatable,
            summaries: [firstCapture]
        )
        let migrated = try #require(migratedConfiguration)

        #expect(migrated.repeatableKind == .timelapse)
        #expect(migrated.durationMinutes == 10)
        #expect(abs(migrated.intervalSeconds - 5) < 0.001)
        #expect(migrated.cameraLens == .telephoto)
        #expect(migrated.cameraZoomFactor == 2)
        #expect(migrated.sourceFormat == .jpeg)
        let migratedProfile = try #require(try store.loadProfile())
        #expect(migratedProfile.isHardwareLocked)
        #expect(migratedProfile.hardware.cameraLens == .telephoto)
        #expect(migratedProfile.hardware.cameraZoomFactor == 2)
        #expect(migratedProfile.configuration(for: .photo).repeatableKind == .photo)
        #expect(migratedProfile.configuration(for: .video).repeatableKind == .video)

        let laterVideo = makeLegacySummary(
            directory: directory,
            kind: .video,
            frameCount: 0,
            duration: 30,
            lens: .wide,
            zoom: 1,
            fileExtension: "mp4",
            hasVideo: true
        )
        let resolvedAgain = try store.loadOrMigrate(module: .repeatable, summaries: [laterVideo])
        #expect(resolvedAgain == migrated)
    }

    @Test("empty legacy projects stay configurable because there is no capture contract to migrate")
    func emptyLegacyProjectDoesNotMigrate() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeEmptyLegacy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProjectCaptureConfigurationStore(projectDirectory: directory)

        #expect(try store.loadOrMigrate(module: .repeatable, summaries: []) == nil)
    }

    @Test("capture configuration migrates schema one and rejects unsupported future schemas")
    func captureConfigurationSchemaCompatibility() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeConfigurationSchema-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("capture_configuration.json")
        let store = ProjectCaptureConfigurationStore(projectDirectory: directory)
        let configuration = CameraeNextCaptureConfiguration.repeatableDefault

        try writeConfigurationDocument(
            schemaVersion: 1,
            configuration: configuration,
            to: fileURL
        )
        let migrated = try #require(
            try store.loadProfileOrMigrate(module: .repeatable, summaries: [])
        )
        #expect(migrated.selectedConfiguration == configuration)
        #expect(migrated.configuration(for: .photo).repeatableKind == .photo)
        #expect(migrated.configuration(for: .video).repeatableKind == .video)
        #expect(migrated.configuration(for: .timelapse).repeatableKind == .timelapse)
        #expect(!migrated.isHardwareLocked)
        #expect(try store.loadProfile() == migrated)

        try writeConfigurationDocument(
            schemaVersion: 99,
            configuration: configuration,
            to: fileURL
        )
        #expect(throws: ProjectCaptureConfigurationError.unsupportedSchema(99)) {
            try store.load()
        }
    }

    @Test("schema three hardware migrates from provisional to captured state exactly once")
    func schemaThreeHardwareLockMigration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeConfigurationSchemaThree-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("capture_configuration.json")
        let store = ProjectCaptureConfigurationStore(projectDirectory: directory)
        var configuration = CameraeNextCaptureConfiguration.repeatableDefault
        configuration.cameraLens = .telephoto
        let legacyProfile = ProjectCaptureProfile(initialConfiguration: configuration)

        try writeProfileDocument(schemaVersion: 3, profile: legacyProfile, to: fileURL)
        let emptyMigration = try #require(
            try store.loadProfileOrMigrate(module: .repeatable, summaries: [])
        )
        #expect(!emptyMigration.isHardwareLocked)

        try writeProfileDocument(schemaVersion: 3, profile: legacyProfile, to: fileURL)
        let captured = makeLegacySummary(
            directory: directory,
            kind: .timelapse,
            frameCount: 1,
            duration: 0,
            lens: .ultraWide,
            zoom: 1,
            fileExtension: "heic"
        )
        let capturedMigration = try #require(
            try store.loadProfileOrMigrate(module: .repeatable, summaries: [captured])
        )
        #expect(capturedMigration.isHardwareLocked)
        #expect(capturedMigration.hardware.cameraLens == .ultraWide)
        #expect(try store.loadProfile() == capturedMigration)
    }

    @Test(
        "photo, timelapse, and video remain available in every Repeatable project",
        arguments: RepeatableCaptureKind.captureOptions
    )
    func projectCaptureKind(kind: RepeatableCaptureKind) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeCaptureKind-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ProjectCaptureConfigurationStore(projectDirectory: directory)
        var configuration = CameraeNextCaptureConfiguration.repeatableDefault
        configuration.repeatableKind = kind

        _ = try store.saveDefaults(configuration)

        let profile = try #require(try store.loadProfile())
        #expect(profile.selectedKind == kind)
        #expect(profile.configuration(for: kind).repeatableKind == kind)
        #expect(
            CameraeNextProjectCaptureCapabilityPolicy.repeatable.availableCaptureKinds ==
                [.photo, .video, .timelapse]
        )
        #expect(CameraeNextProjectCaptureCapabilityPolicy.repeatable.locksCameraHardware)
        #expect(CameraeNextProjectCaptureCapabilityPolicy.repeatable.allowsEditingCaptureDefaults)
    }

    private func makeLegacySummary(
        directory: URL,
        kind: RepeatableCaptureKind,
        frameCount: Int,
        duration: TimeInterval,
        lens: RepeatableCameraLens,
        zoom: Double,
        fileExtension: String,
        hasVideo: Bool = false,
        createdAt: Date = Date(timeIntervalSince1970: 1)
    ) -> TimelapseSessionSummary {
        let sessionDirectory = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let session = TimelapseSession(
            id: UUID(),
            projectID: UUID(),
            module: .repeatable,
            captureKind: kind,
            purpose: .capture,
            referenceMotion: nil,
            referenceGeoPose: nil,
            referenceOrientation: nil,
            cameraLens: lens,
            cameraZoomFactor: zoom,
            name: "legacy",
            directoryURL: sessionDirectory,
            createdAt: createdAt
        )
        return TimelapseSessionSummary(
            session: session,
            captureKind: kind,
            frameCount: frameCount,
            captureDuration: duration,
            referenceFrameURL: sessionDirectory.appendingPathComponent("frame_0001.\(fileExtension)"),
            videoURL: hasVideo ? sessionDirectory.appendingPathComponent("capture.mp4") : nil,
            videoClipURL: nil,
            alignedVideoURL: nil,
            renderedAstroVideoURL: nil,
            isAstroProcessed: false,
            hasRenderedOutput: hasVideo
        )
    }

    private func writeConfigurationDocument(
        schemaVersion: Int,
        configuration: CameraeNextCaptureConfiguration,
        to fileURL: URL
    ) throws {
        let configurationData = try JSONEncoder().encode(configuration)
        let configurationObject = try JSONSerialization.jsonObject(with: configurationData)
        let document: [String: Any] = [
            "schemaVersion": schemaVersion,
            "configuration": configurationObject
        ]
        try JSONSerialization.data(withJSONObject: document)
            .write(to: fileURL, options: .atomic)
    }

    private func writeProfileDocument(
        schemaVersion: Int,
        profile: ProjectCaptureProfile,
        to fileURL: URL
    ) throws {
        let profileData = try JSONEncoder().encode(profile)
        var profileObject = try #require(
            JSONSerialization.jsonObject(with: profileData) as? [String: Any]
        )
        profileObject.removeValue(forKey: "isHardwareLocked")
        let document: [String: Any] = [
            "schemaVersion": schemaVersion,
            "origin": "updatedDefaults",
            "profile": profileObject
        ]
        try JSONSerialization.data(withJSONObject: document)
            .write(to: fileURL, options: .atomic)
    }

    @Test("Astro starts from the photo stacking defaults")
    func astroDefaults() {
        let configuration = CameraeNextCaptureConfiguration.astroDefault

        #expect(configuration.module == .astrophotography)
        #expect(configuration.repeatableKind == .photo)
        #expect(!configuration.usesAutomaticAstroExposure)
        #expect(configuration.cameraLens == .wide)
        #expect(configuration.cameraZoomFactor == 1)
        #expect(configuration.sourceFormat == .dng)
        #expect(configuration.astroExposureSeconds == 8)
        #expect(configuration.intervalSeconds == 8)
        #expect(configuration.astroPhotoStackCount == .ten)
        #expect(configuration.estimatedFrameCount == 10)
    }

    @Test("estimated frame count follows each workflow interval")
    func frameEstimate() {
        var repeatable = CameraeNextCaptureConfiguration.repeatableDefault
        repeatable.durationMinutes = 15
        repeatable.intervalSeconds = 5
        #expect(repeatable.estimatedFrameCount == 180)

        var astro = CameraeNextCaptureConfiguration.astroDefault
        astro.repeatableKind = .timelapse
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

        #expect(presentation.navigationTitle == CameraeL10n.newTimelapse)
        #expect(presentation.primaryActionTitle == CameraeL10n.openCamera)
        #expect(presentation.captureSectionTitle == CameraeL10n.captureSection)
        #expect(presentation.adjustmentsSectionTitle == CameraeL10n.adjustmentsSection)
        #expect(presentation.adjustmentTitles == ["EV", CameraeL10n.interval])
        #expect(presentation.cameraPresentation == .selector)
    }

    @Test("Repeatable video and timelapse expose different configuration contracts")
    func repeatableModes() {
        var video = CameraeNextCaptureConfiguration.repeatableDefault
        video.repeatableKind = .video
        let videoPresentation = CameraeNextWorkflowConfigurationPresentation(configuration: video)
        let timelapsePresentation = CameraeNextWorkflowConfigurationPresentation(configuration: .repeatableDefault)

        #expect(videoPresentation.navigationTitle == CameraeL10n.newVideo)
        #expect(videoPresentation.durationLabels == ["30 s", "1 min", "2 min", CameraeL10n.customDurationShort])
        #expect(videoPresentation.adjustmentTitles == ["EV"])
        #expect(videoPresentation.durationLabels == ["30 s", "1 min", "2 min", CameraeL10n.customDurationShort])
        #expect(videoPresentation.showsVideoSettings)
        #expect(!videoPresentation.showsInterval)
        #expect(video.estimatedFrameCount == video.videoDurationSeconds * video.videoSettings.fps)

        #expect(timelapsePresentation.navigationTitle == CameraeL10n.newTimelapse)
        #expect(!timelapsePresentation.showsVideoSettings)
        #expect(timelapsePresentation.showsInterval)
    }

    @Test("A saved custom duration remains selected without changing the persisted value")
    func restoredCustomDurationSelection() {
        var video = CameraeNextCaptureConfiguration.repeatableDefault
        video.repeatableKind = .video
        video.videoDurationSeconds = 720

        #expect(CameraeNextDurationSelection(configuration: video).selectedValue == 0)
        #expect(video.videoDurationSeconds == 720)

        video.videoDurationSeconds = 60
        #expect(CameraeNextDurationSelection(configuration: video).selectedValue == 60)

        var timelapse = CameraeNextCaptureConfiguration.repeatableDefault
        timelapse.durationMinutes = 10
        #expect(CameraeNextDurationSelection(configuration: timelapse).selectedValue == 0)
        #expect(timelapse.durationMinutes == 10)
    }

    @Test("Recorded video durations close to a preset restore the intended preset")
    func recordedVideoDurationNormalization() {
        #expect(CameraeNextVideoDurationPolicy.normalized(29) == 30)
        #expect(CameraeNextVideoDurationPolicy.normalized(59) == 60)
        #expect(CameraeNextVideoDurationPolicy.normalized(119) == 120)
        #expect(CameraeNextVideoDurationPolicy.normalized(25) == 25)

        var recordedVideo = CameraeNextCaptureConfiguration.repeatableDefault
        recordedVideo.repeatableKind = .video
        recordedVideo.videoDurationSeconds = 29
        let profile = ProjectCaptureProfile(initialConfiguration: recordedVideo)

        #expect(profile.selectedConfiguration.videoDurationSeconds == 30)
        #expect(CameraeNextDurationSelection(configuration: profile.selectedConfiguration).selectedValue == 30)
    }

    @Test("The latest recorded clip refreshes the project's video duration default")
    func latestClipRefreshesVideoDefault() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeLatestVideoDefault-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ProjectCaptureConfigurationStore(projectDirectory: directory)
        var savedVideo = CameraeNextCaptureConfiguration.repeatableDefault
        savedVideo.repeatableKind = .video
        savedVideo.videoDurationSeconds = 60
        _ = try store.saveDefaults(savedVideo)

        let olderClip = makeLegacySummary(
            directory: directory,
            kind: .video,
            frameCount: 0,
            duration: 60,
            lens: .wide,
            zoom: 1,
            fileExtension: "mp4",
            hasVideo: true,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let latestClip = makeLegacySummary(
            directory: directory,
            kind: .video,
            frameCount: 0,
            duration: 29,
            lens: .wide,
            zoom: 1,
            fileExtension: "mp4",
            hasVideo: true,
            createdAt: Date(timeIntervalSince1970: 2)
        )

        let refreshed = try #require(
            try store.loadProfileOrMigrate(
                module: .repeatable,
                summaries: [olderClip, latestClip]
            )
        )

        #expect(refreshed.configuration(for: .video).videoDurationSeconds == 30)
        #expect(try store.loadProfile()?.configuration(for: .video).videoDurationSeconds == 30)
    }

    @Test("Repeatable photo is a single-frame workflow without timed or Astro controls")
    func repeatablePhotoMode() {
        var photo = CameraeNextCaptureConfiguration.repeatableDefault
        photo.repeatableKind = .photo
        let presentation = CameraeNextWorkflowConfigurationPresentation(configuration: photo)

        #expect(photo.estimatedFrameCount == 1)
        #expect(presentation.navigationTitle == "Nova foto")
        #expect(presentation.adjustmentTitles == ["EV"])
        #expect(presentation.durationLabels.isEmpty)
        #expect(!presentation.showsInterval)
        #expect(!presentation.showsVideoSettings)
        #expect(!presentation.showsAstroPhotoStacking)
        #expect(CameraeNextCaptureModeOption.repeatableItems.map(\.value) == [.photo, .video, .timelapse])
    }

    @Test("Astro photo presentation uses stacking instead of a duration")
    func astroPresentation() {
        let presentation = CameraeNextWorkflowConfigurationPresentation(
            configuration: .astroDefault
        )

        #expect(presentation.navigationTitle == CameraeL10n.newAstro)
        #expect(presentation.primaryActionTitle == CameraeL10n.openCamera)
        #expect(presentation.captureSectionTitle == CameraeL10n.sessionSection)
        #expect(presentation.adjustmentsSectionTitle == CameraeL10n.astroCaptureSection)
        #expect(presentation.adjustmentTitles == [CameraeL10n.exposure])
        #expect(presentation.durationLabels.isEmpty)
        #expect(presentation.showsAstroPhotoStacking)
        #expect(presentation.cameraPresentation == .lockedStatus(lens: "Wide", zoom: "1×"))
    }

    @Test("Astro modes expose distinct conditional controls")
    func astroModeContracts() {
        var timelapse = CameraeNextCaptureConfiguration.astroDefault
        timelapse.repeatableKind = .timelapse
        let timelapsePresentation = CameraeNextWorkflowConfigurationPresentation(configuration: timelapse)

        var video = CameraeNextCaptureConfiguration.astroDefault
        video.repeatableKind = .video
        let videoPresentation = CameraeNextWorkflowConfigurationPresentation(configuration: video)

        #expect(timelapsePresentation.durationLabels == ["15 min", "30 min", "1 h", CameraeL10n.customDurationShort])
        #expect(timelapsePresentation.showsInterval)
        #expect(!timelapsePresentation.showsVideoSettings)
        #expect(videoPresentation.adjustmentTitles == ["EV"])
        #expect(videoPresentation.showsVideoSettings)
        #expect(!videoPresentation.showsInterval)
    }

    @Test("Duration options preserve the Figma labels for each workflow")
    func durationLabels() {
        #expect(
            CameraeNextWorkflowConfigurationPresentation(configuration: .repeatableDefault)
                .durationLabels == ["15 min", "30 min", "1 h", CameraeL10n.customDurationShort]
        )
        #expect(
            CameraeNextWorkflowConfigurationPresentation(configuration: .astroDefault)
                .durationLabels.isEmpty
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
            alignedVideoURL: nil,
            renderedAstroVideoURL: nil,
            isAstroProcessed: isAstroProcessed,
            hasRenderedOutput: videoClipURL != nil
        )
    }
}

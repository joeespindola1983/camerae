import CameraeCore
import AVFoundation
import Foundation
import Testing
@testable import Camerae

@Suite("Camerae settings")
@MainActor
struct CameraeSettingsTests {
    @Test("4K 60 fps selects a real 4K format instead of the photo-session fallback")
    func videoFormatSelectionHonorsResolutionAndFrameRate() {
        let formats = [
            CameraeVideoFormatCapability(width: 1720, height: 1290, minimumFPS: 1, maximumFPS: 60),
            CameraeVideoFormatCapability(width: 3840, height: 2160, minimumFPS: 24, maximumFPS: 60),
            CameraeVideoFormatCapability(width: 4032, height: 3024, minimumFPS: 1, maximumFPS: 30)
        ]

        #expect(
            CameraeVideoCaptureFormatPolicy.preferredIndex(
                capabilities: formats,
                resolution: .ultraHD,
                framesPerSecond: 60
            ) == 1
        )
        #expect(
            CameraeVideoCaptureFormatPolicy.preferredIndex(
                capabilities: formats,
                resolution: .ultraHD,
                framesPerSecond: 120
            ) == nil
        )
    }

    @Test("video format selection prefers stabilization without lowering resolution or frame rate")
    func videoFormatSelectionPrefersStabilization() {
        let formats = [
            CameraeVideoFormatCapability(
                width: 3840,
                height: 2160,
                minimumFPS: 24,
                maximumFPS: 60
            ),
            CameraeVideoFormatCapability(
                width: 3840,
                height: 2160,
                minimumFPS: 24,
                maximumFPS: 60,
                supportsStandardStabilization: true
            )
        ]

        #expect(
            CameraeVideoCaptureFormatPolicy.preferredIndex(
                capabilities: formats,
                resolution: .ultraHD,
                framesPerSecond: 60
            ) == 1
        )
    }

    @Test("video quality contributes to the actual encoder bitrate")
    func videoQualityControlsEncoderBitrate() {
        let settings = WorkflowVideoSettings(resolution: .fourK, fps: 60, quality: .high)
        #expect(CameraeVideoEncodingPolicy.averageBitRate(settings: settings) == 120_000_000)
    }

    @Test("video stabilization prefers the low-crop standard mode consistently")
    func videoStabilizationUsesStandardMode() {
        #expect(
            CameraeVideoStabilizationPolicy.preferredMode(
                supportedModes: [.cinematic, .standard, .cinematicExtended]
            ) == .standard
        )
        #expect(
            CameraeVideoStabilizationPolicy.preferredMode(supportedModes: []) == .off
        )
    }

    @Test("photo capture quality never exceeds the output capability")
    func photoQualityIsClampedToOutputCapability() {
        #expect(
            CameraePhotoQualityPrioritizationPolicy.resolved(
                requested: .quality,
                maximum: .speed
            ) == .speed
        )
        #expect(
            CameraePhotoQualityPrioritizationPolicy.resolved(
                requested: .quality,
                maximum: .balanced
            ) == .balanced
        )
        #expect(
            CameraePhotoQualityPrioritizationPolicy.resolved(
                requested: .balanced,
                maximum: .quality
            ) == .balanced
        )
    }

    @Test("new installs use the approved capture and privacy defaults")
    func defaults() {
        let defaults = isolatedDefaults()
        let settings = CameraeSettingsStore(defaults: defaults)

        #expect(settings.diagnosticsEnabled)
        #expect(settings.analyticsEnabled)
        #expect(settings.repeatableFormat == .heic)
        #expect(settings.astroFormat == .dng)
        #expect(settings.performanceMode == .automatic)
        #expect(settings.preserveOriginals)
        #expect(settings.lowStorageWarningEnabled)
    }

    @Test("privacy opt-out disables both Firebase collection paths")
    func privacyOptOut() {
        let defaults = isolatedDefaults()
        var appliedConsent: CameraeDiagnosticsConsentState?
        let settings = CameraeSettingsStore(defaults: defaults) {
            appliedConsent = $0
        }

        settings.diagnosticsEnabled = false

        #expect(!settings.effectiveCrashCollectionEnabled)
        #expect(!settings.effectiveAnalyticsCollectionEnabled)
        #expect(appliedConsent == .init(crashlyticsEnabled: false, analyticsEnabled: false))
    }

    @Test("Firebase consent forwards both effective collection states")
    func firebaseConsentBackend() {
        let backend = DiagnosticsConsentBackendSpy()
        let consent = CameraeDiagnosticsConsent(
            backend: backend,
            isCollectionAllowed: false
        )

        consent.apply(.init(crashlyticsEnabled: true, analyticsEnabled: true))

        #expect(backend.crashlyticsStates == [false])
        #expect(backend.analyticsStates == [false])

        consent.configure(isCollectionAllowed: true)
        consent.apply(.init(crashlyticsEnabled: true, analyticsEnabled: false))
        #expect(backend.crashlyticsStates == [false, true])
        #expect(backend.analyticsStates == [false, false])
    }

    @Test("performance modes resolve capture quality and processing cadence")
    func performancePolicy() {
        #expect(CameraePerformancePolicy(mode: .economy).photoQuality == .speed)
        #expect(CameraePerformancePolicy(mode: .economy).visionCadence == .conservative)
        #expect(CameraePerformancePolicy(mode: .maximumQuality).photoQuality == .quality)
        #expect(CameraePerformancePolicy(mode: .maximumQuality).visionCadence == .quality)
        #expect(
            CameraePerformancePolicy(mode: .automatic)
                .resolvedPhotoQuality(isLowPowerModeEnabled: true, thermalState: .nominal) == .speed
        )
        #expect(
            CameraePerformancePolicy(mode: .automatic)
                .resolvedPhotoQuality(isLowPowerModeEnabled: false, thermalState: .nominal) == .balanced
        )
        #expect(
            CameraePerformancePolicy(mode: .maximumQuality)
                .resolvedPhotoQuality(isLowPowerModeEnabled: false, thermalState: .critical) == .speed
        )
    }

    @Test("disabling low-storage warnings never disables the safety stop")
    func storageWarningPolicy() {
        let warning = CaptureStorageGuardResult(
            decision: .warning,
            reason: .lowMargin,
            availableBytes: 100,
            stopThresholdBytes: 80
        )
        let stop = CaptureStorageGuardResult(
            decision: .stop,
            reason: .completionReserveAtRisk,
            availableBytes: 50,
            stopThresholdBytes: 80
        )

        #expect(!CameraeStorageWarningPolicy(isEnabled: false).shouldPresent(warning))
        #expect(CameraeStorageWarningPolicy(isEnabled: false).mustStop(stop))
    }

    @Test("original cleanup removes capture sources only after an output exists")
    func originalRetentionPolicy() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeRetentionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let frame = root.appendingPathComponent("frame_000001.heic")
        let metadata = root.appendingPathComponent("capture_plan.json")
        let output = root.appendingPathComponent("timelapse.mp4")
        try Data([1]).write(to: frame)
        try Data([2]).write(to: metadata)

        let policy = CameraeOriginalRetentionPolicy(preservesOriginals: false)
        #expect(throws: CameraeOriginalRetentionError.missingRenderedOutput) {
            try policy.apply(in: root, renderedOutputURL: output)
        }
        try Data([3]).write(to: output)
        try policy.apply(in: root, renderedOutputURL: output)

        #expect(!FileManager.default.fileExists(atPath: frame.path))
        #expect(FileManager.default.fileExists(atPath: metadata.path))
        #expect(FileManager.default.fileExists(atPath: output.path))
    }

    @Test("settings survive recreation and feed new project configuration")
    func persistenceAndConfiguration() {
        let defaults = isolatedDefaults()
        let settings = CameraeSettingsStore(defaults: defaults)
        settings.repeatableFormat = .jpeg
        settings.astroFormat = .heic
        settings.performanceMode = .maximumQuality

        let restored = CameraeSettingsStore(defaults: defaults)

        #expect(restored.repeatableFormat == .jpeg)
        #expect(restored.astroFormat == .heic)
        #expect(restored.performanceMode == .maximumQuality)
        #expect(restored.defaultSourceFormat(for: .repeatable) == .jpeg)
        #expect(restored.defaultSourceFormat(for: .astrophotography) == .heic)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "CameraeSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

@MainActor
private final class DiagnosticsConsentBackendSpy: CameraeDiagnosticsConsentBackend {
    private(set) var crashlyticsStates: [Bool] = []
    private(set) var analyticsStates: [Bool] = []

    func setCrashlyticsCollectionEnabled(_ enabled: Bool) {
        crashlyticsStates.append(enabled)
    }

    func setAnalyticsCollectionEnabled(_ enabled: Bool) {
        analyticsStates.append(enabled)
    }
}

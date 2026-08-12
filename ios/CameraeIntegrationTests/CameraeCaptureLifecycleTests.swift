import CoreLocation
import Testing
@testable import Camerae

struct CameraeCaptureLifecycleTests {
    @Test("Astro interval is a minimum start-to-start cadence")
    func astroIntervalCadence() {
        #expect(AstroCaptureTimingPolicy.waitDuration(interval: 8, captureDuration: 3) == 5)
        #expect(AstroCaptureTimingPolicy.waitDuration(interval: 8, captureDuration: 10) == 0)
        #expect(AstroCaptureTimingPolicy.estimatedCaptureCount(duration: 1_800, interval: 8) == 225)
        #expect(AstroCaptureTimingPolicy.normalizedInterval(1) == 2)
        #expect(AstroCaptureTimingPolicy.normalizedInterval(30) == 10)
        #expect(AstroCaptureTimingPolicy.intervalRange == 2...10)
    }
    @Test func preparingAndRunningUseDifferentPresentationStates() {
        #expect(CameraeCaptureLifecyclePresentation(state: .preparing).showsProgress)
        #expect(!CameraeCaptureLifecyclePresentation(state: .running).isVisible)
    }

    @Test func permissionAndConfigurationFailuresAreVisible() {
        let denied = CameraeCaptureLifecyclePresentation(state: .unauthorized)
        let failed = CameraeCaptureLifecyclePresentation(state: .failed("Câmera ocupada"))

        #expect(denied.title == "Acesso à câmera necessário")
        #expect(failed.title == "Não foi possível abrir a câmera")
        #expect(failed.message == "Câmera ocupada")
    }

    @Test func locationAuthorizationUsesDelegateStateWithoutGlobalServicesProbe() {
        #expect(CameraeLocationAuthorizationPolicy.action(for: .notDetermined) == .requestWhenInUse)
        #expect(CameraeLocationAuthorizationPolicy.action(for: .authorizedWhenInUse) == .startUpdates)
        #expect(CameraeLocationAuthorizationPolicy.action(for: .authorizedAlways) == .startUpdates)
        #expect(CameraeLocationAuthorizationPolicy.action(for: .denied) == .unavailable)
        #expect(CameraeLocationAuthorizationPolicy.action(for: .restricted) == .unavailable)
    }

    @Test("live view keeps lens testing reachable only while capture is idle")
    func repeatableLiveViewCapabilityContract() {
        #expect(
            RepeatableLiveViewCapabilityPolicy.actions(
                isCaptureActive: false,
                availableLensCount: 3
            ) == [.leave, .switchLens, .startCapture]
        )
        #expect(
            RepeatableLiveViewCapabilityPolicy.actions(
                isCaptureActive: true,
                availableLensCount: 3
            ) == [.stopCapture]
        )
        #expect(
            RepeatableLiveViewCapabilityPolicy.actions(
                isCaptureActive: false,
                availableLensCount: 1
            ) == [.leave, .startCapture]
        )
    }

    @Test func focusPreflightWaitsForAutofocusAndBlocksAnUnsharpSettledFrame() {
        let now = Date(timeIntervalSince1970: 100)
        let adjusting = CameraFocusMeasurement(
            sharpness: 0.01,
            isAdjustingFocus: true,
            capturedAt: now
        )
        let blurred = CameraFocusMeasurement(
            sharpness: 0.01,
            isAdjustingFocus: false,
            capturedAt: now
        )
        let sharp = CameraFocusMeasurement(
            sharpness: 0.12,
            isAdjustingFocus: false,
            capturedAt: now
        )

        #expect(CameraFocusPreflightPolicy.decision(measurement: adjusting, elapsed: 0.5, now: now) == .wait)
        #expect(CameraFocusPreflightPolicy.decision(measurement: blurred, elapsed: 3, now: now) == .needsUserFocus)
        #expect(CameraFocusPreflightPolicy.decision(measurement: sharp, elapsed: 0.5, now: now) == .ready)
    }

    @Test func focusSharpnessMetricSeparatesFlatAndDetailedLumaFrames() {
        let flat = Array(repeating: UInt8(80), count: 64 * 64)
        let detailed = (0..<(64 * 64)).map { index in
            let x = index % 64
            let y = index / 64
            return UInt8(((x / 8) + (y / 8)).isMultiple(of: 2) ? 0 : 255)
        }

        let flatScore = CameraFocusSharpnessAnalyzer.score(
            luma: flat,
            width: 64,
            height: 64,
            bytesPerRow: 64
        )
        let detailedScore = CameraFocusSharpnessAnalyzer.score(
            luma: detailed,
            width: 64,
            height: 64,
            bytesPerRow: 64
        )

        #expect(flatScore == 0)
        #expect(detailedScore > 0.1)

        let detailedBGRA = detailed.flatMap { value in [value, value, value, UInt8(255)] }
        let bgraScore = detailedBGRA.withUnsafeBufferPointer { buffer in
            CameraFocusSharpnessAnalyzer.scoreBGRA(
                pixels: buffer.baseAddress!,
                width: 64,
                height: 64,
                bytesPerRow: 64 * 4
            )
        }
        #expect(bgraScore > 0.1)
    }

    @Test func customFocusPreflightStaysDisabledWhileNativeAutofocusRemainsAvailable() {
        #expect(
            CameraFocusRecoveryCapabilityPolicy.actions(for: .needsUserFocus) ==
                [.tapToFocus, .retryAutomaticFocus, .captureAnyway]
        )
        #expect(CameraFocusRecoveryCapabilityPolicy.actions(for: .checking) == [])
        #expect(
            RepeatableCaptureKind.captureOptions.allSatisfy {
                !CameraCaptureFocusRequirementPolicy.requiresPreflight(for: $0)
            }
        )
    }

    @Test func captureCountdownUsesCenterBeforeStartAndCornerWhileInformationIsHidden() {
        let starting = CameraeCaptureCountdownPresentation(
            startSeconds: 3,
            isCaptureRunning: true,
            isInformationVisible: false,
            remainingLabel: "00:30"
        )
        let hiddenInformation = CameraeCaptureCountdownPresentation(
            startSeconds: nil,
            isCaptureRunning: true,
            isInformationVisible: false,
            remainingLabel: "00:27"
        )
        let visibleInformation = CameraeCaptureCountdownPresentation(
            startSeconds: nil,
            isCaptureRunning: true,
            isInformationVisible: true,
            remainingLabel: "00:27"
        )

        #expect(CameraeCaptureStartCountdown.seconds == [3, 2, 1])
        #expect(starting.centeredStartSeconds == 3)
        #expect(starting.cornerRemainingLabel == nil)
        #expect(hiddenInformation.cornerRemainingLabel == "00:27")
        #expect(visibleInformation.cornerRemainingLabel == nil)
    }
}

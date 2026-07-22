import CoreGraphics
import ImageIO
import Testing
@testable import Camerae

@Suite("Timelapse orientation regressions")
struct TimelapseOrientationRegressionTests {
    @Test("Session landscape orientation wins over portrait frame dimensions")
    func sessionLandscapeWins() {
        let size = TimelapseRenderGeometry.renderSize(
            pixelSize: CGSize(width: 3024, height: 4032),
            imageOrientation: .up,
            captureOrientation: .landscapeRight,
            resolution: .fourK
        )

        #expect(size == CGSize(width: 3840, height: 2160))
    }

    @Test("Session portrait orientation wins over landscape frame dimensions")
    func sessionPortraitWins() {
        let size = TimelapseRenderGeometry.renderSize(
            pixelSize: CGSize(width: 4032, height: 3024),
            imageOrientation: .up,
            captureOrientation: .portrait,
            resolution: .fourK
        )

        #expect(size == CGSize(width: 2160, height: 3840))
    }

    @Test("EXIF rotation is honored when an old session has no saved orientation")
    func exifFallback() {
        let size = TimelapseRenderGeometry.renderSize(
            pixelSize: CGSize(width: 4032, height: 3024),
            imageOrientation: .right,
            captureOrientation: nil,
            resolution: .preview
        )

        #expect(size == CGSize(width: 1080, height: 1920))
    }

    @Test("Each camera session derives orientation independently from its layout")
    func consecutiveSessionsDoNotReuseOrientation() {
        let first = CaptureDisplayOrientation(displaySize: CGSize(width: 844, height: 390))
        let second = CaptureDisplayOrientation(displaySize: CGSize(width: 390, height: 844))

        #expect(first.isLandscape)
        #expect(second == .portrait)
    }

    @Test("Landscape sides preserve their distinct camera rotation")
    func landscapeSidesRemainDistinct() {
        #expect(CaptureDisplayOrientation.landscapeLeft.videoRotationAngle == 180)
        #expect(CaptureDisplayOrientation.landscapeRight.videoRotationAngle == 0)
    }
}

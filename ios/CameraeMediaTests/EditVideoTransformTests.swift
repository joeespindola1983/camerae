import CoreGraphics
import Testing
@testable import CameraeMedia

@Suite("Edit video spatial transform")
struct EditVideoTransformTests {
    @Test("identity alignment preserves the existing aspect-fit transform")
    func identityPreservesBaseline() {
        let baseline = EditVideoTransformResolver.aspectFitTransform(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: .identity,
            renderSize: CGSize(width: 1920, height: 1080)
        )
        let aligned = EditVideoTransformResolver.layerTransform(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: .identity,
            renderSize: CGSize(width: 1920, height: 1080),
            spatialTransform: .identity,
            commonCrop: .full
        )

        #expect(aligned == baseline)
    }

    @Test("global crop maps the same normalized safe square to the full canvas")
    func commonCropFillsCanvasWithoutAxisDeformation() {
        let transform = EditVideoTransformResolver.layerTransform(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: .identity,
            renderSize: CGSize(width: 1920, height: 1080),
            spatialTransform: .identity,
            commonCrop: .init(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        )

        let minimum = CGPoint(x: 192, y: 108).applying(transform)
        let maximum = CGPoint(x: 1728, y: 972).applying(transform)
        #expect(abs(minimum.x) < 0.001)
        #expect(abs(minimum.y) < 0.001)
        #expect(abs(maximum.x - 1920) < 0.001)
        #expect(abs(maximum.y - 1080) < 0.001)
        #expect(abs(transform.a - transform.d) < 0.000_001)
    }
}

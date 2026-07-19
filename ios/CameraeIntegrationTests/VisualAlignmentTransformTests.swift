import AVFoundation
import CoreGraphics
import ImageIO
import simd
import Testing
@testable import Camerae

@Suite("Visual alignment transform mapping")
struct VisualAlignmentTransformTests {
    @Test("Identity keeps scale, rotation, offsets, and five guides")
    func identityTransform() throws {
        let estimate = VisualAlignmentTransformMapper.estimate(
            transform: matrix_identity_float3x3,
            confidence: 0.9,
            referenceSize: CGSize(width: 120, height: 200),
            targetSize: CGSize(width: 120, height: 200)
        )

        #expect(abs(estimate.scale - 1) < 0.000_001)
        #expect(abs(estimate.horizontalOffset) < 0.000_001)
        #expect(abs(estimate.verticalOffset) < 0.000_001)
        #expect(abs(try #require(estimate.visualRotationDegrees)) < 0.000_001)
        #expect(estimate.matchGuides.count == 5)
        #expect(estimate.distanceHint == .matched)
    }

    @Test("Low confidence preserves geometry but suppresses visual guidance")
    func lowConfidenceSuppressesGuidance() {
        var transform = matrix_identity_float3x3
        transform.columns.2.x = 12
        transform.columns.2.y = -8

        let estimate = VisualAlignmentTransformMapper.estimate(
            transform: transform,
            confidence: 0.01,
            referenceSize: CGSize(width: 120, height: 200),
            targetSize: CGSize(width: 120, height: 200)
        )

        #expect(estimate.horizontalOffset == 12)
        #expect(estimate.verticalOffset == -8)
        #expect(estimate.matchGuides.isEmpty)
        #expect(estimate.visualRotationDegrees == nil)
        #expect(estimate.distanceHint == .searching)
    }

    @Test("Uniform scale maps to the existing distance hints")
    func scaleDistanceHints() {
        let smaller = VisualAlignmentTransformMapper.estimate(
            transform: simd_float3x3(
                SIMD3<Float>(0.9, 0, 0),
                SIMD3<Float>(0, 0.9, 0),
                SIMD3<Float>(0, 0, 1)
            ),
            confidence: 0.9,
            referenceSize: CGSize(width: 100, height: 100),
            targetSize: CGSize(width: 100, height: 100)
        )
        let larger = VisualAlignmentTransformMapper.estimate(
            transform: simd_float3x3(
                SIMD3<Float>(1.1, 0, 0),
                SIMD3<Float>(0, 1.1, 0),
                SIMD3<Float>(0, 0, 1)
            ),
            confidence: 0.9,
            referenceSize: CGSize(width: 100, height: 100),
            targetSize: CGSize(width: 100, height: 100)
        )

        #expect(abs(smaller.scale - 0.9) < 0.000_001)
        #expect(smaller.distanceHint == .moveBack)
        #expect(abs(larger.scale - 1.1) < 0.000_001)
        #expect(larger.distanceHint == .moveForward)
    }

    @Test("Invalid dimensions never create guides")
    func invalidDimensions() {
        let estimate = VisualAlignmentTransformMapper.estimate(
            transform: matrix_identity_float3x3,
            confidence: 0.9,
            referenceSize: .zero,
            targetSize: CGSize(width: 100, height: 100)
        )

        #expect(estimate.matchGuides.isEmpty)
        #expect(estimate.visualRotationDegrees == nil)
    }
}

private final class VisualAlignmentEvaluatorContractStub: VisualAlignmentEvaluating {
    func evaluate(
        sampleBuffer: CMSampleBuffer,
        referenceImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) throws -> VisualAlignmentEstimate? {
        nil
    }
}

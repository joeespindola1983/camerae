import AVFoundation
import CoreGraphics
import ImageIO
import simd
import Vision

protocol VisualAlignmentEvaluating: AnyObject {
    func evaluate(
        sampleBuffer: CMSampleBuffer,
        referenceImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) throws -> VisualAlignmentEstimate?
}

final class AppleVisionAlignmentEvaluator: VisualAlignmentEvaluating {
    func evaluate(
        sampleBuffer: CMSampleBuffer,
        referenceImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) throws -> VisualAlignmentEstimate? {
        let request = VNHomographicImageRegistrationRequest(
            targetedCMSampleBuffer: sampleBuffer,
            orientation: orientation,
            options: [:]
        )
        let handler = VNImageRequestHandler(cgImage: referenceImage, orientation: .up, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first else { return nil }
        return VisualAlignmentTransformMapper.estimate(
            transform: observation.warpTransform,
            confidence: Double(observation.confidence),
            referenceSize: CGSize(width: referenceImage.width, height: referenceImage.height),
            targetSize: Self.orientedTargetImageSize(from: sampleBuffer, orientation: orientation)
        )
    }

    private static func orientedTargetImageSize(
        from sampleBuffer: CMSampleBuffer,
        orientation: CGImagePropertyOrientation
    ) -> CGSize {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return CGSize(width: 1, height: 1)
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: height, height: width)
        default:
            return CGSize(width: width, height: height)
        }
    }
}

enum VisualAlignmentTransformMapper {
    static func estimate(
        transform: simd_float3x3,
        confidence: Double,
        referenceSize: CGSize,
        targetSize: CGSize
    ) -> VisualAlignmentEstimate {
        let a = Double(transform.columns.0.x)
        let b = Double(transform.columns.0.y)
        let c = Double(transform.columns.1.x)
        let d = Double(transform.columns.1.y)
        let determinant = a * d - b * c
        let scale = sqrt(abs(determinant))

        let matchAnalysis = visualMatchAnalysis(
            from: transform,
            confidence: confidence,
            referenceSize: referenceSize,
            targetSize: targetSize
        )

        return VisualAlignmentEstimate(
            scale: scale.isFinite ? scale : 1,
            confidence: confidence,
            horizontalOffset: Double(transform.columns.2.x),
            verticalOffset: Double(transform.columns.2.y),
            matchGuides: matchAnalysis.guides,
            visualRotationDegrees: matchAnalysis.rotationDegrees
        )
    }

    private static func visualMatchAnalysis(
        from transform: simd_float3x3,
        confidence: Double,
        referenceSize: CGSize,
        targetSize: CGSize
    ) -> (guides: [VisualMatchGuide], rotationDegrees: Double?) {
        guard confidence > 0.02,
              referenceSize.width > 0,
              referenceSize.height > 0,
              targetSize.width > 0,
              targetSize.height > 0 else {
            return ([], nil)
        }

        let anchors = [
            CGPoint(x: 1.0 / 3.0, y: 1.0 / 3.0),
            CGPoint(x: 2.0 / 3.0, y: 1.0 / 3.0),
            CGPoint(x: 0.5, y: 0.5),
            CGPoint(x: 1.0 / 3.0, y: 2.0 / 3.0),
            CGPoint(x: 2.0 / 3.0, y: 2.0 / 3.0)
        ]

        var candidates = [
            (
                transform: transform,
                guides: guides(
                    from: transform,
                    anchors: anchors,
                    referenceSize: referenceSize,
                    targetSize: targetSize
                )
            )
        ]

        if let invertedTransform = inverted(transform) {
            candidates.append((
                transform: invertedTransform,
                guides: guides(
                    from: invertedTransform,
                    anchors: anchors,
                    referenceSize: referenceSize,
                    targetSize: targetSize
                )
            ))
        }

        guard let selected = candidates.filter({ $0.guides.count >= 3 }).max(by: { first, second in
            if first.guides.count == second.guides.count {
                return averageGuideLength(first.guides) > averageGuideLength(second.guides)
            }
            return first.guides.count < second.guides.count
        }) else {
            return ([], nil)
        }

        guard averageGuideLength(selected.guides) <= 0.62 else {
            return ([], nil)
        }

        return (selected.guides, visualRotationDegrees(from: selected.transform))
    }

    private static func guides(
        from transform: simd_float3x3,
        anchors: [CGPoint],
        referenceSize: CGSize,
        targetSize: CGSize
    ) -> [VisualMatchGuide] {
        anchors.enumerated().compactMap { index, point in
            let referencePixelPoint = CGPoint(
                x: point.x * referenceSize.width,
                y: point.y * referenceSize.height
            )

            guard let projected = projectedPoint(referencePixelPoint, using: transform) else {
                return nil
            }

            let normalizedProjected = CGPoint(
                x: projected.x / targetSize.width,
                y: projected.y / targetSize.height
            )
            let lenientBounds = -0.35...1.35
            guard lenientBounds.contains(normalizedProjected.x),
                  lenientBounds.contains(normalizedProjected.y) else {
                return nil
            }

            return VisualMatchGuide(
                id: index,
                reference: point,
                current: CGPoint(
                    x: min(max(normalizedProjected.x, 0), 1),
                    y: min(max(normalizedProjected.y, 0), 1)
                )
            )
        }
    }

    private static func averageGuideLength(_ guides: [VisualMatchGuide]) -> CGFloat {
        guard !guides.isEmpty else { return .greatestFiniteMagnitude }

        let total = guides.reduce(CGFloat(0)) { result, guide in
            let dx = guide.current.x - guide.reference.x
            let dy = guide.current.y - guide.reference.y
            return result + sqrt(dx * dx + dy * dy)
        }
        return total / CGFloat(guides.count)
    }

    private static func visualRotationDegrees(from transform: simd_float3x3) -> Double? {
        let radians = atan2(Double(transform.columns.0.y), Double(transform.columns.0.x))
        guard radians.isFinite else { return nil }

        var degrees = radians * 180 / .pi
        while degrees > 180 { degrees -= 360 }
        while degrees < -180 { degrees += 360 }
        return degrees
    }

    private static func inverted(_ transform: simd_float3x3) -> simd_float3x3? {
        let determinant = simd_determinant(transform)
        guard determinant.isFinite, abs(determinant) > 0.0001 else { return nil }

        let invertedTransform = simd_inverse(transform)
        guard invertedTransform.columns.0.x.isFinite,
              invertedTransform.columns.1.y.isFinite,
              invertedTransform.columns.2.z.isFinite else {
            return nil
        }
        return invertedTransform
    }

    private static func projectedPoint(
        _ point: CGPoint,
        using transform: simd_float3x3
    ) -> CGPoint? {
        let x = Float(point.x)
        let y = Float(point.y)
        let denominator = transform.columns.0.z * x + transform.columns.1.z * y + transform.columns.2.z
        guard denominator.isFinite, abs(denominator) > 0.0001 else { return nil }

        let projectedX = (transform.columns.0.x * x + transform.columns.1.x * y + transform.columns.2.x) / denominator
        let projectedY = (transform.columns.0.y * x + transform.columns.1.y * y + transform.columns.2.y) / denominator
        guard projectedX.isFinite, projectedY.isFinite else { return nil }

        return CGPoint(x: CGFloat(projectedX), y: CGFloat(projectedY))
    }
}

struct VisualAlignmentEstimate: Equatable {
    let scale: Double
    let confidence: Double
    let horizontalOffset: Double
    let verticalOffset: Double
    let matchGuides: [VisualMatchGuide]
    let visualRotationDegrees: Double?

    init(
        scale: Double,
        confidence: Double,
        horizontalOffset: Double,
        verticalOffset: Double,
        matchGuides: [VisualMatchGuide] = [],
        visualRotationDegrees: Double? = nil
    ) {
        self.scale = scale
        self.confidence = confidence
        self.horizontalOffset = horizontalOffset
        self.verticalOffset = verticalOffset
        self.matchGuides = matchGuides
        self.visualRotationDegrees = visualRotationDegrees
    }

    var isFineAdjustment: Bool {
        confidence > 0.05 && abs(scale - 1) <= 0.06
    }

    var distanceHint: VisualDistanceHint {
        guard confidence > 0.05 else { return .searching }
        if scale < 0.96 { return .moveBack }
        if scale > 1.04 { return .moveForward }
        return .matched
    }
}

struct VisualMatchGuide: Equatable, Identifiable {
    let id: Int
    let reference: CGPoint
    let current: CGPoint
}

enum VisualDistanceHint: Equatable {
    case searching
    case moveForward
    case moveBack
    case matched
}

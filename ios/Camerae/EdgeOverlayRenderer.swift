import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum AlignmentOverlayStyle {
    case normal
    case referenceEdges

    var isEdgeEnabled: Bool {
        self == .referenceEdges
    }
}

enum EdgeOverlayTint: CaseIterable {
    case red
    case green
    case blue

    var ciColor: CIColor {
        switch self {
        case .red:
            return CIColor(red: 1.0, green: 0.12, blue: 0.08, alpha: 1.0)
        case .green:
            return CIColor(red: 0.12, green: 1.0, blue: 0.22, alpha: 1.0)
        case .blue:
            return CIColor(red: 0.05, green: 0.5, blue: 1.0, alpha: 1.0)
        }
    }

    var next: EdgeOverlayTint {
        switch self {
        case .red:
            return .green
        case .green:
            return .blue
        case .blue:
            return .red
        }
    }
}

struct EdgeOverlayStroke: Equatable {
    var detail: Double = 0.12

    var edgeIntensity: Float {
        Float(1.45 + clampedDetail * 1.8)
    }

    var threshold: Float {
        Float(0.36 - clampedDetail * 0.18)
    }

    var dilationRadius: Float {
        Float(max(0, (clampedDetail - 0.62) * 2.2))
    }

    var displayValue: Int {
        Int((clampedDetail * 100).rounded())
    }

    private var clampedDetail: Double {
        min(max(detail, 0), 1)
    }
}

struct EdgeOverlayOptions {
    var tint: EdgeOverlayTint = .green
    var stroke: EdgeOverlayStroke = EdgeOverlayStroke()
    var inverted: Bool = false
    var maxPixelDimension: CGFloat = 1800
    var backgroundOpacity: CGFloat = 0.1
}

enum EdgeOverlayRenderer {
    private static let context = CIContext(options: [
        .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
        .outputColorSpace: CGColorSpaceCreateDeviceRGB()
    ])

    static func render(image: UIImage, options: EdgeOverlayOptions = EdgeOverlayOptions()) -> UIImage? {
        guard var input = CIImage(image: image) else { return nil }

        let originalExtent = input.extent
        guard originalExtent.width > 0, originalExtent.height > 0 else { return nil }

        let longestSide = max(originalExtent.width, originalExtent.height)
        let scale = min(1, options.maxPixelDimension / longestSide)
        if scale < 1 {
            input = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        let extent = input.extent
        let lineArt = input.applyingFilter("CILineOverlay", parameters: [
            "inputNRNoiseLevel": 0.09,
            "inputNRSharpness": 0.46,
            "inputEdgeIntensity": options.stroke.edgeIntensity,
            "inputThreshold": options.stroke.threshold,
            "inputContrast": 38.0
        ])

        var visibleLines = (options.inverted ? lineArt : lineArt.applyingFilter("CIColorInvert"))
            .applyingFilter("CIFalseColor", parameters: [
                "inputColor0": CIColor.clear,
                "inputColor1": options.tint.ciColor
            ])
        if options.stroke.dilationRadius > 0 {
            visibleLines = visibleLines.applyingFilter("CIMorphologyMaximum", parameters: [
                kCIInputRadiusKey: options.stroke.dilationRadius
            ])
        }

        let background = CIImage(
            color: CIColor(red: 0, green: 0, blue: 0, alpha: options.backgroundOpacity)
        )
        .cropped(to: extent)

        let output = visibleLines.applyingFilter("CISourceOverCompositing", parameters: [
            kCIInputBackgroundImageKey: background
        ])

        guard let cgImage = context.createCGImage(output, from: extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }
}

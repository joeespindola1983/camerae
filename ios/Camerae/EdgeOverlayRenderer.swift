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

enum EdgeOverlayStroke: CaseIterable {
    case fine
    case medium
    case thick

    var edgeIntensity: Float {
        switch self {
        case .fine:
            return 2.3
        case .medium:
            return 3.0
        case .thick:
            return 3.8
        }
    }

    var threshold: Float {
        switch self {
        case .fine:
            return 0.24
        case .medium:
            return 0.2
        case .thick:
            return 0.16
        }
    }

    var dilationRadius: Float {
        switch self {
        case .fine:
            return 0
        case .medium:
            return 0.7
        case .thick:
            return 1.4
        }
    }
}

struct EdgeOverlayOptions {
    var tint: EdgeOverlayTint = .green
    var stroke: EdgeOverlayStroke = .fine
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

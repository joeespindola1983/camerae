import CoreImage
import Foundation
import ImageIO
import UIKit

final class ExposureStacker {
    private let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
        .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
    ])

    func averageJPEGs(_ frames: [Data]) throws -> Data {
        guard let firstData = frames.first,
              var accumulator = CIImage(data: firstData)?.normalizedForStacking() else {
            throw CameraError.photoEncodingFailed
        }

        let extent = accumulator.extent
        for index in frames.dropFirst().indices {
            guard let frame = CIImage(data: frames[index])?.normalizedForStacking().cropped(to: extent) else {
                continue
            }

            let total = CGFloat(index + 1)
            let previousWeight = CGFloat(index) / total
            let nextWeight = CGFloat(1) / total
            accumulator = Self.add(
                Self.scale(accumulator, by: previousWeight),
                Self.scale(frame, by: nextWeight)
            ).cropped(to: extent)
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let data = context.jpegRepresentation(
            of: accumulator,
            colorSpace: colorSpace,
            options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.95]
        ) else {
            throw CameraError.photoEncodingFailed
        }

        return data
    }

    private static func add(_ foreground: CIImage, _ background: CIImage) -> CIImage {
        foreground.applyingFilter("CIAdditionCompositing", parameters: [
            kCIInputBackgroundImageKey: background
        ])
    }

    private static func scale(_ image: CIImage, by factor: CGFloat) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: factor, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: factor, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: factor, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])
    }
}

private extension CIImage {
    func normalizedForStacking() -> CIImage {
        let orientation = properties[kCGImagePropertyOrientation as String] as? UInt32
        guard let orientation else { return self }
        return oriented(CGImagePropertyOrientation(rawValue: orientation) ?? .up)
    }
}

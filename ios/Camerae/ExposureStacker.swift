import CoreImage
import Foundation
import ImageIO
import UIKit

enum AstroProcessingProfile: String, CaseIterable, Identifiable {
    case natural
    case milkyWay
    case strong

    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural:
            return "Natural"
        case .milkyWay:
            return "Via Lactea"
        case .strong:
            return "Forte"
        }
    }

    var frameRetention: Double {
        switch self {
        case .natural:
            return 1.0
        case .milkyWay:
            return 0.85
        case .strong:
            return 0.75
        }
    }

    var alignsStars: Bool {
        self != .natural
    }

    var noiseLevel: Float {
        switch self {
        case .natural:
            return 0.015
        case .milkyWay:
            return 0.025
        case .strong:
            return 0.04
        }
    }

    var sharpness: Float {
        switch self {
        case .natural:
            return 0.55
        case .milkyWay:
            return 0.65
        case .strong:
            return 0.75
        }
    }
}

struct AstroImageProcessingSettings: Equatable, Hashable {
    var profile: AstroProcessingProfile
    var appliesDenoise: Bool
    var noiseLevel: Float
    var sharpness: Float

    static func defaults(for profile: AstroProcessingProfile) -> AstroImageProcessingSettings {
        AstroImageProcessingSettings(
            profile: profile,
            appliesDenoise: profile != .natural,
            noiseLevel: profile.noiseLevel,
            sharpness: profile.sharpness
        )
    }

    var alignsStars: Bool {
        profile.alignsStars
    }
}

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

    func preferredFrames(_ frameURLs: [URL], maxDimension: CGFloat?, profile: AstroProcessingProfile) -> [URL] {
        guard profile.frameRetention < 1, frameURLs.count > 5 else {
            return frameURLs
        }

        let targetCount = max(5, Int(ceil(Double(frameURLs.count) * profile.frameRetention)))
        return frameURLs
            .map { url in
                (url: url, score: sharpnessScore(for: url, maxDimension: min(maxDimension ?? 1920, 320)))
            }
            .sorted { left, right in
                left.score > right.score
            }
            .prefix(targetCount)
            .map(\.url)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func averageJPEGFiles(
        _ frameURLs: [URL],
        maxDimension: CGFloat? = nil,
        profile: AstroProcessingProfile = .natural
    ) throws -> Data {
        try averageJPEGFiles(
            frameURLs,
            maxDimension: maxDimension,
            settings: .defaults(for: profile)
        )
    }

    func averageJPEGFiles(
        _ frameURLs: [URL],
        maxDimension: CGFloat? = nil,
        settings: AstroImageProcessingSettings
    ) throws -> Data {
        guard let firstURL = frameURLs.first,
              var accumulator = processedFrame(firstURL, maxDimension: maxDimension, settings: settings) else {
            throw CameraError.photoEncodingFailed
        }

        let extent = accumulator.extent
        let referenceAnchor = settings.alignsStars ? starAnchor(in: accumulator) : nil
        accumulator = try materialized(accumulator, extent: extent)

        for index in frameURLs.dropFirst().indices {
            try autoreleasepool {
                guard var frame = processedFrame(frameURLs[index], maxDimension: maxDimension, settings: settings) else {
                    return
                }

                if let referenceAnchor, let frameAnchor = starAnchor(in: frame) {
                    let dx = referenceAnchor.x - frameAnchor.x
                    let dy = referenceAnchor.y - frameAnchor.y
                    frame = frame.transformed(by: CGAffineTransform(translationX: dx, y: dy))
                }
                frame = frame.cropped(to: extent)

                let total = CGFloat(index + 1)
                let previousWeight = CGFloat(index) / total
                let nextWeight = CGFloat(1) / total
                let averaged = Self.add(
                    Self.scale(accumulator, by: previousWeight),
                    Self.scale(frame, by: nextWeight)
                ).cropped(to: extent)

                accumulator = try materialized(averaged, extent: extent)
            }
        }

        accumulator = postProcessedStack(accumulator, profile: settings.profile).cropped(to: extent)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let data = context.jpegRepresentation(
            of: accumulator,
            colorSpace: colorSpace,
            options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.95]
        ) else {
            throw CameraError.photoEncodingFailed
        }

        context.clearCaches()
        return data
    }

    private func processedFrame(
        _ frameURL: URL,
        maxDimension: CGFloat?,
        profile: AstroProcessingProfile
    ) -> CIImage? {
        processedFrame(
            frameURL,
            maxDimension: maxDimension,
            settings: .defaults(for: profile)
        )
    }

    private func processedFrame(
        _ frameURL: URL,
        maxDimension: CGFloat?,
        settings: AstroImageProcessingSettings
    ) -> CIImage? {
        guard var image = CIImage(contentsOf: frameURL)?.normalizedForStacking() else {
            return nil
        }

        if let maxDimension {
            image = image.downscaled(maxDimension: maxDimension)
        }

        if settings.profile != .natural {
            image = normalizedExposureAndWhiteBalance(image)
        }

        if settings.appliesDenoise {
            image = image.applyingFilter("CINoiseReduction", parameters: [
                "inputNoiseLevel": settings.noiseLevel,
                "inputSharpness": settings.sharpness
            ])
        }

        return image
    }

    private func postProcessedStack(_ image: CIImage, profile: AstroProcessingProfile) -> CIImage {
        switch profile {
        case .natural:
            return image
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1.04,
                    kCIInputContrastKey: 1.06,
                    kCIInputBrightnessKey: -0.01
                ])
                .applyingFilter("CISharpenLuminance", parameters: [
                    kCIInputSharpnessKey: 0.25
                ])
        case .milkyWay:
            return image
                .applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputShadowAmount": 0.25,
                    "inputHighlightAmount": 0.95
                ])
                .applyingFilter("CIGammaAdjust", parameters: [
                    "inputPower": 0.88
                ])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1.10,
                    kCIInputContrastKey: 1.12,
                    kCIInputBrightnessKey: 0.015
                ])
                .applyingFilter("CIVibrance", parameters: [
                    "inputAmount": 0.16
                ])
                .applyingFilter("CISharpenLuminance", parameters: [
                    kCIInputSharpnessKey: 0.28
                ])
        case .strong:
            return image
                .applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputShadowAmount": 0.38,
                    "inputHighlightAmount": 0.90
                ])
                .applyingFilter("CIGammaAdjust", parameters: [
                    "inputPower": 0.82
                ])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1.18,
                    kCIInputContrastKey: 1.20,
                    kCIInputBrightnessKey: 0.02
                ])
                .applyingFilter("CIVibrance", parameters: [
                    "inputAmount": 0.24
                ])
                .applyingFilter("CISharpenLuminance", parameters: [
                    kCIInputSharpnessKey: 0.36
                ])
        }
    }

    private func normalizedExposureAndWhiteBalance(_ image: CIImage) -> CIImage {
        guard let stats = colorStats(for: image.downscaled(maxDimension: 96)) else {
            return image
        }

        let targetLuminance = 0.30
        let exposureRatio = max(0.5, min(2.5, targetLuminance / max(stats.luminance, 0.01)))
        let exposureEV = max(-0.25, min(0.65, log2(exposureRatio)))
        let gray = max((stats.red + stats.green + stats.blue) / 3, 0.01)
        let redGain = max(0.90, min(1.10, gray / max(stats.red, 0.01)))
        let greenGain = max(0.92, min(1.08, gray / max(stats.green, 0.01)))
        let blueGain = max(0.90, min(1.12, gray / max(stats.blue, 0.01)))

        return image
            .applyingFilter("CIExposureAdjust", parameters: [
                kCIInputEVKey: exposureEV
            ])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: redGain, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: greenGain, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: blueGain, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
    }

    private func sharpnessScore(for frameURL: URL, maxDimension: CGFloat) -> Double {
        guard let image = CIImage(contentsOf: frameURL)?.normalizedForStacking().downscaled(maxDimension: maxDimension),
              let sample = luminanceSample(for: image) else {
            return 0
        }

        guard sample.width > 2, sample.height > 2 else { return 0 }

        var total = 0.0
        var count = 0

        for y in 1..<(sample.height - 1) {
            for x in 1..<(sample.width - 1) {
                let center = sample.luma[y * sample.width + x]
                let laplacian =
                    sample.luma[y * sample.width + x - 1] +
                    sample.luma[y * sample.width + x + 1] +
                    sample.luma[(y - 1) * sample.width + x] +
                    sample.luma[(y + 1) * sample.width + x] -
                    (4 * center)

                total += abs(laplacian)
                count += 1
            }
        }

        return count > 0 ? total / Double(count) : 0
    }

    private func starAnchor(in image: CIImage) -> CGPoint? {
        guard let sample = luminanceSample(for: image.downscaled(maxDimension: 160)) else {
            return nil
        }

        let ranked = sample.luma.enumerated()
            .filter { $0.element > 0.42 }
            .sorted { $0.element > $1.element }
            .prefix(80)

        guard !ranked.isEmpty else {
            return nil
        }

        var weightedX = 0.0
        var weightedY = 0.0
        var totalWeight = 0.0

        for item in ranked {
            let x = item.offset % sample.width
            let y = item.offset / sample.width
            let weight = pow(item.element, 2)
            weightedX += Double(x) * weight
            weightedY += Double(y) * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else {
            return nil
        }

        let scaleX = image.extent.width / CGFloat(sample.width)
        let scaleY = image.extent.height / CGFloat(sample.height)
        return CGPoint(
            x: image.extent.minX + CGFloat(weightedX / totalWeight) * scaleX,
            y: image.extent.minY + CGFloat(weightedY / totalWeight) * scaleY
        )
    }

    private func luminanceSample(for image: CIImage) -> LuminanceSample? {
        let normalized = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let extent = normalized.extent.integral
        let width = max(1, Int(extent.width))
        let height = max(1, Int(extent.height))
        let rowBytes = width * 4
        var pixels = [UInt8](repeating: 0, count: rowBytes * height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        context.render(
            normalized,
            toBitmap: &pixels,
            rowBytes: rowBytes,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8,
            colorSpace: colorSpace
        )

        var luma = [Double]()
        luma.reserveCapacity(width * height)

        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let red = Double(pixels[offset]) / 255.0
            let green = Double(pixels[offset + 1]) / 255.0
            let blue = Double(pixels[offset + 2]) / 255.0
            luma.append((0.2126 * red) + (0.7152 * green) + (0.0722 * blue))
        }

        return LuminanceSample(width: width, height: height, luma: luma)
    }

    private func colorStats(for image: CIImage) -> ColorStats? {
        let normalized = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let extent = normalized.extent.integral
        let width = max(1, Int(extent.width))
        let height = max(1, Int(extent.height))
        let rowBytes = width * 4
        var pixels = [UInt8](repeating: 0, count: rowBytes * height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        context.render(
            normalized,
            toBitmap: &pixels,
            rowBytes: rowBytes,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8,
            colorSpace: colorSpace
        )

        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var luminance = 0.0
        var count = 0.0

        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[offset]) / 255.0
            let g = Double(pixels[offset + 1]) / 255.0
            let b = Double(pixels[offset + 2]) / 255.0
            let l = (0.2126 * r) + (0.7152 * g) + (0.0722 * b)

            guard l > 0.02, l < 0.85 else {
                continue
            }

            red += r
            green += g
            blue += b
            luminance += l
            count += 1
        }

        guard count > 0 else {
            return nil
        }

        return ColorStats(
            red: red / count,
            green: green / count,
            blue: blue / count,
            luminance: luminance / count
        )
    }

    private func materialized(_ image: CIImage, extent: CGRect) throws -> CIImage {
        guard let cgImage = context.createCGImage(image, from: extent) else {
            throw CameraError.photoEncodingFailed
        }

        context.clearCaches()
        return CIImage(cgImage: cgImage)
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

private struct LuminanceSample {
    let width: Int
    let height: Int
    let luma: [Double]
}

private struct ColorStats {
    let red: Double
    let green: Double
    let blue: Double
    let luminance: Double
}

private extension CIImage {
    func normalizedForStacking() -> CIImage {
        let orientation = properties[kCGImagePropertyOrientation as String] as? UInt32
        guard let orientation else { return self }
        return oriented(CGImagePropertyOrientation(rawValue: orientation) ?? .up)
    }

    func downscaled(maxDimension: CGFloat) -> CIImage {
        guard maxDimension > 0 else { return self }

        let longestSide = max(extent.width, extent.height)
        guard longestSide > maxDimension else { return self }

        let scale = maxDimension / longestSide
        return transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
}

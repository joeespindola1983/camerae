import CoreGraphics
import CoreVideo
import Foundation

enum CameraeVisionFeatureConfiguration {
    static let shadowEnabledKey = "CameraeVisionOpenCVShadowEnabled"
    static let releaseDefault = CameraeVisionSchedulerConfiguration.disabled

    static func current(
        userDefaults: UserDefaults = .standard,
        processInfo: ProcessInfo = .processInfo
    ) -> CameraeVisionSchedulerConfiguration {
        guard userDefaults.bool(forKey: shadowEnabledKey) else { return releaseDefault }
        let cadence: CameraeVisionCadence = processInfo.isLowPowerModeEnabled
            ? .conservative
            : .balanced
        return .init(enabled: true, cadence: cadence)
    }
}

enum CameraeVisionPixelBufferFactory {
    enum ConversionError: Error {
        case allocationFailed(CVReturn)
        case lockFailed(CVReturn)
        case contextCreationFailed
    }

    static func makeBGRA(from image: CGImage) throws -> CVPixelBuffer {
        var optionalBuffer: CVPixelBuffer?
        let attributes: CFDictionary = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ] as CFDictionary
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            image.width,
            image.height,
            kCVPixelFormatType_32BGRA,
            attributes,
            &optionalBuffer
        )
        guard status == kCVReturnSuccess, let buffer = optionalBuffer else {
            throw ConversionError.allocationFailed(status)
        }

        let lockStatus = CVPixelBufferLockBaseAddress(buffer, [])
        guard lockStatus == kCVReturnSuccess else {
            throw ConversionError.lockFailed(lockStatus)
        }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue |
                CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            throw ConversionError.contextCreationFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }
}

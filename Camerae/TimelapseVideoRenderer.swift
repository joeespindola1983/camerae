import AVFoundation
import CoreGraphics
import Foundation
import UIKit

struct TimelapseVideoRenderer {
    func render(frames: [URL], outputURL: URL, fps: Int) async throws {
        try await Task.detached(priority: .userInitiated) {
            try renderVideo(frames: frames, outputURL: outputURL, fps: fps)
        }.value
    }
}

private func renderVideo(frames: [URL], outputURL: URL, fps: Int) throws {
    guard let firstFrame = frames.first,
          let firstImage = UIImage(contentsOfFile: firstFrame.path),
          let firstCGImage = firstImage.normalizedCGImage() else {
        throw VideoRenderError.noFrames
    }

    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: outputURL.path) {
        try fileManager.removeItem(at: outputURL)
    }

    let renderSize = evenRenderSize(for: firstCGImage)
    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: renderSize.width,
        AVVideoHeightKey: renderSize.height
    ])
    input.expectsMediaDataInRealTime = false

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: renderSize.width,
            kCVPixelBufferHeightKey as String: renderSize.height
        ]
    )

    guard writer.canAdd(input) else {
        throw VideoRenderError.writerConfigurationFailed
    }

    writer.add(input)

    guard writer.startWriting() else {
        throw writer.error ?? VideoRenderError.writerConfigurationFailed
    }

    writer.startSession(atSourceTime: .zero)

    let frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(fps, 1)))
    var frameIndex: Int64 = 0

    for frameURL in frames {
        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.002)
        }

        guard let image = UIImage(contentsOfFile: frameURL.path),
              let cgImage = image.normalizedCGImage(),
              let pixelBuffer = makePixelBuffer(from: cgImage, size: renderSize) else {
            continue
        }

        let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
        if !adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            throw writer.error ?? VideoRenderError.frameAppendFailed
        }

        frameIndex += 1
    }

    guard frameIndex > 0 else {
        input.markAsFinished()
        writer.cancelWriting()
        throw VideoRenderError.noFrames
    }

    input.markAsFinished()

    let semaphore = DispatchSemaphore(value: 0)
    writer.finishWriting {
        semaphore.signal()
    }
    semaphore.wait()

    switch writer.status {
    case .completed:
        break
    case .failed:
        throw writer.error ?? VideoRenderError.writerConfigurationFailed
    case .cancelled:
        throw VideoRenderError.renderCancelled
    default:
        throw VideoRenderError.writerConfigurationFailed
    }

    let outputValues = try outputURL.resourceValues(forKeys: [.fileSizeKey])
    guard (outputValues.fileSize ?? 0) > 0 else {
        throw VideoRenderError.emptyOutput
    }
}

private func evenRenderSize(for image: CGImage) -> CGSize {
    let maxDimension: CGFloat = 1920
    let width = CGFloat(image.width)
    let height = CGFloat(image.height)
    let scale = min(1, maxDimension / max(width, height))
    let scaledWidth = Int(width * scale)
    let scaledHeight = Int(height * scale)

    return CGSize(
        width: max(2, scaledWidth - (scaledWidth % 2)),
        height: max(2, scaledHeight - (scaledHeight % 2))
    )
}

private func makePixelBuffer(from image: CGImage, size: CGSize) -> CVPixelBuffer? {
    var pixelBuffer: CVPixelBuffer?
    let options: [CFString: Any] = [
        kCVPixelBufferCGImageCompatibilityKey: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey: true
    ]

    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        Int(size.width),
        Int(size.height),
        kCVPixelFormatType_32ARGB,
        options as CFDictionary,
        &pixelBuffer
    )

    guard status == kCVReturnSuccess, let pixelBuffer else {
        return nil
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

    guard let context = CGContext(
        data: CVPixelBufferGetBaseAddress(pixelBuffer),
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
    ) else {
        return nil
    }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(origin: .zero, size: size))
    return pixelBuffer
}

private extension UIImage {
    func normalizedCGImage() -> CGImage? {
        if imageOrientation == .up {
            return cgImage
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}

enum VideoRenderError: LocalizedError {
    case noFrames
    case writerConfigurationFailed
    case frameAppendFailed
    case renderCancelled
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .noFrames:
            return "nenhum frame encontrado para gerar o video"
        case .writerConfigurationFailed:
            return "nao foi possivel configurar o gerador de video"
        case .frameAppendFailed:
            return "nao foi possivel adicionar um frame ao video"
        case .renderCancelled:
            return "a geracao do video foi cancelada"
        case .emptyOutput:
            return "o MP4 foi gerado vazio"
        }
    }
}

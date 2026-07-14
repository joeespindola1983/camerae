import AVFoundation
import CameraeCore
import CoreGraphics
import Foundation
import ImageIO
import UIKit

struct TimelapseVideoRenderer {
    func render(
        frames: [URL],
        outputURL: URL,
        settings: WorkflowVideoSettings,
        progress: (@Sendable (Int, Int) async -> Void)? = nil
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            try await renderVideo(frames: frames, outputURL: outputURL, settings: settings, progress: progress)
        }.value
    }
}

private func renderVideo(
    frames: [URL],
    outputURL: URL,
    settings: WorkflowVideoSettings,
    progress: (@Sendable (Int, Int) async -> Void)?
) async throws {
    guard let firstFrame = frames.first else {
        throw VideoRenderError.noFrames
    }

    let fileManager = FileManager.default
    let temporaryURL = outputURL.deletingLastPathComponent()
        .appendingPathComponent(".\(UUID().uuidString).rendering.mp4")
    try? fileManager.removeItem(at: temporaryURL)
    defer { try? fileManager.removeItem(at: temporaryURL) }

    let renderSize = try renderSize(for: firstFrame, resolution: settings.resolution)
    let fps = max(settings.fps, 1)
    let writer = try AVAssetWriter(outputURL: temporaryURL, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: Int(renderSize.width),
        AVVideoHeightKey: Int(renderSize.height),
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: bitRate(for: renderSize, fps: fps, quality: settings.quality),
            AVVideoMaxKeyFrameIntervalKey: max(fps, 1)
        ]
    ])
    input.expectsMediaDataInRealTime = false

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(renderSize.width),
            kCVPixelBufferHeightKey as String: Int(renderSize.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
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
        try Task.checkCancellation()
        try waitUntilReady(input: input, writer: writer)

        try autoreleasepool {
            guard let pixelBufferPool = adaptor.pixelBufferPool else {
                throw VideoRenderError.writerConfigurationFailed
            }

            guard let pixelBuffer = makePixelBuffer(from: frameURL, size: renderSize, pool: pixelBufferPool) else {
                return
            }

            let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
            if !adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                throw writer.error ?? VideoRenderError.frameAppendFailed
            }

            frameIndex += 1
        }

        if frameIndex == 1 || frameIndex % 5 == 0 || frameIndex == Int64(frames.count) {
            await progress?(Int(frameIndex), frames.count)
        }
    }

    guard frameIndex > 0 else {
        input.markAsFinished()
        writer.cancelWriting()
        throw VideoRenderError.noFrames
    }

    input.markAsFinished()

    await withCheckedContinuation { continuation in
        writer.finishWriting {
            continuation.resume()
        }
    }

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

    let outputValues = try temporaryURL.resourceValues(forKeys: [.fileSizeKey])
    guard (outputValues.fileSize ?? 0) > 0 else {
        throw VideoRenderError.emptyOutput
    }
    let asset = AVURLAsset(url: temporaryURL)
    let duration = CMTimeGetSeconds(try await asset.load(.duration))
    let tracks = try await asset.loadTracks(withMediaType: .video)
    guard duration.isFinite, duration > 0, !tracks.isEmpty else {
        throw VideoRenderError.invalidOutput
    }
    try AtomicArtifactPublisher().publish(
        temporaryURL: temporaryURL,
        destinationURL: outputURL
    ) { candidate in
        let size = try candidate.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0 else { throw VideoRenderError.emptyOutput }
    }
}

private func renderSize(for frameURL: URL, resolution: WorkflowVideoResolution) throws -> CGSize {
    guard
        let source = CGImageSourceCreateWithURL(frameURL as CFURL, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let pixelWidth = properties[kCGImagePropertyPixelWidth] as? CGFloat,
        let pixelHeight = properties[kCGImagePropertyPixelHeight] as? CGFloat
    else {
        throw VideoRenderError.noFrames
    }

    guard let maxPixelSize = resolution.maxPixelSize else {
        return evenSize(width: pixelWidth, height: pixelHeight)
    }

    let isPortrait = pixelHeight >= pixelWidth
    let targetWidth = isPortrait ? min(maxPixelSize.width, maxPixelSize.height) : max(maxPixelSize.width, maxPixelSize.height)
    let targetHeight = isPortrait ? max(maxPixelSize.width, maxPixelSize.height) : min(maxPixelSize.width, maxPixelSize.height)
    return evenSize(width: targetWidth, height: targetHeight)
}

private func evenSize(width: CGFloat, height: CGFloat) -> CGSize {
    let evenWidth = Int(width) - (Int(width) % 2)
    let evenHeight = Int(height) - (Int(height) % 2)
    return CGSize(width: max(2, evenWidth), height: max(2, evenHeight))
}

private func bitRate(for size: CGSize, fps: Int, quality: WorkflowVideoQuality) -> Int {
    let frameRateFactor = Double(max(fps, 24)) / 30.0
    let pixelFactor = Double(size.width * size.height * 4)
    return max(Int(pixelFactor * frameRateFactor * quality.bitRateMultiplier), 2_000_000)
}

private func makePixelBuffer(from frameURL: URL, size: CGSize, pool: CVPixelBufferPool) -> CVPixelBuffer? {
    guard let image = UIImage(contentsOfFile: frameURL.path),
          let cgImage = image.normalizedCGImage() else {
        return nil
    }

    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)

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
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else {
        return nil
    }

    context.clear(CGRect(origin: .zero, size: size))
    context.interpolationQuality = .high
    context.draw(cgImage, in: CGRect(origin: .zero, size: size))
    return pixelBuffer
}

private func waitUntilReady(input: AVAssetWriterInput, writer: AVAssetWriter) throws {
    while !input.isReadyForMoreMediaData {
        if writer.status == .failed || writer.status == .cancelled {
            throw writer.error ?? VideoRenderError.frameAppendFailed
        }

        Thread.sleep(forTimeInterval: 0.01)
    }
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
    case invalidOutput

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
        case .invalidOutput:
            return "o MP4 gerado nao possui duracao ou faixa de video valida"
        }
    }
}

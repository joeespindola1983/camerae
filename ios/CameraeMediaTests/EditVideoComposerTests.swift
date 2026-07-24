import AVFoundation
import CameraeCore
import CoreVideo
import Foundation
import Testing
@testable import CameraeMedia

@Suite("Edit video composer")
struct EditVideoComposerTests {
    @Test("portrait compositions use an orientation-agnostic export preset")
    func portraitExportPresetDoesNotImposeLandscapeGeometry() {
        #expect(
            EditVideoExportPresetPolicy.presetName(renderWidth: 1080, renderHeight: 1920)
                == AVAssetExportPresetHighestQuality
        )
        #expect(
            EditVideoExportPresetPolicy.presetName(renderWidth: 1920, renderHeight: 1080)
                == AVAssetExportPreset1920x1080
        )
    }

    @Test("export diagnostics preserve AVFoundation domain, code, and underlying error")
    func exportDiagnosticsPreserveSystemErrorIdentity() {
        let underlying = NSError(
            domain: "NSOSStatusErrorDomain",
            code: -16976,
            userInfo: [NSLocalizedDescriptionKey: "encoder stopped"]
        )
        let error = NSError(
            domain: AVFoundationErrorDomain,
            code: -11800,
            userInfo: [
                NSLocalizedDescriptionKey: "The operation could not be completed",
                NSUnderlyingErrorKey: underlying
            ]
        )

        let detail = EditVideoComposerDiagnostics.describe(error)

        #expect(detail.contains("domain=AVFoundationErrorDomain"))
        #expect(detail.contains("code=-11800"))
        #expect(detail.contains("underlyingDomain=NSOSStatusErrorDomain"))
        #expect(detail.contains("underlyingCode=-16976"))
    }

    @Test("exports ordered clips to a validated 1080p MP4")
    func exportsPlayableMP4() async throws {
#if targetEnvironment(simulator)
        // The iOS 26 Simulator rejects AVAssetExportSession's 1080p hardware
        // pipeline with AVErrorOperationNotSupported. This contract runs on a
        // physical-device test destination; planner and app orchestration remain
        // covered on Simulator.
        return
#else
        let fixture = try VideoCompositionFixture()
        defer { fixture.remove() }
        let firstURL = fixture.root.appendingPathComponent("first.mp4")
        let secondURL = fixture.root.appendingPathComponent("second.mp4")
        try await TinyVideoFactory.make(url: firstURL, red: 230, green: 30, blue: 30)
        try await TinyVideoFactory.make(url: secondURL, red: 30, green: 60, blue: 230)
        let prepared = try await fixture.makeDocumentAndAssets(urls: [firstURL, secondURL])
        let outputURL = fixture.root.appendingPathComponent("Exports/final.mp4")
        let progress = ProgressRecorder()

        let exported = try await EditVideoComposer().export(
            project: prepared.document,
            assets: prepared.assets,
            outputURL: outputURL
        ) { value in
            await progress.record(value)
        }

        let values = try exported.resourceValues(forKeys: [.fileSizeKey])
        let asset = AVURLAsset(url: exported)
        let duration = CMTimeGetSeconds(try await asset.load(.duration))
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)

        #expect(exported == outputURL)
        #expect((values.fileSize ?? 0) > 0)
        #expect(abs(duration - prepared.expectedDuration) < 0.15)
        #expect(Int(abs(size.width)) == 1920)
        #expect(Int(abs(size.height)) == 1080)
        #expect(await progress.last == 1)
#endif
    }
}

private actor ProgressRecorder {
    private(set) var last: Double = 0
    func record(_ value: Double) { last = value }
}

private final class VideoCompositionFixture: @unchecked Sendable {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeEditComposerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func makeDocumentAndAssets(
        urls: [URL]
    ) async throws -> (
        document: EditProjectDocument,
        assets: [MediaAssetID: ResolvedMediaAsset],
        expectedDuration: TimeInterval
    ) {
        var items: [EditTimelineItem] = []
        var assets: [MediaAssetID: ResolvedMediaAsset] = [:]
        var duration: TimeInterval = 0
        for (index, url) in urls.enumerated() {
            let reference = MediaAssetReference(
                projectID: UUID(uuidString: String(format: "A1000000-0000-0000-0000-%012d", index + 1))!,
                sessionID: UUID(uuidString: String(format: "A2000000-0000-0000-0000-%012d", index + 1))!,
                kind: .repeatableTimelapse,
                relativePath: "clip\(index).mp4"
            )
            let metadata = try await MediaAssetProbe().probe(url: url)
            let descriptor = MediaAssetDescriptor(
                reference: reference,
                sourceModule: .repeatable,
                projectName: "Source",
                sessionName: "Session \(index)",
                sourceCreatedAt: Date(timeIntervalSince1970: 0),
                duration: metadata.duration,
                pixelWidth: metadata.pixelWidth,
                pixelHeight: metadata.pixelHeight,
                hasAudio: metadata.hasAudio,
                fileSize: metadata.fileSize,
                isAvailable: true
            )
            items.append(EditTimelineItem(id: UUID(), asset: reference, addedAt: Date(timeIntervalSince1970: 0)))
            assets[reference.id] = ResolvedMediaAsset(descriptor: descriptor, url: url)
            duration += metadata.duration
        }
        return (
            EditProjectDocument(
                projectID: UUID(uuidString: "A3000000-0000-0000-0000-000000000001")!,
                canvas: .landscape16x9,
                items: items,
                updatedAt: Date(timeIntervalSince1970: 0)
            ),
            assets,
            duration
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private enum TinyVideoFactory {
    static func make(url: URL, red: UInt8, green: UInt8, blue: UInt8) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 640,
            AVVideoHeightKey: 360
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 640,
                kCVPixelBufferHeightKey as String: 360,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        guard writer.canAdd(input) else { throw TinyVideoError.writerFailed }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? TinyVideoError.writerFailed }
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<6 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else { throw TinyVideoError.writerFailed }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                  let buffer else { throw TinyVideoError.writerFailed }
            fill(buffer, red: red, green: green, blue: blue)
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else {
                throw writer.error ?? TinyVideoError.writerFailed
            }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: 6, timescale: 30))
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else { throw writer.error ?? TinyVideoError.writerFailed }
    }

    private static func fill(_ buffer: CVPixelBuffer, red: UInt8, green: UInt8, blue: UInt8) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        for y in 0..<height {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                row[x * 4] = blue
                row[x * 4 + 1] = green
                row[x * 4 + 2] = red
                row[x * 4 + 3] = 255
            }
        }
    }
}

private enum TinyVideoError: Error {
    case writerFailed
}

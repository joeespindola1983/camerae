import Foundation
import Testing
import UIKit
@testable import CameraeMedia

@Suite("Thumbnail pipeline component")
struct ThumbnailPipelineTests {
    @Test("downsampling respects the requested maximum pixel size")
    func downsampleSize() async throws {
        let fixture = try ThumbnailFixture(width: 1_200, height: 800)
        defer { fixture.remove() }
        let pipeline = ThumbnailPipeline(cacheDirectory: fixture.cacheDirectory)

        let result = try #require(await pipeline.thumbnail(for: fixture.imageURL, maxPixelSize: 240))

        #expect(max(result.image.size.width * result.image.scale, result.image.size.height * result.image.scale) <= 240)
        #expect(result.source == .generated)
    }

    @Test("memory and disk cache avoid decoding the original again")
    func cacheLayers() async throws {
        let fixture = try ThumbnailFixture(width: 600, height: 400)
        defer { fixture.remove() }
        let decoder = CountingThumbnailDecoder()
        let firstPipeline = ThumbnailPipeline(cacheDirectory: fixture.cacheDirectory, decoder: decoder)

        let first = try #require(await firstPipeline.thumbnail(for: fixture.imageURL, maxPixelSize: 128))
        let memory = try #require(await firstPipeline.thumbnail(for: fixture.imageURL, maxPixelSize: 128))
        await firstPipeline.clearMemory()
        let disk = try #require(await firstPipeline.thumbnail(for: fixture.imageURL, maxPixelSize: 128))

        #expect(first.source == .generated)
        #expect(memory.source == .memory)
        #expect(disk.source == .disk)
        #expect(await decoder.calls == 1)
    }

    @Test("concurrent requests for one key share a single decode")
    func concurrentDeduplication() async throws {
        let fixture = try ThumbnailFixture(width: 600, height: 400)
        defer { fixture.remove() }
        let decoder = CountingThumbnailDecoder(delayNanoseconds: 80_000_000)
        let pipeline = ThumbnailPipeline(cacheDirectory: fixture.cacheDirectory, decoder: decoder)

        await withTaskGroup(of: ThumbnailResult?.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    await pipeline.thumbnail(for: fixture.imageURL, maxPixelSize: 128)
                }
            }
            for await result in group {
                #expect(result?.image != nil)
            }
        }

        #expect(await decoder.calls == 1)
    }
}

private actor CountingThumbnailDecoder: ThumbnailDecoding {
    private(set) var calls = 0
    private let delayNanoseconds: UInt64
    private let realDecoder = ImageIOThumbnailDecoder()

    init(delayNanoseconds: UInt64 = 0) {
        self.delayNanoseconds = delayNanoseconds
    }

    func decode(url: URL, maxPixelSize: Int) async -> UIImage? {
        calls += 1
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return await realDecoder.decode(url: url, maxPixelSize: maxPixelSize)
    }
}

private final class ThumbnailFixture: @unchecked Sendable {
    let root: URL
    let imageURL: URL
    let cacheDirectory: URL

    init(width: Int, height: Int) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraeThumbnailTests-\(UUID().uuidString)", isDirectory: true)
        imageURL = root.appendingPathComponent("source.jpg")
        cacheDirectory = root.appendingPathComponent("Cache", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        try #require(image.jpegData(compressionQuality: 0.9)).write(to: imageURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

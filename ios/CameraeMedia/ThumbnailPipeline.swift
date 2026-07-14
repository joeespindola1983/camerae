import Foundation
import ImageIO
import UIKit

public enum ThumbnailCacheSource: String, Equatable, Sendable {
    case memory
    case disk
    case generated
}

public struct ThumbnailResult: @unchecked Sendable {
    public let image: UIImage
    public let source: ThumbnailCacheSource

    public init(image: UIImage, source: ThumbnailCacheSource) {
        self.image = image
        self.source = source
    }
}

public protocol ThumbnailDecoding: Sendable {
    func decode(url: URL, maxPixelSize: Int) async -> UIImage?
}

public struct ImageIOThumbnailDecoder: ThumbnailDecoding {
    public init() {}

    public func decode(url: URL, maxPixelSize: Int) async -> UIImage? {
        await Task.detached(priority: .utility) {
            autoreleasepool {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, [
                    kCGImageSourceShouldCache: false
                ] as CFDictionary) else { return nil }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCache: false,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 1)
                ]
                guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                    return nil
                }
                return UIImage(cgImage: cgImage)
            }
        }.value
    }
}

public actor ThumbnailPipeline {
    public static let shared: ThumbnailPipeline = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return ThumbnailPipeline(
            cacheDirectory: caches.appendingPathComponent("Camerae/Thumbnails", isDirectory: true)
        )
    }()

    private let cacheDirectory: URL
    private let decoder: any ThumbnailDecoding
    private let fileManager: FileManager
    private let memory = NSCache<NSString, UIImage>()
    private let limiter: ThumbnailDecodeLimiter
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    public init(
        cacheDirectory: URL,
        decoder: any ThumbnailDecoding = MediaThumbnailDecoder(),
        fileManager: FileManager = .default,
        memoryCostLimit: Int = 48 * 1024 * 1024,
        maximumConcurrentDecodes: Int = 4
    ) {
        self.cacheDirectory = cacheDirectory
        self.decoder = decoder
        self.fileManager = fileManager
        limiter = ThumbnailDecodeLimiter(limit: maximumConcurrentDecodes)
        memory.totalCostLimit = memoryCostLimit
        memory.countLimit = 300
    }

    public func thumbnail(for sourceURL: URL, maxPixelSize: Int) async -> ThumbnailResult? {
        guard !Task.isCancelled, let key = cacheKey(for: sourceURL, maxPixelSize: maxPixelSize) else { return nil }
        let memoryKey = key as NSString
        if let image = memory.object(forKey: memoryKey) {
            return ThumbnailResult(image: image, source: .memory)
        }

        let diskURL = cacheDirectory.appendingPathComponent("\(key).jpg")
        if fileManager.fileExists(atPath: diskURL.path), let image = UIImage(contentsOfFile: diskURL.path) {
            storeInMemory(image, key: memoryKey)
            return ThumbnailResult(image: image, source: .disk)
        }

        if let task = inFlight[key], let image = await task.value {
            guard !Task.isCancelled else { return nil }
            storeInMemory(image, key: memoryKey)
            return ThumbnailResult(image: image, source: .generated)
        }

        let decoder = self.decoder
        let limiter = self.limiter
        let task: Task<UIImage?, Never> = Task(priority: .utility) {
            guard !Task.isCancelled else { return nil }
            await limiter.acquire()
            let image = await decoder.decode(url: sourceURL, maxPixelSize: maxPixelSize)
            await limiter.release()
            return image
        }
        inFlight[key] = task
        let generated = await task.value
        inFlight[key] = nil
        guard !Task.isCancelled, let generated else { return nil }

        storeInMemory(generated, key: memoryKey)
        if let data = generated.jpegData(compressionQuality: 0.84) {
            do {
                try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
                try data.write(to: diskURL, options: Data.WritingOptions.atomic)
            } catch {
                // The disk layer is an optimization. A write failure must not hide a valid thumbnail.
            }
        }
        return ThumbnailResult(image: generated, source: .generated)
    }

    public func clearMemory() {
        memory.removeAllObjects()
    }

    public func clearDisk() throws {
        if fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.removeItem(at: cacheDirectory)
        }
    }

    private func storeInMemory(_ image: UIImage, key: NSString) {
        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)
        memory.setObject(image, forKey: key, cost: max(width * height * 4, 1))
    }

    private func cacheKey(for sourceURL: URL, maxPixelSize: Int) -> String? {
        guard let values = try? sourceURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return nil
        }
        let size = values.fileSize ?? 0
        let modified = Int64((values.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1_000)
        let material = "\(sourceURL.standardizedFileURL.path)|\(maxPixelSize)|\(size)|\(modified)"
        return String(format: "%016llx-%d", Self.fnv1a(material), maxPixelSize)
    }

    private static func fnv1a(_ string: String) -> UInt64 {
        string.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}

private actor ThumbnailDecodeLimiter {
    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(limit, 1)
    }

    func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            active = max(active - 1, 0)
        } else {
            waiters.removeFirst().resume()
        }
    }
}

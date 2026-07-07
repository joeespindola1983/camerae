import SwiftUI
import UIKit
import ImageIO

struct ReferenceThumbnail: View {
    let imageURL: URL?
    let systemImage: String

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.thinMaterial)
            }
        }
        .frame(width: 64, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.secondary.opacity(0.2), lineWidth: 1)
        }
        .task(id: imageURL) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let imageURL else {
            image = nil
            return
        }

        image = await ThumbnailCache.thumbnail(for: imageURL, maxPixelSize: 220)
    }
}

enum ThumbnailCache {
    static let directoryName = "Thumbnail Cache"

    static func thumbnail(for sourceURL: URL, maxPixelSize: Int) async -> UIImage? {
        await Task.detached(priority: .utility) {
            autoreleasepool {
                guard let cacheURL = cachedThumbnailURL(for: sourceURL, maxPixelSize: maxPixelSize) else {
                    return generatedThumbnail(for: sourceURL, maxPixelSize: maxPixelSize)
                }

                if FileManager.default.fileExists(atPath: cacheURL.path),
                   let cachedImage = UIImage(contentsOfFile: cacheURL.path) {
                    return cachedImage
                }

                guard let thumbnail = generatedThumbnail(for: sourceURL, maxPixelSize: maxPixelSize) else {
                    return nil
                }

                if let data = thumbnail.jpegData(compressionQuality: 0.86) {
                    do {
                        try FileManager.default.createDirectory(
                            at: cacheURL.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        try data.write(to: cacheURL, options: [.atomic])
                    } catch {
                        print("camerae-debug thumbnail-cache write failed \(cacheURL.path): \(error.localizedDescription)")
                    }
                }

                return thumbnail
            }
        }.value
    }

    private static func generatedThumbnail(for sourceURL: URL, maxPixelSize: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: image)
    }

    private static func cachedThumbnailURL(for sourceURL: URL, maxPixelSize: Int) -> URL? {
        do {
            let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let fileSize = values.fileSize ?? 0
            let modificationStamp = Int(values.contentModificationDate?.timeIntervalSince1970 ?? 0)
            let cacheDirectory = sourceURL
                .deletingLastPathComponent()
                .appendingPathComponent(directoryName, isDirectory: true)
            let baseName = safeCacheBaseName(sourceURL.deletingPathExtension().lastPathComponent)
            let fileName = "\(baseName)-\(maxPixelSize)-\(fileSize)-\(modificationStamp).jpg"
            return cacheDirectory.appendingPathComponent(fileName)
        } catch {
            print("camerae-debug thumbnail-cache metadata failed \(sourceURL.path): \(error.localizedDescription)")
            return nil
        }
    }

    private static func safeCacheBaseName(_ name: String) -> String {
        let parts = name.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let safeName = parts.filter { !$0.isEmpty }.joined(separator: "_")
        return safeName.isEmpty ? "thumbnail" : safeName
    }
}

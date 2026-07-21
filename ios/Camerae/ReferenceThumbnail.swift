import CameraeMedia
import SwiftUI
import UIKit

struct ReferenceThumbnail: View {
    let imageURL: URL?
    let systemImage: String
    var width: CGFloat? = 64
    var height: CGFloat = 48
    var maxPixelSize = 220
    var usesNeutralImagePlaceholder = false

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                if usesNeutralImagePlaceholder {
                    Color(red: 229 / 255, green: 231 / 255, blue: 235 / 255)
                        .overlay {
                            Image(systemName: systemImage)
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(Color(.systemGray))
                                .frame(width: 44, height: 44)
                                .background(Color.white.opacity(0.82), in: Circle())
                        }
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.secondary.opacity(0.12))
                }
            }
        }
        .frame(maxWidth: width == nil ? .infinity : nil)
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
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

        image = await ThumbnailPipeline.shared.thumbnail(for: imageURL, maxPixelSize: maxPixelSize)?.image
    }
}

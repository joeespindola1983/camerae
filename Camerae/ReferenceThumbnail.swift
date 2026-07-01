import SwiftUI
import UIKit

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
            loadImage()
        }
    }

    private func loadImage() {
        guard let imageURL else {
            image = nil
            return
        }

        image = UIImage(contentsOfFile: imageURL.path)
    }
}

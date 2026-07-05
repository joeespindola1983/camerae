import SwiftUI

struct ExportedArchivesView: View {
    let urls: [URL]

    @State private var shareItem: ExportArchiveShareItem?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Arquivos") {
                    ForEach(urls, id: \.path) { url in
                        HStack(spacing: 12) {
                            Image(systemName: "doc.zipper")
                                .font(.title3)
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(url.lastPathComponent)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(2)

                                Text(fileSizeLabel(for: url))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                shareItem = ExportArchiveShareItem(url: url)
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("ZIPs exportados")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url])
            }
        }
    }

    private func fileSizeLabel(for url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

private struct ExportArchiveShareItem: Identifiable {
    let url: URL

    var id: String { url.path }
}

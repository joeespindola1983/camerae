import SwiftUI

struct BlockingProgressOverlay: View {
    let title: String
    let message: String
    var detail: String?
    var cancelTitle: String?
    var cancelAction: (() -> Void)?

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)

                Text(title)
                    .font(.headline)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let detail {
                    Text(detail)
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                if let cancelTitle, let cancelAction {
                    Button(role: .cancel) {
                        cancelAction()
                    } label: {
                        Text(cancelTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
            .frame(maxWidth: 280)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(radius: 18)
        }
        .allowsHitTesting(true)
    }
}

import SwiftUI

enum CameraeNextOperationState: Equatable, Sendable {
    case idle
    case processing(title: String, detail: String?, canCancel: Bool)
    case success(String)
    case failure(String)
}

struct CameraeNextOperationPresentation: Equatable, Sendable {
    let title: String?
    let message: String?
    let detail: String?
    let symbol: String
    let isBlocking: Bool
    let canCancel: Bool

    init(state: CameraeNextOperationState) {
        switch state {
        case .idle:
            title = nil
            message = nil
            detail = nil
            symbol = "circle"
            isBlocking = false
            canCancel = false
        case let .processing(titleValue, detailValue, cancellation):
            title = titleValue
            message = "Mantenha o Camerae aberto até a operação terminar."
            detail = detailValue
            symbol = "progress.indicator"
            isBlocking = true
            canCancel = cancellation
        case let .success(messageValue):
            title = "Concluído"
            message = messageValue
            detail = nil
            symbol = "checkmark.circle"
            isBlocking = false
            canCancel = false
        case let .failure(messageValue):
            title = "Não foi possível concluir"
            message = messageValue
            detail = nil
            symbol = "exclamationmark.triangle"
            isBlocking = false
            canCancel = false
        }
    }
}

struct CameraeNextOperationOverlay: View {
    let state: CameraeNextOperationState
    let theme: CameraeNextTheme
    var onCancel: (() -> Void)?

    private var presentation: CameraeNextOperationPresentation { .init(state: state) }

    var body: some View {
        if presentation.isBlocking {
            ZStack {
                Color.black.opacity(0.58).ignoresSafeArea()

                CameraeNextCard(theme: theme) {
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(theme.accent)
                        Text(presentation.title ?? "Processando")
                            .font(.custom("Outfit-SemiBold", size: 18, relativeTo: .headline))
                            .foregroundStyle(theme.text)
                        if let message = presentation.message {
                            Text(message)
                                .font(.custom("Outfit-Regular", size: 13, relativeTo: .subheadline))
                                .foregroundStyle(theme.muted)
                                .multilineTextAlignment(.center)
                        }
                        if let detail = presentation.detail {
                            Text(detail)
                                .font(.custom("DMMono-Regular", size: 11, relativeTo: .caption))
                                .foregroundStyle(theme.accent)
                        }
                        if presentation.canCancel, let onCancel {
                            CameraeNextActionButton(
                                title: "Cancelar",
                                systemImage: "xmark",
                                theme: theme,
                                style: .secondary,
                                action: onCancel
                            )
                        }
                    }
                }
                .frame(maxWidth: 310)
                .padding(24)
            }
            .allowsHitTesting(true)
        }
    }
}

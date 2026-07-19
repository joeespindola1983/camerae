import SwiftUI

struct CameraeNextCaptureCompletionPresentation: Equatable, Sendable {
    let title: String
    let message: String
    let primaryActionTitle: String
    let offersProcessing: Bool
    let accentTheme: CameraeWorkflowTheme

    init(module: CameraModule) {
        if module == .astrophotography {
            title = "Sessão concluída"
            message = "As imagens foram salvas. Agora você pode revisar, empilhar e finalizar o resultado Astro."
            primaryActionTitle = "Processar imagens"
            offersProcessing = true
            accentTheme = .astro
        } else {
            title = "Captura concluída"
            message = "O material foi salvo no projeto e já está disponível na lista de sessões."
            primaryActionTitle = "Voltar ao projeto"
            offersProcessing = false
            accentTheme = .repeatable
        }
    }
}

struct CameraeNextCompletedCapture: Identifiable, Equatable {
    let id = UUID()
    let module: CameraModule
    let session: TimelapseSession?
}

struct CameraeNextCaptureCompletionView: View {
    let capture: CameraeNextCompletedCapture
    let onDone: () -> Void
    let onOpenSessions: () -> Void

    @State private var isPresentingProcessing = false

    private var presentation: CameraeNextCaptureCompletionPresentation {
        .init(module: capture.module)
    }
    private var theme: CameraeNextTheme { .init(workflow: presentation.accentTheme) }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(theme.accent.opacity(0.16))
                        .frame(width: 132, height: 132)
                    Circle()
                        .stroke(theme.accent.opacity(0.34), lineWidth: 1)
                        .frame(width: 104, height: 104)
                    Image(systemName: presentation.offersProcessing ? "sparkles" : "checkmark")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(theme.accent)
                }

                VStack(spacing: 10) {
                    Text(presentation.title)
                        .font(.custom("Outfit-SemiBold", size: 26, relativeTo: .title2))
                        .foregroundStyle(theme.text)
                    Text(presentation.message)
                        .font(.custom("Outfit-Regular", size: 15, relativeTo: .body))
                        .foregroundStyle(theme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 330)
                }

                if let session = capture.session {
                    CameraeNextCard(theme: theme) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                CameraeNextSectionLabel(title: "Sessão", theme: theme)
                                Text(session.name)
                                    .font(.custom("Outfit-SemiBold", size: 15, relativeTo: .headline))
                                    .foregroundStyle(theme.text)
                                Text(session.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                                    .foregroundStyle(theme.muted)
                            }
                            Spacer()
                            Image(systemName: "photo.stack")
                                .font(.title2)
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .frame(maxWidth: 358)
                }

                Spacer()

                VStack(spacing: 10) {
                    CameraeNextActionButton(
                        title: presentation.primaryActionTitle,
                        systemImage: presentation.offersProcessing ? "wand.and.stars" : "arrow.left",
                        theme: theme,
                        isDisabled: presentation.offersProcessing && capture.session == nil
                    ) {
                        if presentation.offersProcessing {
                            isPresentingProcessing = true
                        } else {
                            onDone()
                        }
                    }

                    CameraeNextActionButton(
                        title: "Ver sessões",
                        systemImage: "rectangle.stack",
                        theme: theme,
                        style: .secondary,
                        action: onOpenSessions
                    )
                }
                .frame(maxWidth: 358)
            }
            .padding(16)
        }
        .preferredColorScheme(theme.colorScheme)
        .onAppear { AppOrientationLock.shared.restorePortrait() }
        .fullScreenCover(isPresented: $isPresentingProcessing) {
            if let session = capture.session {
                NavigationStack {
                    CameraeNextAstroProcessingView(session: session) {
                        isPresentingProcessing = false
                        onDone()
                    }
                }
            }
        }
    }
}

struct CameraeNextAstroProcessingView: View {
    let session: TimelapseSession
    let onClose: () -> Void

    var body: some View {
        AstroProcessingView(session: session, onComplete: onClose)
            .cameraeTheme(.astro)
    }
}

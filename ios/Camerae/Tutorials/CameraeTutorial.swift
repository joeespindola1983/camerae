import AVKit
import Foundation
import SwiftUI

enum CameraeTutorialID: String, Hashable, Sendable {
    case spatialMapping
}

struct CameraeTutorial: Equatable, Sendable {
    let id: CameraeTutorialID
    let contentVersion: Int
    let title: String
    let detail: String
    let videoResourceName: String
    let fallbackSteps: [String]

    static let spatialMapping = CameraeTutorial(
        id: .spatialMapping,
        contentVersion: 1,
        title: "Como mapear o local",
        detail: "Veja como caminhar pela cena e manter o tripé em foco.",
        videoResourceName: "spatial-mapping-tutorial",
        fallbackSteps: [
            "Mantenha o tripé parado e enquadrado durante todo o processo.",
            "Caminhe devagar ao redor dele, incluindo o chão e objetos fixos.",
            "Evite pessoas, veículos e movimentos rápidos até a cena estar pronta."
        ]
    )
}

final class CameraeTutorialProgressStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func shouldPresent(_ tutorial: CameraeTutorial) -> Bool {
        defaults.integer(forKey: key(for: tutorial.id)) < tutorial.contentVersion
    }

    func markCompleted(_ tutorial: CameraeTutorial) {
        defaults.set(tutorial.contentVersion, forKey: key(for: tutorial.id))
    }

    private func key(for id: CameraeTutorialID) -> String {
        "camerae.tutorial.\(id.rawValue).completed-content-version"
    }
}

enum CameraeTutorialEntryPoint: Equatable, Sendable {
    case firstUse
    case help
}

enum CameraeTutorialRoute: Equatable, Sendable {
    case present
    case continueToFeature
}

enum CameraeTutorialPresentationPolicy {
    static func route(
        for entryPoint: CameraeTutorialEntryPoint,
        tutorial: CameraeTutorial,
        progressStore: CameraeTutorialProgressStore
    ) -> CameraeTutorialRoute {
        switch entryPoint {
        case .help:
            .present
        case .firstUse:
            progressStore.shouldPresent(tutorial) ? .present : .continueToFeature
        }
    }
}

enum CameraeTutorialVisualState: Equatable, Sendable {
    case poster
    case playing
    case paused
    case completed
    case unavailable
}

enum CameraeTutorialAction: Equatable, Sendable {
    case play
    case pause
    case replay
    case readFallback
    case continueToFeature
    case close
}

enum CameraeTutorialCapabilityPolicy {
    static func actions(for state: CameraeTutorialVisualState) -> [CameraeTutorialAction] {
        switch state {
        case .poster:
            [.play, .continueToFeature, .close]
        case .playing:
            [.pause, .continueToFeature, .close]
        case .paused:
            [.play, .continueToFeature, .close]
        case .completed:
            [.replay, .continueToFeature, .close]
        case .unavailable:
            [.readFallback, .continueToFeature, .close]
        }
    }
}

struct CameraeTutorialView: View {
    let tutorial: CameraeTutorial
    let onContinue: () -> Void
    let onClose: () -> Void

    @State private var player: AVPlayer?
    private let theme = CameraeNextTheme(workflow: .repeatable)

    init(
        tutorial: CameraeTutorial,
        bundle: Bundle = .main,
        onContinue: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.tutorial = tutorial
        self.onContinue = onContinue
        self.onClose = onClose
        let url = bundle.url(forResource: tutorial.videoResourceName, withExtension: "mp4")
        _player = State(initialValue: url.map(AVPlayer.init(url:)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("REPEATABLE · GUIA ESPACIAL")
                        .font(.custom("DMMono-Regular", size: 10, relativeTo: .caption2))
                        .tracking(1.2)
                        .foregroundStyle(theme.muted)

                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.text)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Fechar tutorial")
                }

                Text("Antes de mapear")
                    .font(.custom("Outfit-SemiBold", size: 28, relativeTo: .title))
                    .foregroundStyle(theme.text)

                Text(tutorial.detail)
                    .font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
                    .foregroundStyle(theme.muted)

                CameraeNextCard(theme: theme) {
                    VStack(alignment: .leading, spacing: 12) {
                        tutorialMedia

                        Text(tutorial.title)
                            .font(.custom("Outfit-SemiBold", size: 20, relativeTo: .title3))
                            .foregroundStyle(theme.text)

                        Text(
                            player == nil
                                ? "Siga estas instruções para continuar sem o vídeo."
                                : "Ande devagar ao redor do tripé até a cena estar pronta."
                        )
                        .font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
                        .foregroundStyle(theme.muted)

                        Text(player == nil ? "INSTRUÇÕES DISPONÍVEIS" : "CC · LEGENDAS")
                            .font(.custom("DMMono-Regular", size: 10, relativeTo: .caption2))
                            .tracking(1)
                            .foregroundStyle(theme.muted)
                    }
                }

                Text("Você poderá rever este tutorial na aba Tripé.")
                    .font(.custom("Outfit-Regular", size: 12, relativeTo: .caption))
                    .foregroundStyle(theme.muted)

                CameraeNextActionButton(
                    title: "Continuar sem assistir",
                    systemImage: nil,
                    theme: theme,
                    style: .secondary,
                    action: onContinue
                )
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(theme.background.ignoresSafeArea())
    }

    @ViewBuilder
    private var tutorialMedia: some View {
        if let player {
            VideoPlayer(player: player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(theme.border, lineWidth: 1)
                }
                .accessibilityLabel("Tutorial em vídeo: \(tutorial.title)")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label("Vídeo em preparação", systemImage: "play.slash")
                    .font(.custom("Outfit-SemiBold", size: 18, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                ForEach(Array(tutorial.fallbackSteps.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)")
                        .font(.custom("Outfit-Regular", size: 14, relativeTo: .body))
                        .foregroundStyle(theme.muted)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Instruções alternativas para \(tutorial.title)")
        }
    }
}

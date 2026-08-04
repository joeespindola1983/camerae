import Foundation
import OSLog

enum CameraeCaptureDiagnostics {
    private static let logger = Logger(subsystem: "com.espindola.camerae", category: "CameraeCapture")

    nonisolated static func event(_ stage: String, _ detail: String = "") {
        let suffix = detail.isEmpty ? "" : " | \(detail)"
        logger.notice("[CameraeCapture] \(stage, privacy: .public)\(suffix, privacy: .public)")
    }

    nonisolated static func error(_ stage: String, _ detail: String) {
        logger.error("[CameraeCapture] \(stage, privacy: .public) | \(detail, privacy: .public)")
    }
}

struct CameraeAlignmentDiagnosticSession: Equatable, Sendable {
    let id: String

    init(id: String = String(UUID().uuidString.prefix(8))) {
        self.id = id
    }
}

enum CameraeLiveAlignmentDiagnostics {
    private static let logger = Logger(
        subsystem: "com.espindola.camerae",
        category: "CameraeAlignment"
    )

    nonisolated static func event(
        _ event: CameraeAlignmentDiagnosticEvent,
        sessionID: String,
        _ detail: String = ""
    ) {
        let suffix = detail.isEmpty ? "" : " | \(detail)"
        logger.notice(
            "[CameraeAlignment] session=\(sessionID, privacy: .public) | event=\(event.rawValue, privacy: .public)\(suffix, privacy: .public)"
        )
    }

    nonisolated static func error(
        _ event: CameraeAlignmentDiagnosticEvent,
        sessionID: String,
        _ detail: String
    ) {
        logger.error(
            "[CameraeAlignment] session=\(sessionID, privacy: .public) | event=\(event.rawValue, privacy: .public) | \(detail, privacy: .public)"
        )
    }
}

enum CameraeCaptureLifecycleState: Equatable, Sendable {
    case idle
    case preparing
    case running
    case unauthorized
    case failed(String)
    case stopped
}

struct CameraeCaptureLifecyclePresentation: Equatable, Sendable {
    let title: String?
    let message: String?
    let showsProgress: Bool

    init(state: CameraeCaptureLifecycleState) {
        switch state {
        case .idle, .stopped:
            title = nil
            message = nil
            showsProgress = false
        case .preparing:
            title = "Abrindo câmera"
            message = "Preparando o preview e os sensores de alinhamento."
            showsProgress = true
        case .running:
            title = nil
            message = nil
            showsProgress = false
        case .unauthorized:
            title = "Acesso à câmera necessário"
            message = "Ative a câmera para o Camerae nos Ajustes do iPhone."
            showsProgress = false
        case let .failed(error):
            title = "Não foi possível abrir a câmera"
            message = error
            showsProgress = false
        }
    }

    var isVisible: Bool { title != nil }
}

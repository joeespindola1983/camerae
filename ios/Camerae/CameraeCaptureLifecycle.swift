import Foundation
import OSLog
import SwiftUI

struct CameraFocusMeasurement: Equatable, Sendable {
    let sharpness: Double
    let isAdjustingFocus: Bool
    let capturedAt: Date
}

enum CameraFocusPreflightDecision: Equatable, Sendable {
    case wait
    case ready
    case needsUserFocus
}

enum CameraFocusPreflightState: Equatable, Sendable {
    case idle
    case checking
    case ready
    case needsUserFocus
}

enum CameraFocusPreflightPolicy {
    static let minimumSharpness = 0.035
    static let maximumWait: TimeInterval = 2.5
    static let maximumMeasurementAge: TimeInterval = 0.75

    static func decision(
        measurement: CameraFocusMeasurement?,
        elapsed: TimeInterval,
        now: Date = Date()
    ) -> CameraFocusPreflightDecision {
        guard let measurement,
              now.timeIntervalSince(measurement.capturedAt) <= maximumMeasurementAge,
              !measurement.isAdjustingFocus else {
            return elapsed < maximumWait ? .wait : .needsUserFocus
        }
        if measurement.sharpness >= minimumSharpness {
            return .ready
        }
        return elapsed < maximumWait ? .wait : .needsUserFocus
    }
}

enum CameraFocusRecoveryCapability: Equatable, Sendable {
    case tapToFocus
    case retryAutomaticFocus
    case captureAnyway
}

enum CameraFocusRecoveryCapabilityPolicy {
    static func actions(for state: CameraFocusPreflightState) -> [CameraFocusRecoveryCapability] {
        state == .needsUserFocus
            ? [.tapToFocus, .retryAutomaticFocus, .captureAnyway]
            : []
    }
}

enum CameraCaptureFocusRequirementPolicy {
    static func requiresPreflight(for _: RepeatableCaptureKind) -> Bool { true }
}

enum CameraFocusSharpnessAnalyzer {
    static func score(
        luma: [UInt8],
        width: Int,
        height: Int,
        bytesPerRow: Int
    ) -> Double {
        luma.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            return score(
                luma: baseAddress,
                width: width,
                height: height,
                bytesPerRow: bytesPerRow
            )
        }
    }

    static func score(
        luma: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        bytesPerRow: Int
    ) -> Double {
        let block = 4
        let sampledWidth = width / block
        let sampledHeight = height / block
        guard sampledWidth >= 3, sampledHeight >= 3 else { return 0 }

        var sampled = Array(repeating: Double.zero, count: sampledWidth * sampledHeight)
        for sampledY in 0..<sampledHeight {
            for sampledX in 0..<sampledWidth {
                var total = 0
                for offsetY in 0..<block {
                    let row = (sampledY * block + offsetY) * bytesPerRow
                    for offsetX in 0..<block {
                        total += Int(luma[row + sampledX * block + offsetX])
                    }
                }
                sampled[sampledY * sampledWidth + sampledX] = Double(total) / Double(block * block)
            }
        }

        return laplacianScore(
            sampled: sampled,
            width: sampledWidth,
            height: sampledHeight
        )
    }

    static func scoreBGRA(
        pixels: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        bytesPerRow: Int
    ) -> Double {
        let block = 4
        let sampledWidth = width / block
        let sampledHeight = height / block
        guard sampledWidth >= 3, sampledHeight >= 3 else { return 0 }
        var sampled = Array(repeating: Double.zero, count: sampledWidth * sampledHeight)
        for sampledY in 0..<sampledHeight {
            for sampledX in 0..<sampledWidth {
                var total = 0.0
                for offsetY in 0..<block {
                    let row = (sampledY * block + offsetY) * bytesPerRow
                    for offsetX in 0..<block {
                        let pixel = row + (sampledX * block + offsetX) * 4
                        total += 0.0722 * Double(pixels[pixel])
                            + 0.7152 * Double(pixels[pixel + 1])
                            + 0.2126 * Double(pixels[pixel + 2])
                    }
                }
                sampled[sampledY * sampledWidth + sampledX] = total / Double(block * block)
            }
        }
        return laplacianScore(
            sampled: sampled,
            width: sampledWidth,
            height: sampledHeight
        )
    }

    private static func laplacianScore(
        sampled: [Double],
        width: Int,
        height: Int
    ) -> Double {
        var laplacianTotal = 0.0
        var sampleCount = 0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = sampled[y * width + x]
                let laplacian = abs(
                    4 * center
                        - sampled[y * width + x - 1]
                        - sampled[y * width + x + 1]
                        - sampled[(y - 1) * width + x]
                        - sampled[(y + 1) * width + x]
                )
                laplacianTotal += laplacian
                sampleCount += 1
            }
        }
        guard sampleCount > 0 else { return 0 }
        return laplacianTotal / Double(sampleCount) / 255
    }
}

enum CameraeCaptureStartCountdown {
    static let seconds = [3, 2, 1]
}

struct CameraeCaptureCountdownPresentation: Equatable, Sendable {
    let startSeconds: Int?
    let isCaptureRunning: Bool
    let isInformationVisible: Bool
    let remainingLabel: String?

    var centeredStartSeconds: Int? { startSeconds }

    var cornerRemainingLabel: String? {
        guard startSeconds == nil, isCaptureRunning, !isInformationVisible else { return nil }
        return remainingLabel
    }
}

struct CameraeCaptureStartCountdownOverlay: View {
    let seconds: Int

    var body: some View {
        VStack(spacing: 8) {
            Text("A CAPTURA COMEÇA EM")
                .font(.custom("DMMono-Regular", size: 11, relativeTo: .caption))
                .tracking(1.4)
            Text("\(seconds)")
                .font(.system(size: 76, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
        }
        .foregroundStyle(.white)
        .padding(28)
        .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A captura começa em \(seconds) segundos")
    }
}

struct CameraeCaptureRemainingCountdownOverlay: View {
    let label: String

    var body: some View {
        Label(label, systemImage: "timer")
            .font(.system(.body, design: .monospaced, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(.black.opacity(0.72), in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.2), lineWidth: 1) }
            .accessibilityLabel("Tempo restante")
            .accessibilityValue(label)
    }
}

struct CameraFocusRecoveryOverlay: View {
    let retryAutomaticFocus: () -> Void
    let captureAnyway: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "viewfinder")
                .font(.system(size: 28, weight: .medium))
            Text("Foco não confirmado")
                .font(.headline)
            Text("Toque na imagem sobre o assunto principal ou tente novamente com foco automático central.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.76))
                .multilineTextAlignment(.center)
            Button("Foco automático central", action: retryAutomaticFocus)
                .buttonStyle(.borderedProminent)
            Button("Capturar mesmo assim", action: captureAnyway)
                .buttonStyle(.bordered)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: 330)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture-focus-recovery")
    }
}

struct CameraFocusCheckingOverlay: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(.white)
            Text("Verificando foco")
                .font(.headline)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(.black.opacity(0.76), in: Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.2), lineWidth: 1) }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

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

enum CameraeCaptureLifecycleState: Equatable, Sendable {
    case idle
    case preparing
    case running
    case unauthorized
    case failed(String)
    case stopped
}

enum RepeatableLiveViewCapability: Hashable, Sendable {
    case leave
    case switchLens
    case startCapture
    case stopCapture
}

enum RepeatableLiveViewCapabilityPolicy {
    static func actions(
        isCaptureActive: Bool,
        availableLensCount: Int
    ) -> Set<RepeatableLiveViewCapability> {
        if isCaptureActive {
            return [.stopCapture]
        }
        var actions: Set<RepeatableLiveViewCapability> = [.leave, .startCapture]
        if availableLensCount > 1 {
            actions.insert(.switchLens)
        }
        return actions
    }
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

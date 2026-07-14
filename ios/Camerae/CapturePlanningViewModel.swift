import CameraeCore
import Combine
import Foundation
import SwiftUI
import UIKit

@MainActor
final class CapturePlanningViewModel: ObservableObject {
    @Published private(set) var result: CapturePreflightResult?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let service: CapturePreflightService
    private var evaluationID: UUID?

    init(service: CapturePreflightService) {
        self.service = service
    }

    convenience init(projectDirectoryURL: URL) {
        self.init(service: CapturePreflightService(
            storageProvider: VolumeStorageCapacityProvider(rootURL: projectDirectoryURL),
            batteryProvider: SystemBatterySnapshotProvider()
        ))
    }

    func evaluate(
        plan: CapturePlan,
        sizeProfile: CaptureSizeProfile,
        capabilityProfile: DeviceCapabilityProfile,
        observedDrainPerHour: Double?
    ) async {
        let currentID = UUID()
        evaluationID = currentID
        isLoading = true
        result = nil
        errorMessage = nil
        defer {
            if evaluationID == currentID {
                isLoading = false
            }
        }

        do {
            let evaluated = try await service.evaluate(
                plan: plan,
                sizeProfile: sizeProfile,
                capabilityProfile: capabilityProfile,
                observedDrainPerHour: observedDrainPerHour
            )
            guard !Task.isCancelled, evaluationID == currentID else { return }
            result = evaluated
        } catch is CancellationError {
            return
        } catch {
            guard evaluationID == currentID else { return }
            result = nil
            errorMessage = error.localizedDescription
        }
    }
}

struct CapturePreflightPresentation: Equatable {
    let canStart: Bool
    let title: String
    let detail: String

    init(storage: CaptureAdmissionResult) {
        switch storage.decision {
        case .allowed:
            canStart = true
            title = "Captura viável"
            detail = Self.capacityDetail(storage)
        case .warning:
            canStart = true
            title = "Margem de espaço reduzida"
            detail = Self.capacityDetail(storage)
        case .blocked:
            canStart = false
            title = "Espaço insuficiente"
            detail = "Libere pelo menos \(Self.bytes(storage.shortfallBytes)) antes de iniciar."
        case .unknown:
            canStart = false
            title = "Espaço não disponível"
            detail = "Não foi possível confirmar a capacidade deste volume."
        }
    }

    private static func capacityDetail(_ storage: CaptureAdmissionResult) -> String {
        guard let required = storage.requiredBytes, let available = storage.availableBytes else {
            return "A capacidade será monitorada durante a captura."
        }
        return "Necessário \(bytes(required)) • disponível \(bytes(available))"
    }

    private static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }
}

struct CapturePreflightMetricsPresentation: Equatable {
    let primary: String
    let secondary: String

    init(plan: CapturePlan, estimate: CaptureEstimate) {
        switch plan.workflow {
        case .repeatableVideo:
            primary = "Vídeo \(Self.duration(plan.plannedDuration))"
            secondary = "\(Self.resolution(plan.resolution)) • \(plan.captureFPS ?? 0) FPS • captura ~\(Self.bytes(estimate.captureBytes))"
        case .repeatableTimelapse, .astro:
            primary = "\(estimate.expectedFrameCount) frames • vídeo \(Self.duration(estimate.renderedDuration ?? 0))"
            secondary = "\(plan.sourceFormat.rawValue.uppercased()) • captura ~\(Self.bytes(estimate.captureBytes))"
        }
    }

    private static func resolution(_ resolution: CaptureResolution) -> String {
        switch resolution {
        case .highDefinition: "HD"
        case .fullHD: "FHD"
        case .ultraHD: "4K"
        case .fullSensor: "Resolução máxima"
        }
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }
}

struct CapturePreflightCard: View {
    @ObservedObject var model: CapturePlanningViewModel

    var body: some View {
        Group {
            if model.isLoading {
                HStack {
                    ProgressView()
                    Text("Calculando espaço e bateria")
                }
            } else if let result = model.result {
                let presentation = CapturePreflightPresentation(storage: result.storage)
                let metrics = CapturePreflightMetricsPresentation(
                    plan: result.resolvedPlan,
                    estimate: result.estimate
                )
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        presentation.title,
                        systemImage: presentation.canStart ? "checkmark.circle" : "externaldrive.badge.exclamationmark"
                    )
                    .font(.caption.weight(.semibold))
                    Text(presentation.detail)
                        .font(.caption2)
                    Text(metrics.primary)
                        .font(.caption2.weight(.semibold))
                    Text(metrics.secondary)
                        .font(.caption2)
                    if result.energy.externalPowerRecommended {
                        Text("Alimentação externa recomendada")
                            .font(.caption2.weight(.semibold))
                    }
                    if result.formatFallbackReason != nil {
                        Text("Formato ajustado antes da captura por compatibilidade")
                            .font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(model.errorMessage ?? "Aguardando estimativa")
                    .font(.caption)
            }
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

}

struct SystemBatterySnapshotProvider: BatterySnapshotProviding, @unchecked Sendable {
    func snapshot() async -> BatterySnapshot {
        await MainActor.run {
            UIDevice.current.isBatteryMonitoringEnabled = true
            let level = UIDevice.current.batteryLevel
            return BatterySnapshot(
                level: level >= 0 ? Double(level) : nil,
                state: Self.batteryState(UIDevice.current.batteryState),
                isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
                thermalState: Self.thermalState(ProcessInfo.processInfo.thermalState),
                capturedAt: Date()
            )
        }
    }

    private static func batteryState(_ state: UIDevice.BatteryState) -> BatteryState {
        switch state {
        case .unplugged: .unplugged
        case .charging: .charging
        case .full: .full
        case .unknown: .unknown
        @unknown default: .unknown
        }
    }

    private static func thermalState(_ state: ProcessInfo.ThermalState) -> CaptureThermalState {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .unknown
        }
    }
}

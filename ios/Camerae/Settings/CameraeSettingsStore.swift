import CameraeCore
import Foundation

enum CameraePerformanceMode: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case economy
    case maximumQuality

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: CameraeL10n.settingsPerformanceAutomatic
        case .economy: CameraeL10n.settingsPerformanceEconomy
        case .maximumQuality: CameraeL10n.settingsPerformanceMaximum
        }
    }
}

enum CameraePhotoQualityMode: Equatable, Sendable {
    case speed
    case balanced
    case quality
}

enum CameraeVisionPerformanceCadence: Equatable, Sendable {
    case conservative
    case balanced
    case quality
}

struct CameraePerformancePolicy: Equatable, Sendable {
    let mode: CameraePerformanceMode

    var photoQuality: CameraePhotoQualityMode {
        switch mode {
        case .automatic: .balanced
        case .economy: .speed
        case .maximumQuality: .quality
        }
    }

    var visionCadence: CameraeVisionPerformanceCadence {
        switch mode {
        case .automatic: .balanced
        case .economy: .conservative
        case .maximumQuality: .quality
        }
    }

    func resolvedPhotoQuality(
        isLowPowerModeEnabled: Bool,
        thermalState: ProcessInfo.ThermalState
    ) -> CameraePhotoQualityMode {
        if thermalState == .serious || thermalState == .critical {
            return .speed
        }
        guard mode == .automatic else { return photoQuality }
        if isLowPowerModeEnabled {
            return .speed
        }
        return thermalState == .fair ? .speed : .balanced
    }
}

struct CameraeStorageWarningPolicy: Equatable, Sendable {
    let isEnabled: Bool

    func shouldPresent(_ result: CaptureStorageGuardResult) -> Bool {
        isEnabled && result.decision == .warning
    }

    func mustStop(_ result: CaptureStorageGuardResult) -> Bool {
        result.decision == .stop
    }
}

@MainActor
final class CameraeSettingsStore: ObservableObject {
    static let shared = CameraeSettingsStore()

    enum Key {
        static let diagnosticsEnabled = "settings.privacy.diagnosticsEnabled"
        static let analyticsEnabled = "settings.privacy.analyticsEnabled"
        static let repeatableFormat = "settings.capture.repeatableFormat"
        static let astroFormat = "settings.capture.astroFormat"
        static let performanceMode = "settings.capture.performanceMode"
        static let preserveOriginals = "settings.storage.preserveOriginals"
        static let lowStorageWarning = "settings.storage.lowStorageWarning"
    }

    private let defaults: UserDefaults
    private let onDiagnosticsChanged: @MainActor (CameraeDiagnosticsConsentState) -> Void

    @Published var diagnosticsEnabled: Bool {
        didSet {
            defaults.set(diagnosticsEnabled, forKey: Key.diagnosticsEnabled)
            notifyDiagnosticsChanged()
        }
    }
    @Published var analyticsEnabled: Bool {
        didSet {
            defaults.set(analyticsEnabled, forKey: Key.analyticsEnabled)
            notifyDiagnosticsChanged()
        }
    }
    @Published var repeatableFormat: CaptureSourceFormat {
        didSet { defaults.set(repeatableFormat.rawValue, forKey: Key.repeatableFormat) }
    }
    @Published var astroFormat: CaptureSourceFormat {
        didSet { defaults.set(astroFormat.rawValue, forKey: Key.astroFormat) }
    }
    @Published var performanceMode: CameraePerformanceMode {
        didSet { defaults.set(performanceMode.rawValue, forKey: Key.performanceMode) }
    }
    @Published var preserveOriginals: Bool {
        didSet { defaults.set(preserveOriginals, forKey: Key.preserveOriginals) }
    }
    @Published var lowStorageWarningEnabled: Bool {
        didSet { defaults.set(lowStorageWarningEnabled, forKey: Key.lowStorageWarning) }
    }

    var effectiveCrashCollectionEnabled: Bool { diagnosticsEnabled }
    var effectiveAnalyticsCollectionEnabled: Bool { diagnosticsEnabled && analyticsEnabled }

    init(
        defaults: UserDefaults = .standard,
        onDiagnosticsChanged: @escaping @MainActor (CameraeDiagnosticsConsentState) -> Void = {
            CameraeDiagnosticsConsent.shared.apply($0)
        }
    ) {
        self.defaults = defaults
        self.onDiagnosticsChanged = onDiagnosticsChanged
        diagnosticsEnabled = Self.bool(defaults, key: Key.diagnosticsEnabled, fallback: true)
        analyticsEnabled = Self.bool(defaults, key: Key.analyticsEnabled, fallback: true)
        repeatableFormat = Self.format(defaults, key: Key.repeatableFormat, fallback: .heic, allowed: [.heic, .jpeg])
        astroFormat = Self.format(defaults, key: Key.astroFormat, fallback: .dng, allowed: [.heic, .dng])
        performanceMode = defaults.string(forKey: Key.performanceMode)
            .flatMap(CameraePerformanceMode.init(rawValue:)) ?? .automatic
        preserveOriginals = Self.bool(defaults, key: Key.preserveOriginals, fallback: true)
        lowStorageWarningEnabled = Self.bool(defaults, key: Key.lowStorageWarning, fallback: true)
    }

    func defaultSourceFormat(for module: CameraModule) -> CaptureSourceFormat {
        switch module {
        case .repeatable: repeatableFormat
        case .astrophotography: astroFormat
        case .edit: .jpeg
        }
    }

    var performancePolicy: CameraePerformancePolicy {
        .init(mode: performanceMode)
    }

    var storageWarningPolicy: CameraeStorageWarningPolicy {
        .init(isEnabled: lowStorageWarningEnabled)
    }

    private func notifyDiagnosticsChanged() {
        onDiagnosticsChanged(.init(
            crashlyticsEnabled: effectiveCrashCollectionEnabled,
            analyticsEnabled: effectiveAnalyticsCollectionEnabled
        ))
    }

    private static func bool(_ defaults: UserDefaults, key: String, fallback: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }

    private static func format(
        _ defaults: UserDefaults,
        key: String,
        fallback: CaptureSourceFormat,
        allowed: Set<CaptureSourceFormat>
    ) -> CaptureSourceFormat {
        guard let raw = defaults.string(forKey: key),
              let value = CaptureSourceFormat(rawValue: raw),
              allowed.contains(value) else { return fallback }
        return value
    }
}

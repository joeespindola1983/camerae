import CameraeCore
import Foundation

enum CameraePerformanceMode: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case economy
    case maximumQuality

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automático"
        case .economy: "Economia"
        case .maximumQuality: "Qualidade máxima"
        }
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

    @Published var diagnosticsEnabled: Bool {
        didSet {
            defaults.set(diagnosticsEnabled, forKey: Key.diagnosticsEnabled)
            CameraeDiagnosticsConsent.shared.apply(settings: self)
        }
    }
    @Published var analyticsEnabled: Bool {
        didSet {
            defaults.set(analyticsEnabled, forKey: Key.analyticsEnabled)
            CameraeDiagnosticsConsent.shared.apply(settings: self)
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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

import Foundation

protocol CameraeCrashReportingBackend: AnyObject {
    func setCollectionEnabled(_ enabled: Bool)
    func setValue(_ value: String, forKey key: String)
    func log(_ message: String)
}

struct CameraeCrashReportingConfiguration: Equatable {
    static let collectionEnabledKey = "CameraeCrashlyticsCollectionEnabled"
    static let releaseChannelKey = "CameraeReleaseChannel"

    let isEnabled: Bool
    let releaseChannel: String

    init(isEnabled: Bool, releaseChannel: String) {
        self.isEnabled = isEnabled
        self.releaseChannel = releaseChannel
    }

    init(infoDictionary: [String: Any]) {
        isEnabled = Self.boolValue(infoDictionary[Self.collectionEnabledKey])
        releaseChannel = (infoDictionary[Self.releaseChannelKey] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "unknown"
    }

    private static func boolValue(_ value: Any?) -> Bool {
        switch value {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            return (value as NSString).boolValue
        default:
            return false
        }
    }
}

enum CameraeDiagnosticModule: String {
    case app
    case repeatable
    case astro
    case edit

    init(module: CameraModule) {
        switch module {
        case .repeatable:
            self = .repeatable
        case .astrophotography:
            self = .astro
        case .edit:
            self = .edit
        }
    }
}

final class CameraeCrashReporter {
    static let shared = CameraeCrashReporter(backend: FirebaseCrashReportingBackend())

    private let backend: CameraeCrashReportingBackend
    private var isEnabled = false

    init(backend: CameraeCrashReportingBackend) {
        self.backend = backend
    }

    func start(
        configuration: CameraeCrashReportingConfiguration,
        appVersion: String,
        build: String
    ) {
        isEnabled = configuration.isEnabled
        backend.setCollectionEnabled(configuration.isEnabled)
        guard configuration.isEnabled else { return }

        backend.setValue(appVersion, forKey: "app_version")
        backend.setValue(build, forKey: "app_build")
        backend.setValue(configuration.releaseChannel, forKey: "release_channel")
        backend.setValue(CameraeDiagnosticModule.app.rawValue, forKey: "diagnostic_module")
        backend.log("camerae_started")
    }

    func setModule(_ module: CameraeDiagnosticModule) {
        guard isEnabled else { return }
        backend.setValue(module.rawValue, forKey: "diagnostic_module")
    }
}

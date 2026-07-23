import FirebaseCore
import UIKit

final class AppOrientationLock {
    static let shared = AppOrientationLock()

    private(set) var mask: UIInterfaceOrientationMask = .portrait

    private init() {}

    func lock(to orientation: CaptureDisplayOrientation?) {
        mask = orientation?.interfaceOrientationMask ?? .all
        applyGeometryPreference()
    }

    func unlock() {
        mask = .all
        applyGeometryPreference()
    }

    func restorePortrait() {
        mask = .portrait
        applyGeometryPreference()
    }

    private func applyGeometryPreference() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes where scene.activationState == .foregroundActive {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}

final class CameraeAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        let info = Bundle.main.infoDictionary ?? [:]
        let releaseConfiguration = CameraeCrashReportingConfiguration(infoDictionary: info)
        let settings = CameraeSettingsStore.shared
        CameraeDiagnosticsConsent.shared.configure(
            isCollectionAllowed: releaseConfiguration.isEnabled
        )
        CameraeCrashReporter.shared.start(
            configuration: .init(
                isEnabled: releaseConfiguration.isEnabled && settings.effectiveCrashCollectionEnabled,
                releaseChannel: releaseConfiguration.releaseChannel
            ),
            appVersion: info["CFBundleShortVersionString"] as? String ?? "unknown",
            build: info["CFBundleVersion"] as? String ?? "unknown"
        )
        CameraeDiagnosticsConsent.shared.apply(settings: settings)
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppOrientationLock.shared.mask
    }
}

private extension CaptureDisplayOrientation {
    var interfaceOrientationMask: UIInterfaceOrientationMask {
        switch self {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        }
    }
}

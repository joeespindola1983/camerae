import UIKit

final class AppOrientationLock {
    static let shared = AppOrientationLock()

    private(set) var mask: UIInterfaceOrientationMask = .all

    private init() {}

    func lock(to orientation: CaptureDisplayOrientation?) {
        mask = orientation?.interfaceOrientationMask ?? .all
        applyGeometryPreference()
    }

    func unlock() {
        mask = .all
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

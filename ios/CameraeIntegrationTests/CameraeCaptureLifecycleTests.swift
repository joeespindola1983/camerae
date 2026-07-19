import CoreLocation
import Testing
@testable import Camerae

struct CameraeCaptureLifecycleTests {
    @Test func preparingAndRunningUseDifferentPresentationStates() {
        #expect(CameraeCaptureLifecyclePresentation(state: .preparing).showsProgress)
        #expect(!CameraeCaptureLifecyclePresentation(state: .running).isVisible)
    }

    @Test func permissionAndConfigurationFailuresAreVisible() {
        let denied = CameraeCaptureLifecyclePresentation(state: .unauthorized)
        let failed = CameraeCaptureLifecyclePresentation(state: .failed("Câmera ocupada"))

        #expect(denied.title == "Acesso à câmera necessário")
        #expect(failed.title == "Não foi possível abrir a câmera")
        #expect(failed.message == "Câmera ocupada")
    }

    @Test func locationAuthorizationUsesDelegateStateWithoutGlobalServicesProbe() {
        #expect(CameraeLocationAuthorizationPolicy.action(for: .notDetermined) == .requestWhenInUse)
        #expect(CameraeLocationAuthorizationPolicy.action(for: .authorizedWhenInUse) == .startUpdates)
        #expect(CameraeLocationAuthorizationPolicy.action(for: .authorizedAlways) == .startUpdates)
        #expect(CameraeLocationAuthorizationPolicy.action(for: .denied) == .unavailable)
        #expect(CameraeLocationAuthorizationPolicy.action(for: .restricted) == .unavailable)
    }
}

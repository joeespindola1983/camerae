import SwiftUI
import UIKit

@main
struct CameraeApp: App {
    @UIApplicationDelegateAdaptor(CameraeAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            CameraeNextRootView()
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        UIApplication.shared.isIdleTimerDisabled = true
                    }
                }
        }
    }
}

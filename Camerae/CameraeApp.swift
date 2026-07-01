import SwiftUI

@main
struct CameraeApp: App {
    @UIApplicationDelegateAdaptor(CameraeAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

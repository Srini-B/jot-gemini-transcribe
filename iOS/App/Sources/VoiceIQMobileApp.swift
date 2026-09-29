import SwiftUI
import UIKit

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let model = AppModel()

    func applicationWillTerminate(_ application: UIApplication) {
        // The recording is finalized to disk; the next launch transcribes it.
        model.prepareForTermination()
    }
}

@main
struct VoiceIQMobileApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Theme.applyAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(delegate.model)
                .environmentObject(delegate.model.session)
                .environmentObject(delegate.model.hostReturn)
                .environmentObject(delegate.model.setup)
                .tint(Theme.Colors.accent)
                .onOpenURL { delegate.model.open($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: delegate.model.appBecameActive()
            case .background: delegate.model.appEnteredBackground()
            default: break
            }
        }
    }
}

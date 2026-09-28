// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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

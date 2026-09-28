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

import Foundation

/// Brings an app to the front by bundle ID, the way the app switcher does: it
/// resumes where it was, with no URL for the app to act on.
///
/// Uses `LSApplicationWorkspace`, which is private API. Everything is
/// resolved at runtime, so a missing class or selector returns false and the
/// caller falls back to a URL or the swipe-back screen.
enum AppLauncher {
    static func open(bundleID: String) -> Bool {
        guard let workspaceClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type else { return false }
        let defaultSelector = NSSelectorFromString("defaultWorkspace")
        guard workspaceClass.responds(to: defaultSelector),
              let workspace = workspaceClass.perform(defaultSelector)?.takeUnretainedValue() as? NSObject else { return false }
        let openSelector = NSSelectorFromString("openApplicationWithBundleID:")
        guard workspace.responds(to: openSelector) else { return false }
        typealias Open = @convention(c) (AnyObject, Selector, NSString) -> Bool
        let open = unsafeBitCast(workspace.method(for: openSelector), to: Open.self)
        return open(workspace, openSelector, bundleID as NSString)
    }
}

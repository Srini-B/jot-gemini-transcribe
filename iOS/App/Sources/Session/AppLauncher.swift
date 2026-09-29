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

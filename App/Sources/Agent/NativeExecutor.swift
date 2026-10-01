import AppKit
import PeekabooAutomationKit
import PeekabooFoundation
import VoiceIQCore

/// The agent's own panel, hidden while the whole screen is captured so the
/// model never sees or acts on its own transcript.
@MainActor
protocol AgentOverlay: AnyObject {
    func setHidden(_ hidden: Bool)
}

/// Agent mode's hands: Peekaboo's accessibility observer and CGEvent
/// actions, in this process. One instance per session, because element
/// ids only mean something against the snapshot that produced them and
/// the snapshot manager must outlive observe → act.
@MainActor
final class NativeExecutor: ActionExecutor {
    private let snapshots = InMemorySnapshotManager()
    private let automation: UIAutomationService
    private let apps = ApplicationService()
    private let observation: DesktopObservationService
    private let menus: MenuService
    private let permissions = PermissionsService()

    private var latest: AgentObservation?
    /// The screen rect, in points with a top-left origin, that the latest
    /// screenshot covers. `click_at` maps through it.
    private var capturedFrame: CGRect?
    /// The last app observed that is not VoiceiQ. When VoiceiQ itself is in
    /// front (the user clicked the panel), this is the app the agent is
    /// still working in.
    private var lastForeignBundleID: String?
    /// Hidden while the whole screen is captured.
    var overlay: AgentOverlay?

    /// Longest edge of the screenshot sent to the model. Enough to read
    /// menu text; small enough that a session of a dozen steps stays cheap.
    private static let maxImageEdge: CGFloat = 1280

    /// Where Peekaboo writes each observation PNG before we delete it.
    /// Purged on start so a crash mid-observe leaves nothing behind.
    private static let scratchDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("VoiceiQ-agent", isDirectory: true)

    /// Time an app gets to react before the next look, per action. Chrome
    /// did not have a result page up when the loop observed right after
    /// "press return"; the model then reported the search as not loaded.
    private static let settle: [AgentTool: UInt64] = [
        .click: 800_000_000, .clickAt: 800_000_000, .press: 800_000_000, .invokeMenu: 800_000_000,
        .type: 300_000_000, .scroll: 400_000_000, .openApp: 1_000_000_000,
    ]

    init() {
        try? FileManager.default.removeItem(at: Self.scratchDirectory)
        try? FileManager.default.createDirectory(at: Self.scratchDirectory, withIntermediateDirectories: true)
        let logging = LoggingService()
        let capture = ScreenCaptureService(loggingService: logging)
        automation = UIAutomationService(snapshotManager: snapshots, loggingService: logging)
        observation = DesktopObservationService(
            screenCapture: capture, automation: automation, applications: apps, snapshotManager: snapshots
        )
        menus = MenuService(applicationService: apps)
    }

    // MARK: - Permissions

    /// What the session needs before it can look or act. Empty when ready.
    static func missingPermissions() -> [String] {
        let permissions = PermissionsService()
        var missing: [String] = []
        if !permissions.checkScreenRecordingPermission() { missing.append("Screen Recording") }
        if !permissions.checkAccessibilityPermission() { missing.append("Accessibility") }
        return missing
    }

    // MARK: - ActionExecutor

    func observe() async -> AgentObservation {
        let missing = Self.missingPermissions()
        guard missing.isEmpty else {
            let result = AgentObservation(limitation: "\(missing.joined(separator: " and ")) permission is off for VoiceiQ in System Settings → Privacy & Security; the agent cannot see or act until it is on.")
            latest = result
            return result
        }
        do {
            return try await capture(target: workTarget())
        } catch {
            // No window to capture (desktop, a menu-only app): fall back to the
            // main display so the model still sees something.
            Log.session.info("agent window observe failed, trying screen: \(error.localizedDescription)")
            overlay?.setHidden(true)
            defer { overlay?.setHidden(false) }
            do {
                return try await capture(target: .screen(index: nil))
            } catch {
                let result = AgentObservation(limitation: "Couldn't capture the screen (\(error.localizedDescription)).")
                latest = result
                return result
            }
        }
    }

    /// The window the agent should look at. VoiceiQ in front means the user
    /// clicked the panel; the work is in the topmost window of any other
    /// app, or failing that the app observed before.
    private func workTarget() -> DesktopObservationTargetRequest {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if let frontmost, frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier { return .frontmost }
        if let pid = Self.topmostForeignWindowOwner() { return .pid(pid, window: nil) }
        if let lastForeignBundleID { return .app(identifier: lastForeignBundleID, window: nil) }
        return .frontmost
    }

    /// Owner of the first normal-layer window in the window list that is
    /// not ours. The list is front-to-back, so this is the window the user
    /// sees behind the panel.
    static func topmostForeignWindowOwner() -> pid_t? {
        let own = ProcessInfo.processInfo.processIdentifier
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        return windows.first {
            let pid = $0[kCGWindowOwnerPID as String] as? pid_t
            return pid != nil && pid != own && (($0[kCGWindowLayer as String] as? Int) ?? 1) == 0
        }?[kCGWindowOwnerPID as String] as? pid_t
    }

    /// Our visible windows, in points with a top-left origin, the space
    /// element frames use.
    static func ownWindowFrames() -> [CGRect] {
        guard let primary = NSScreen.screens.first else { return [] }
        return NSApp.windows.filter(\.isVisible).map { window in
            let frame = window.frame
            return CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
        }
    }

    func describe(_ call: AgentToolCall) -> String {
        guard let tool = AgentTool(rawValue: call.name) else { return call.name }
        switch tool {
        case .observe: return "Look at the screen"
        case .click:
            let kind = call.string("click_type") ?? "single"
            let verb = kind == "double" ? "Double-click" : kind == "right" ? "Right-click" : "Click"
            return "\(verb) \(elementName(call.string("element_id")))"
        case .clickAt:
            let x = call.int("x") ?? 0, y = call.int("y") ?? 0
            return "Click at \(x), \(y)"
        case .type:
            let text = call.string("text") ?? ""
            let target = call.string("element_id").map { " into \(elementName($0))" } ?? ""
            return "Type \"\(Self.clip(text))\"\(target)"
        case .press: return "Press \(call.string("keys") ?? "")"
        case .scroll: return "Scroll \(call.string("direction") ?? "down")"
        case .invokeMenu: return "Choose \(call.string("path") ?? "") from the menu"
        case .openApp: return "Open \(call.string("name") ?? "")"
        case .wait: return "Wait"
        case .webSearch: return "Search the web"
        case .fetchPage: return "Read a page"
        case .answer: return "Answer"
        case .done: return "Done"
        }
    }

    func perform(_ call: AgentToolCall, approved: Bool) async -> ActionOutcome {
        guard let tool = AgentTool(rawValue: call.name) else { return .failed("Unknown tool \(call.name).") }
        if !approved, let risk = riskDescription(for: call, tool: tool) {
            return .needsConfirmation(risk)
        }
        let outcome = await act(call, tool: tool)
        if case .done = outcome, let settle = Self.settle[tool] {
            try? await Task.sleep(nanoseconds: settle)
        }
        return outcome
    }

    private func act(_ call: AgentToolCall, tool: AgentTool) async -> ActionOutcome {
        do {
            switch tool {
            case .click:
                guard let id = call.string("element_id") else { return .failed("element_id is required.") }
                guard latest?.elements.contains(where: { $0.id == id }) == true else {
                    return .failed("No element \(id) in the latest observation. Observe again and use a current id.")
                }
                try await automation.click(target: .elementId(id), clickType: clickType(call), snapshotId: latest?.snapshotID)
                return .done("Clicked \(elementName(id)).")
            case .clickAt:
                guard let x = call.arguments["x"]?.doubleValue, let y = call.arguments["y"]?.doubleValue else {
                    return .failed("x and y are required.")
                }
                guard let point = screenPoint(imageX: x, imageY: y) else {
                    return .failed("No screenshot to map the point to. Observe first.")
                }
                try await automation.click(target: .coordinates(point), clickType: clickType(call), snapshotId: nil)
                return .done("Clicked at \(Int(point.x)), \(Int(point.y)) on screen.")
            case .type:
                guard let text = call.string("text") else { return .failed("text is required.") }
                if let id = call.string("element_id") {
                    try await automation.click(target: .elementId(id), clickType: .single, snapshotId: latest?.snapshotID)
                    try await Task.sleep(nanoseconds: 120_000_000)
                }
                var actions: [TypeAction] = []
                if call.bool("clear") == true { actions.append(.clear) }
                actions.append(.text(text))
                _ = try await automation.typeActions(actions, cadence: .fixed(milliseconds: 8), snapshotId: nil)
                return .done("Typed \(text.count) characters.")
            case .press:
                guard let keys = call.string("keys"), !keys.isEmpty else { return .failed("keys is required.") }
                try await press(keys)
                return .done("Pressed \(keys).")
            case .scroll:
                let direction = ScrollDirection(rawValue: call.string("direction") ?? "down") ?? .down
                let amount = max(1, min(call.int("amount") ?? 5, 50))
                try await automation.scroll(ScrollRequest(
                    direction: direction, amount: amount, target: call.string("element_id"),
                    snapshotId: latest?.snapshotID, foreground: true
                ))
                return .done("Scrolled \(direction.rawValue) \(amount).")
            case .invokeMenu:
                guard let path = call.string("path"), !path.isEmpty else { return .failed("path is required.") }
                guard let app = latest?.appName ?? NSWorkspace.shared.frontmostApplication?.localizedName else {
                    return .failed("No frontmost app to send the menu command to.")
                }
                try await menus.clickMenuItem(app: app, itemPath: path)
                return .done("Chose \(path) in \(app).")
            case .openApp:
                guard let name = call.string("name"), !name.isEmpty else { return .failed("name is required.") }
                do {
                    try await apps.activateApplication(identifier: name)
                } catch {
                    _ = try await apps.launchApplication(identifier: name)
                }
                return .done("\(name) is in front.")
            case .observe, .wait, .webSearch, .fetchPage, .answer, .done:
                return .failed("\(call.name) is not an action.")
            }
        } catch is CancellationError {
            return .failed("Stopped.")
        } catch {
            return .failed(Self.message(for: error))
        }
    }

    // MARK: - Observation

    private func capture(target: DesktopObservationTargetRequest) async throws -> AgentObservation {
        let result = try await observation.observe(DesktopObservationRequest(
            target: target,
            capture: DesktopCaptureOptions(engine: .modern),
            detection: DesktopDetectionOptions(
                mode: .accessibility,
                traversalBudget: AXTraversalBudget(maxDepth: 10, maxElementCount: 300)
            ),
            // Peekaboo only registers the snapshot (needed for element-id
            // clicks) when it writes the PNG to disk. We keep the bytes in
            // memory and delete the file straight away.
            output: DesktopObservationOutputOptions(
                path: Self.scratchDirectory.path + "/", saveSnapshot: true, includeImageData: true
            )
        ))
        for path in [result.files.rawScreenshotPath, result.files.annotatedScreenshotPath].compactMap({ $0 }) {
            try? FileManager.default.removeItem(atPath: path)
        }
        let metadata = result.capture.metadata
        let frame = result.target.bounds ?? metadata.windowInfo?.bounds ?? metadata.displayInfo?.bounds
        let scaled = Self.downscale(result.capture.imageData)
        // Screen-mode detection walks the frontmost app's tree, which is
        // ours when the user has just clicked the panel; those elements
        // are the transcript, not the user's work.
        let ownFrames = Self.ownWindowFrames()
        let elements = (result.elements?.elements.all ?? []).filter { element in
            !ownFrames.contains { $0.contains(element.bounds) }
        }.map { element in
            AgentElement(
                id: element.id,
                role: element.type.rawValue,
                label: element.label,
                value: element.value,
                frame: element.bounds,
                isEnabled: element.isEnabled
            )
        }
        let bundleID = metadata.applicationInfo?.bundleIdentifier
        if let bundleID, bundleID != Bundle.main.bundleIdentifier { lastForeignBundleID = bundleID }
        let observed = AgentObservation(
            appName: metadata.applicationInfo?.name ?? result.target.app?.name,
            bundleID: bundleID,
            windowTitle: metadata.windowInfo?.title ?? result.target.window?.title,
            windowFrame: frame,
            imageSize: scaled?.size,
            image: scaled?.data,
            imageMIMEType: "image/jpeg",
            elements: elements,
            snapshotID: result.files.publishedSnapshotID ?? result.elements?.snapshotId
        )
        latest = observed
        capturedFrame = frame
        return observed
    }

    /// A JPEG no wider than `maxImageEdge`, and its pixel size.
    private static func downscale(_ png: Data) -> (data: Data, size: CGSize)? {
        guard let source = NSBitmapImageRep(data: png) else { return nil }
        let width = CGFloat(source.pixelsWide), height = CGFloat(source.pixelsHigh)
        guard width > 0, height > 0 else { return nil }
        let scale = min(1, maxImageEdge / max(width, height))
        let target = CGSize(width: (width * scale).rounded(.down), height: (height * scale).rounded(.down))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: target))
        NSGraphicsContext.restoreGraphicsState()
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else { return nil }
        return (jpeg, target)
    }

    /// Screenshot pixels → screen points, through the captured frame.
    private func screenPoint(imageX: Double, imageY: Double) -> CGPoint? {
        guard let frame = capturedFrame, let size = latest?.imageSize, size.width > 0, size.height > 0 else { return nil }
        return CGPoint(
            x: frame.minX + imageX / size.width * frame.width,
            y: frame.minY + imageY / size.height * frame.height
        )
    }

    // MARK: - Actions

    private func clickType(_ call: AgentToolCall) -> ClickType {
        switch call.string("click_type") {
        case "double": return .double
        case "right": return .right
        default: return .single
        }
    }

    /// "return" and "cmd,shift,t" both arrive here. A lone special key goes
    /// through typeActions; anything with a modifier is a hotkey chord.
    private func press(_ keys: String) async throws {
        let parts = keys.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 1, let special = SpecialKey(rawValue: Self.specialKeyName(parts[0])) {
            _ = try await automation.typeActions([.key(special)], cadence: .fixed(milliseconds: 8), snapshotId: nil)
            return
        }
        if parts.count == 1, parts[0].count == 1 {
            _ = try await automation.typeActions([.text(parts[0])], cadence: .fixed(milliseconds: 8), snapshotId: nil)
            return
        }
        try await automation.hotkey(keys: parts.joined(separator: ","), holdDuration: 50)
    }

    private static func specialKeyName(_ name: String) -> String {
        switch name {
        case "enter", "return": return "return"
        case "esc", "escape": return "escape"
        case "backspace", "delete": return "delete"
        case "pageup", "page_up": return "pageup"
        case "pagedown", "page_down": return "pagedown"
        default: return name
        }
    }

    // MARK: - Risk

    private static let riskyWords = ["send", "pay", "purchase", "buy", "delete", "remove", "share", "log in", "login", "sign in", "accept", "agree", "submit", "confirm", "transfer", "empty trash"]

    /// A one-line question for the user when the step looks irreversible,
    /// judged from the element the model picked or the text it will type.
    private func riskDescription(for call: AgentToolCall, tool: AgentTool) -> String? {
        let subject: String?
        switch tool {
        case .click:
            subject = call.string("element_id").flatMap(element(for:)).map { [$0.label, $0.value].compactMap { $0 }.joined(separator: " ") }
        case .press:
            // Return on a form or in a chat can send; cmd-delete and cmd-backspace delete.
            let keys = call.string("keys")?.lowercased() ?? ""
            if keys.contains("delete") && keys.contains("cmd") { return "Press \(keys), which may delete something?" }
            return nil
        case .invokeMenu:
            subject = call.string("path")
        default:
            subject = nil
        }
        guard let subject = subject?.lowercased(), !subject.isEmpty else { return nil }
        guard let word = Self.riskyWords.first(where: subject.contains) else { return nil }
        return "\(describe(call))? It looks like it will \(word)."
    }

    // MARK: - Helpers

    private func element(for id: String) -> AgentElement? {
        latest?.elements.first { $0.id == id }
    }

    private func elementName(_ id: String?) -> String {
        guard let id else { return "an element" }
        guard let element = element(for: id) else { return id }
        if let label = element.label, !label.isEmpty { return "\"\(Self.clip(label))\"" }
        if let value = element.value, !value.isEmpty { return "the \(element.role) \"\(Self.clip(value))\"" }
        return "the \(element.role) \(id)"
    }

    private static func clip(_ text: String, max: Int = 48) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count <= max ? flat : String(flat.prefix(max)) + "…"
    }

    private static func message(for error: Error) -> String {
        error.localizedDescription
    }
}

import Foundation

/// The one tool list. Each transport renders it in its host's shape; the
/// names and parameters never differ, so the executor has one switch.
public enum AgentTool: String, CaseIterable, Sendable {
    case observe
    case click
    case clickAt = "click_at"
    case type
    case press
    case scroll
    case invokeMenu = "invoke_menu"
    case openApp = "open_app"
    case wait
    case webSearch = "web_search"
    case fetchPage = "fetch_page"
    case answer
    case done

    /// The tools that need a web key. Left out of the list when there is none.
    public static let webTools: [AgentTool] = [.webSearch, .fetchPage]

    /// The list for one session: everything, or everything but the web.
    public static func available(web: Bool) -> [AgentTool] {
        allCases.filter { web || !webTools.contains($0) }
    }

    public var description: String {
        switch self {
        case .observe:
            return "Look at the screen again: returns the frontmost app, its window, a screenshot and the interactive elements with ids. Call this after an action changed the screen and before deciding the next step."
        case .wait:
            return "Wait up to 5 seconds for the screen to change (a page loading, an app opening), then look again. Use it when the last observation shows something still in progress."
        case .webSearch:
            return "Search the web. Returns titles, URLs and snippets. Use it to look up facts, names and current information the screen does not give you, before asking the user for more."
        case .fetchPage:
            return "Read a web page by URL as text. Use it after web_search when a snippet is not enough."
        case .click:
            return "Click an element from the latest observation by its id."
        case .clickAt:
            return "Click at a point in the latest screenshot, in its pixel coordinates (origin top-left; the screenshot size is given in the observation). Use only when no element id matches."
        case .type:
            return "Type text into the focused field, or into the element with element_id. Set clear to true to replace the field's current content."
        case .press:
            return "Press a key or shortcut. Examples: \"return\", \"escape\", \"tab\", \"cmd,s\", \"cmd,shift,t\", \"down\". Modifier names: cmd, shift, alt, ctrl."
        case .scroll:
            return "Scroll in a direction, in the element with element_id or under the pointer."
        case .invokeMenu:
            return "Choose a menu bar item in the frontmost app by its path, for example \"File > Save\" or \"Edit > Find > Find…\"."
        case .openApp:
            return "Open or bring to front an app by name, for example \"Safari\" or \"Notes\"."
        case .answer:
            return "Reply to the user. Use it for questions and explanations, and to tell the user when something could not be done. Ends the turn."
        case .done:
            return "The task is complete. Give a one-line summary of what was done. Ends the turn."
        }
    }

    /// JSON Schema for the arguments.
    public var parameters: [String: Any] {
        func schema(_ properties: [String: [String: Any]], required: [String]) -> [String: Any] {
            ["type": "object", "properties": properties, "required": required]
        }
        let elementID: [String: Any] = ["type": "string", "description": "Element id from the latest observation."]
        let clickType: [String: Any] = ["type": "string", "enum": ["single", "double", "right"]]
        switch self {
        case .observe:
            return schema([:], required: [])
        case .click:
            return schema(["element_id": elementID, "click_type": clickType], required: ["element_id"])
        case .clickAt:
            return schema(["x": ["type": "number"], "y": ["type": "number"], "click_type": clickType], required: ["x", "y"])
        case .type:
            return schema(["text": ["type": "string"], "element_id": elementID, "clear": ["type": "boolean"]], required: ["text"])
        case .press:
            return schema(["keys": ["type": "string"]], required: ["keys"])
        case .scroll:
            return schema([
                "direction": ["type": "string", "enum": ["up", "down", "left", "right"]],
                "amount": ["type": "integer", "description": "Lines to scroll, default 5."],
                "element_id": elementID,
            ], required: ["direction"])
        case .invokeMenu:
            return schema(["path": ["type": "string"]], required: ["path"])
        case .openApp:
            return schema(["name": ["type": "string"]], required: ["name"])
        case .wait:
            return schema(["seconds": ["type": "number", "description": "1 to 5, default 2."]], required: [])
        case .webSearch:
            return schema([
                "query": ["type": "string"],
                "recent": ["type": "boolean", "description": "True for news or anything that changes by the hour."],
            ], required: ["query"])
        case .fetchPage:
            return schema(["url": ["type": "string"]], required: ["url"])
        case .answer:
            return schema(["text": ["type": "string"]], required: ["text"])
        case .done:
            return schema(["summary": ["type": "string"]], required: ["summary"])
        }
    }

    /// True for calls that end the turn without touching the system.
    public var endsTurn: Bool { self == .answer || self == .done }

    /// Steps after which the screen may differ, so a fresh look follows.
    public var changesState: Bool { !(self == .observe || endsTurn || Self.webTools.contains(self)) }
}

/// One interactive element the observer found, with the id the model uses.
public struct AgentElement: Equatable, Sendable {
    public var id: String
    public var role: String
    public var label: String?
    public var value: String?
    /// Global screen points, origin top-left.
    public var frame: CGRect
    public var isEnabled: Bool

    public init(id: String, role: String, label: String?, value: String?, frame: CGRect, isEnabled: Bool = true) {
        self.id = id
        self.role = role
        self.label = label
        self.value = value
        self.frame = frame
        self.isEnabled = isEnabled
    }
}

/// What the agent saw: the pixels and a bounded element list.
public struct AgentObservation: Equatable, Sendable {
    public var appName: String?
    public var bundleID: String?
    public var windowTitle: String?
    public var windowFrame: CGRect?
    /// Pixel size of `image`. `click_at` coordinates are in this space.
    public var imageSize: CGSize?
    public var image: Data?
    public var imageMIMEType: String
    public var elements: [AgentElement]
    /// Opaque handle the executor needs to act on these element ids.
    public var snapshotID: String?
    /// Why there is no image or no elements, when a permission is missing.
    public var limitation: String?

    public init(appName: String? = nil, bundleID: String? = nil, windowTitle: String? = nil, windowFrame: CGRect? = nil,
                imageSize: CGSize? = nil, image: Data? = nil, imageMIMEType: String = "image/png",
                elements: [AgentElement] = [], snapshotID: String? = nil, limitation: String? = nil) {
        self.appName = appName
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.windowFrame = windowFrame
        self.imageSize = imageSize
        self.image = image
        self.imageMIMEType = imageMIMEType
        self.elements = elements
        self.snapshotID = snapshotID
        self.limitation = limitation
    }

    /// The one line the transcript shows.
    public var summary: String {
        var line = "Looking at \(appName ?? "the screen")"
        if let windowTitle, !windowTitle.isEmpty { line += ", \"\(windowTitle)\"" }
        if !elements.isEmpty { line += ", \(elements.count) elements" }
        if let limitation { line += " (\(limitation))" }
        return line
    }

    /// The text the model reads. Compact, one element per line, bounded by
    /// the observer's traversal budget.
    public var modelText: String {
        var lines: [String] = []
        lines.append("Frontmost app: \(appName ?? "unknown")\(bundleID.map { " (\($0))" } ?? "")")
        if let windowTitle { lines.append("Window: \"\(windowTitle)\"") }
        if let windowFrame { lines.append("Window frame: \(Self.rect(windowFrame))") }
        if let imageSize { lines.append("Screenshot: \(Int(imageSize.width))x\(Int(imageSize.height)) pixels, covering the window frame; click_at takes screenshot coordinates") }
        if let limitation { lines.append("Limitation: \(limitation)") }
        if elements.isEmpty {
            lines.append("Elements: none found")
        } else {
            lines.append("Elements (id role \"label\" [value] @x,y wxh):")
            for element in elements {
                var line = "\(element.id) \(element.role)"
                if let label = element.label, !label.isEmpty { line += " \"\(Self.clip(label))\"" }
                if let value = element.value, !value.isEmpty { line += " [\(Self.clip(value))]" }
                line += " @\(Self.rect(element.frame))"
                if !element.isEnabled { line += " disabled" }
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func rect(_ rect: CGRect) -> String {
        "\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height))"
    }

    private static func clip(_ text: String, max: Int = 80) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count <= max ? flat : String(flat.prefix(max)) + "…"
    }
}

/// How an executed tool call ended, with what the model should read.
public enum ActionOutcome: Equatable, Sendable {
    case done(String)
    case failed(String)
    /// The step changes something the user must approve first.
    case needsConfirmation(String)
}

/// The system side of the loop: what the app can do to the Mac.
@MainActor
public protocol ActionExecutor: AnyObject {
    /// Look at the frontmost window.
    func observe() async -> AgentObservation
    /// One line for the transcript, resolved against the latest
    /// observation so an element id becomes its label.
    func describe(_ call: AgentToolCall) -> String
    /// Perform one call. Never called for `answer`, `done` or `observe`.
    /// Returns `needsConfirmation` for a risky step unless `approved`.
    func perform(_ call: AgentToolCall, approved: Bool) async -> ActionOutcome
}

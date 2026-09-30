#if os(macOS)
import ApplicationServices
import Foundation

public struct FieldSnapshot: @unchecked Sendable {
    public let element: AXUIElement
    public let pid: pid_t
    public let bundleID: String?

    public init(element: AXUIElement, pid: pid_t, bundleID: String?) {
        self.element = element
        self.pid = pid
        self.bundleID = bundleID
    }

    public func currentValue() -> String? {
        AXInserter.fieldText(of: element)
    }

    /// `currentValue()` for a caller that holds the user's keystroke while it
    /// reads: a hung app costs 0.2 s, not the 6 s AX default that would get
    /// the event tap disabled.
    func quickValue() -> String? {
        AXUIElementSetMessagingTimeout(element, 0.2)
        defer { AXUIElementSetMessagingTimeout(element, 0) }
        return currentValue()
    }
}

/// The fields `EditLearner` tracks, readable from the event-tap thread.
final class WatchedFields: @unchecked Sendable {
    private let lock = NSLock()
    private var fields: [FieldKey: FieldSnapshot] = [:]

    func set(_ key: FieldKey, _ snapshot: FieldSnapshot?) {
        lock.lock()
        fields[key] = snapshot
        lock.unlock()
    }

    func fields(pid: pid_t) -> [(FieldKey, FieldSnapshot)] {
        lock.lock()
        defer { lock.unlock() }
        return fields.filter { $0.key.pid == pid }.map { ($0.key, $0.value) }
    }
}

struct FieldKey: Hashable, @unchecked Sendable {
    let pid: pid_t
    private let element: AXUIElement

    init(_ snapshot: FieldSnapshot) {
        pid = snapshot.pid
        element = snapshot.element
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pid == rhs.pid && CFEqual(lhs.element, rhs.element)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
        hasher.combine(CFHash(element))
    }
}
#endif

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
}

struct FieldKey: Hashable {
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

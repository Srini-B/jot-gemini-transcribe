// Copyright 2026 Google LLC
// Licensed under the Apache License, Version 2.0.

#if os(macOS)
import ApplicationServices
import Foundation

public enum SelectedTextCapture {
    public struct Snapshot: Equatable, Sendable {
        public let text: String?
        public let isSettable: Bool
    }

    public static func capture() -> Snapshot {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 1.5)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return Snapshot(text: nil, isSettable: false)
        }
        let element = unsafeDowncast(focusedRef as AnyObject, to: AXUIElement.self)
        var selectedRef: CFTypeRef?
        let text = AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &selectedRef
        ) == .success ? selectedRef as? String : nil
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable)
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Snapshot(text: trimmed?.isEmpty == false ? text : nil, isSettable: settable.boolValue)
    }
}
#endif

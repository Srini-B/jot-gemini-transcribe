import AppKit
import SwiftUI

/// The grip on the pill's leading edge. Dragging it slides the whole panel
/// along the bottom of the screen; letting go snaps to the nearest of the five
/// anchors (`SettingsStore.pillAnchors`) and remembers it.
///
/// The gesture only reports "moving" and "released". `PillHUDController` owns
/// the panel and reads the pointer from `NSEvent.mouseLocation`, because the
/// gesture's own translation is measured in a coordinate space that moves
/// with the window being dragged.
///
/// SwiftUI rather than an NSView subclass: inside the Liquid Glass capsule an
/// `NSViewRepresentable` never received `mouseDown` (verified on macOS 26 with
/// synthetic events), while SwiftUI controls in the same pill do.
struct PillDragHandle: View {
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 3) {
                    Circle().frame(width: 3, height: 3)
                    Circle().frame(width: 3, height: 3)
                }
            }
        }
        .foregroundStyle(VoiceIQUI.Colors.onSurfaceVariant.opacity(0.7))
        .frame(width: 14, height: 20)
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { _ in
                    NotificationCenter.default.post(name: .pillDragMoved, object: nil)
                }
                .onEnded { _ in
                    NotificationCenter.default.post(name: .pillDragEnded, object: nil)
                }
        )
        .accessibilityLabel("Move pill")
    }
}

extension Notification.Name {
    /// Pointer moved while holding the grip. Read `NSEvent.mouseLocation`.
    static let pillDragMoved = Notification.Name("io.blue.voiceiq.pill.dragMoved")
    /// Grip released. Snap to the nearest anchor.
    static let pillDragEnded = Notification.Name("io.blue.voiceiq.pill.dragEnded")
}

import SwiftUI
import VoiceIQCore

/// A downloaded update, with a restart to apply it now.
struct UpdateReadyContent: View {
    let version: String

    var body: some View {
        HStack(spacing: VoiceIQUI.Spacing.s) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(VoiceIQUI.Colors.primary)
            Text("VoiceiQ \(version) is ready")
                .font(VoiceIQUI.TypeScale.label())
                .foregroundStyle(VoiceIQUI.Colors.onSurface)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Button("Restart") {
                NotificationCenter.default.post(name: .pillUpdateRestartTapped, object: nil)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(VoiceIQUI.Colors.primary)
            .accessibilityLabel("Restart VoiceiQ to install the update")
            Button {
                NotificationCenter.default.post(name: .pillUpdateDismissed, object: nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VoiceIQUI.Colors.onSurfaceVariant)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Later")
        }
    }
}

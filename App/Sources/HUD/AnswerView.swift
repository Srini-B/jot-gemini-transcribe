// Copyright 2026 Google LLC
// Licensed under the Apache License, Version 2.0.

import AppKit
import SwiftUI

struct AnswerView: View {
    let answer: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Answer")
                    .font(.headline)
                Spacer()
                Button {
                    copy()
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                Button {
                    NotificationCenter.default.post(name: .pillAnswerDismissed, object: nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close answer")
            }

            ScrollView {
                renderedAnswer
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VoiceIQUI.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 4)
    }

    @ViewBuilder
    private var renderedAnswer: some View {
        if containsMarkdown,
           let attributed = try? AttributedString(
               markdown: answer,
               options: .init(interpretedSyntax: .full)
           ) {
            Text(attributed)
        } else {
            Text(answer)
        }
    }

    private var containsMarkdown: Bool {
        answer.range(of: #"(?m)(^#{1,6}\s|^[-*+]\s|^\d+\.\s|```|\[[^\]]+\]\([^)]+\)|\*\*[^*]+\*\*)"#,
                     options: .regularExpression) != nil
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer, forType: .string)
        copied = true
    }
}

extension Notification.Name {
    static let pillAnswerDismissed = Notification.Name("io.blue.voiceiq.pill.answer.dismissed")
}

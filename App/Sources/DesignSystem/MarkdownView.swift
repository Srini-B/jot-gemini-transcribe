import AppKit
import SwiftUI

/// Lays out a Markdown answer block by block: paragraphs, headings, lists
/// with markers, code in a box, quotes with a bar, and tables as a grid.
/// Shared by the agent panel and the Ask Anything answer.
struct MarkdownView: View {
    private let blocks: [MarkdownBlock]
    private let style: MarkdownStyle
    private let color: Color
    private var size: CGFloat { style.size }

    init(_ markdown: String, size: CGFloat = 14, color: Color = VoiceIQUI.Colors.onSurface) {
        blocks = MarkdownBlock.parse(markdown)
        style = MarkdownStyle(size: size)
        self.color = color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: size * 0.6) {
            ForEach(blocks) { block in
                view(block)
            }
        }
        .foregroundStyle(color)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(_, let text):
            inline(text)
        case .heading(_, let level, let text):
            inline(text, font: GTFont.flex(headingSize(level), weight: 600))
                .padding(.top, size * 0.3)
        case .list(_, let items):
            list(items)
        case .code(_, let code):
            Text(code)
                .font(style.code)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(VoiceIQUI.Colors.surfaceContainer)
                .clipShape(RoundedRectangle(cornerRadius: VoiceIQUI.Radius.small, style: .continuous))
        case .quote(_, let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(VoiceIQUI.Colors.outlineVariant)
                    .frame(width: 3)
                inline(text)
                    .foregroundStyle(VoiceIQUI.Colors.onSurfaceVariant)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .table(_, let table):
            MarkdownTableView(table: table, style: style)
        case .rule:
            Divider()
        }
    }

    // MARK: - Inline

    private func inline(_ text: AttributedString, font: Font? = nil) -> some View {
        Text(style.styled(text, base: font ?? style.body))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return size * 1.3
        case 2: return size * 1.15
        default: return size
        }
    }

    // MARK: - Lists

    private func list(_ items: [MarkdownBlock.ListItem]) -> some View {
        VStack(alignment: .leading, spacing: size * 0.3) {
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.ordered ? "\(item.ordinal)." : "•")
                        .font(style.body)
                        .frame(minWidth: 16, alignment: .trailing)
                    inline(item.text)
                }
                .padding(.leading, CGFloat(item.depth - 1) * 20)
            }
        }
    }
}

/// Fonts for one answer. Bold and code come through as
/// `inlinePresentationIntent`; SwiftUI's own mapping would ask the variable
/// font for a bold trait it does not expose, so the faces are set explicitly.
struct MarkdownStyle {
    let size: CGFloat
    var body: Font { GTFont.flex(size, weight: 400) }
    var bold: Font { GTFont.flex(size, weight: 600) }
    var code: Font { GTFont.sansCode(size - 1, weight: 400) }
    var nsBody: NSFont { GTFont.nsFlex(size, weight: 400) }
    var nsBold: NSFont { GTFont.nsFlex(size, weight: 600) }
    var nsCode: NSFont { GTFont.nsSansCode(size - 1, weight: 400) }

    func styled(_ text: AttributedString, base: Font) -> AttributedString {
        var out = text
        for run in out.runs {
            let intent = run.inlinePresentationIntent ?? []
            var font = base
            if intent.contains(.stronglyEmphasized) { font = bold }
            if intent.contains(.code) { font = code }
            if intent.contains(.emphasized) { font = font.italic() }
            out[run.range].font = font
            out[run.range].inlinePresentationIntent = nil
            if intent.contains(.strikethrough) { out[run.range].strikethroughStyle = .single }
        }
        return out
    }

    /// The same text as AppKit measures it, for column sizing.
    func measured(_ text: AttributedString, base: NSFont) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for run in text.runs {
            let intent = run.inlinePresentationIntent ?? []
            var font = base
            if intent.contains(.stronglyEmphasized) { font = nsBold }
            if intent.contains(.code) { font = nsCode }
            out.append(NSAttributedString(string: String(text[run.range].characters), attributes: [.font: font]))
        }
        return out
    }
}

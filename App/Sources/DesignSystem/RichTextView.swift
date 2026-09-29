import AppKit
import SwiftUI

/// Read-only, selectable, scrolling text backed by NSTextView.
///
/// SwiftUI's `Text(...).textSelection(.enabled)` builds an AppKit selection
/// overlay per view and re-measures every one on scroll, which is what froze the
/// meeting transcript at twenty minutes of text. One NSTextView holds any length
/// of text, wraps to the width it is given, and selects across paragraphs.
struct RichTextView: NSViewRepresentable {
    let text: NSAttributedString
    var inset = NSSize(width: 0, height: 0)

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let view = scroll.documentView as! NSTextView
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = inset
        view.isAutomaticLinkDetectionEnabled = false
        view.linkTextAttributes = [
            .foregroundColor: NSColor(hex: 0x0B57D0),
            .cursor: NSCursor.pointingHand,
        ]
        view.textStorage?.setAttributedString(text)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView,
              view.textStorage?.isEqual(to: text) == false else { return }
        view.textStorage?.setAttributedString(text)
        view.scroll(.zero)
    }
}

/// Markdown → NSAttributedString with the block structure laid out: paragraphs
/// separated by a blank line, list items on their own lines with a bullet or
/// number, headings bold, code in the code face, links clickable.
///
/// `AttributedString(markdown:)` parses all of that but keeps the blocks as
/// `presentationIntent` attributes and no line breaks, which is why a Text
/// built from it ran "…$84,413.Sources:…" together on one line.
enum MarkdownRenderer {
    static func render(_ markdown: String, size: CGFloat = 14, color: NSColor = .labelColor) -> NSAttributedString {
        let body = GTFont.nsFlex(size, weight: 400)
        let bold = GTFont.nsFlex(size, weight: 600)
        let code = GTFont.nsSansCode(size - 1, weight: 400)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = size * 0.6

        guard let parsed = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .full)) else {
            return NSAttributedString(string: markdown, attributes: [.font: body, .foregroundColor: color, .paragraphStyle: paragraph])
        }

        let out = NSMutableAttributedString()
        var lastBlock: Int?
        for run in parsed.runs {
            let block = run.presentationIntent
            let blockID = block?.components.first?.identity
            if let blockID, blockID != lastBlock {
                if out.length > 0 { out.append(NSAttributedString(string: "\n")) }
                if let prefix = listPrefix(block) {
                    out.append(NSAttributedString(string: prefix, attributes: [.font: body, .foregroundColor: color, .paragraphStyle: paragraph]))
                }
            }
            lastBlock = blockID

            var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: color, .paragraphStyle: paragraph]
            var font = body
            if let inline = run.inlinePresentationIntent {
                if inline.contains(.stronglyEmphasized) { font = bold }
                if inline.contains(.code) { font = code }
            }
            if let block, block.components.contains(where: { if case .header = $0.kind { return true }; return false }) {
                font = bold
            }
            if let block, block.components.contains(where: { if case .codeBlock = $0.kind { return true }; return false }) {
                font = code
            }
            attributes[.font] = font
            if let link = run.link { attributes[.link] = link }
            out.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return out
    }

    private static func listPrefix(_ intent: PresentationIntent?) -> String? {
        guard let intent else { return nil }
        var ordinal: Int?
        var ordered = false
        for component in intent.components {
            switch component.kind {
            case .listItem(let n): ordinal = n
            case .orderedList: ordered = true
            default: break
            }
        }
        guard let ordinal else { return nil }
        return ordered ? "\(ordinal). " : "•  "
    }
}

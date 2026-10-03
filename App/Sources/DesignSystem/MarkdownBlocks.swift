import Foundation

/// The block structure of a Markdown answer, ready for a view to lay out.
///
/// `AttributedString(markdown:)` parses GFM fully but hands every block back
/// as a `presentationIntent` attribute on inline runs, with no line breaks.
/// Flattening that to one string put each table cell on its own line. This
/// groups the runs back into blocks so tables become grids, lists get their
/// markers, and code gets its box.
enum MarkdownBlock: Identifiable {
    struct ListItem: Identifiable {
        let id: Int
        let ordered: Bool
        let ordinal: Int
        /// 1 for a top-level item, 2 for an item nested one level in.
        let depth: Int
        /// Text of an item that resumes after its nested list. It keeps the
        /// item's indent but shows no marker.
        let continuation: Bool
        let text: AttributedString
    }

    struct Table {
        let alignments: [PresentationIntent.TableColumn.Alignment]
        let header: [AttributedString]
        let rows: [[AttributedString]]
        var columnCount: Int { alignments.count }
    }

    case paragraph(id: Int, AttributedString)
    case heading(id: Int, level: Int, AttributedString)
    case list(id: Int, items: [ListItem])
    case code(id: Int, String)
    case quote(id: Int, AttributedString)
    case table(id: Int, Table)
    case rule(id: Int)

    var id: Int {
        switch self {
        case .paragraph(let id, _), .heading(let id, _, _), .list(let id, _),
             .code(let id, _), .quote(let id, _), .table(let id, _), .rule(let id):
            return id
        }
    }

    /// Inline text keeps `inlinePresentationIntent` (bold, code, strikethrough)
    /// and `link`; the view maps those to fonts. Block intents are stripped.
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        guard let parsed = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .full)) else {
            return [.paragraph(id: 0, AttributedString(markdown))]
        }
        var blocks: [MarkdownBlock] = []
        var group: [AttributedString.Runs.Run] = []
        var groupID: Int?

        func flush() {
            guard let id = groupID, !group.isEmpty else { return }
            if let block = build(id: id, runs: group, in: parsed) { blocks.append(block) }
            group = []
        }

        for run in parsed.runs {
            // Components are ordered innermost first; the last one is the block
            // the run belongs to at the top level.
            let outer = run.presentationIntent?.components.last
            let id = outer?.identity ?? -1
            if id != groupID {
                flush()
                groupID = id
            }
            group.append(run)
        }
        flush()
        return blocks
    }

    private static func build(id: Int, runs: [AttributedString.Runs.Run], in source: AttributedString) -> MarkdownBlock? {
        let outer = runs[0].presentationIntent?.components.last
        switch outer?.kind {
        case .none, .paragraph:
            return .paragraph(id: id, paragraphs(runs, in: source))
        case .header(let level):
            return .heading(id: id, level: level, paragraphs(runs, in: source))
        case .codeBlock:
            var text = runs.map { String(source[$0.range].characters) }.joined()
            while text.hasSuffix("\n") { text.removeLast() }
            return .code(id: id, text)
        case .blockQuote:
            return .quote(id: id, paragraphs(runs, in: source))
        case .thematicBreak:
            return .rule(id: id)
        case .orderedList, .unorderedList:
            return .list(id: id, items: listItems(runs, in: source))
        case .table(let columns):
            return .table(id: id, table(columns: columns, runs: runs, in: source))
        default:
            return .paragraph(id: id, paragraphs(runs, in: source))
        }
    }

    /// Inline text of the runs, with a line break between distinct paragraphs.
    private static func paragraphs(_ runs: [AttributedString.Runs.Run], in source: AttributedString) -> AttributedString {
        var out = AttributedString()
        var lastParagraph: Int?
        for run in runs {
            let paragraph = run.presentationIntent?.components.first { if case .paragraph = $0.kind { return true }; return false }?.identity
            if let lastParagraph, paragraph != lastParagraph { out.append(AttributedString("\n")) }
            lastParagraph = paragraph
            out.append(inline(run, in: source))
        }
        return out
    }

    private static func inline(_ run: AttributedString.Runs.Run, in source: AttributedString) -> AttributedString {
        var piece = AttributedString(source[run.range])
        piece.presentationIntent = nil
        return piece
    }

    /// Each run belongs to its innermost list item. Nested lists may mix
    /// numbers and bullets, so the list just outside that item decides the
    /// marker. Runs stay in source order: when an item's text resumes after
    /// its nested list, that text becomes a separate continuation entry
    /// instead of being pulled up in front of the nested items.
    private static func listItems(_ runs: [AttributedString.Runs.Run], in source: AttributedString) -> [ListItem] {
        struct Group {
            let identity: Int, ordered: Bool, ordinal: Int, depth: Int
            var runs: [AttributedString.Runs.Run]
        }
        var groups: [Group] = []
        for run in runs {
            let components = run.presentationIntent?.components ?? []
            let itemIndices = components.indices.filter { if case .listItem = components[$0].kind { return true }; return false }
            guard let index = itemIndices.first, case .listItem(let ordinal) = components[index].kind else { continue }
            let identity = components[index].identity
            if groups.last?.identity == identity {
                groups[groups.count - 1].runs.append(run)
                continue
            }
            var ordered = false
            if components.indices.contains(index + 1), case .orderedList = components[index + 1].kind { ordered = true }
            groups.append(Group(identity: identity, ordered: ordered, ordinal: ordinal, depth: itemIndices.count, runs: [run]))
        }
        var seen: Set<Int> = []
        return groups.enumerated().map { offset, group in
            ListItem(id: offset, ordered: group.ordered, ordinal: group.ordinal, depth: group.depth,
                     continuation: !seen.insert(group.identity).inserted,
                     text: paragraphs(group.runs, in: source))
        }
    }

    private static func table(columns: [PresentationIntent.TableColumn], runs: [AttributedString.Runs.Run], in source: AttributedString) -> Table {
        var header = Array(repeating: AttributedString(), count: columns.count)
        var rows: [[AttributedString]] = []
        var rowIndexByID: [Int: Int] = [:]
        for run in runs {
            let components = run.presentationIntent?.components ?? []
            var column: Int?
            var row: (id: Int, isHeader: Bool)?
            for component in components {
                switch component.kind {
                case .tableCell(let index): column = index
                case .tableHeaderRow: row = (component.identity, true)
                case .tableRow: row = (component.identity, false)
                default: break
                }
            }
            guard let column, let row, column < columns.count else { continue }
            let piece = inline(run, in: source)
            if row.isHeader {
                header[column].append(piece)
                continue
            }
            let rowIndex: Int
            if let known = rowIndexByID[row.id] {
                rowIndex = known
            } else {
                rowIndex = rows.count
                rowIndexByID[row.id] = rowIndex
                rows.append(Array(repeating: AttributedString(), count: columns.count))
            }
            rows[rowIndex][column].append(piece)
        }
        return Table(alignments: columns.map(\.alignment), header: header, rows: rows)
    }
}

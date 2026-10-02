import SwiftUI

/// One row of a side-by-side diff. Hunk/meta lines span both columns (`full`).
struct SplitDiffRow: Identifiable, Sendable {
    let id: Int
    var left: DiffLine?
    var right: DiffLine?
    var full: DiffLine?
}

enum SplitDiffBuilder {
    /// Pairs each run of removed lines with the following run of added lines.
    static func rows(_ lines: [DiffLine]) -> [SplitDiffRow] {
        var rows: [SplitDiffRow] = []
        var removed: [DiffLine] = [], added: [DiffLine] = []

        func flush() {
            for k in 0..<max(removed.count, added.count) {
                let l = k < removed.count ? removed[k] : nil
                let r = k < added.count ? added[k] : nil
                rows.append(SplitDiffRow(id: (l ?? r)!.id, left: l, right: r))
            }
            removed = []; added = []
        }

        for line in lines {
            switch line.kind {
            case .removed:
                if !added.isEmpty { flush() }   // a new removal after additions starts a new block
                removed.append(line)
            case .added:
                added.append(line)
            case .context:
                flush()
                rows.append(SplitDiffRow(id: line.id, left: line, right: line))
            case .hunk, .meta:
                flush()
                rows.append(SplitDiffRow(id: line.id, full: line))
            }
        }
        flush()
        return rows
    }
}

/// Syntax highlighting for diff lines, keyed by `DiffLine.id`.
enum DiffHighlighter {
    /// Old and new sides are tokenized separately so multi-line comments stay correct on each side.
    static func highlight(_ lines: [DiffLine], path: String) -> [Int: AttributedString] {
        guard let language = SyntaxLanguage.forPath(path) else { return [:] }
        let highlighter = SyntaxHighlighter(language: language)
        var result: [Int: AttributedString] = [:]

        for side in [DiffLineKind.removed, .added] {
            var inBlock = false
            for line in lines {
                switch line.kind {
                case .hunk: inBlock = false   // state before a hunk is unknown
                case side, .context:
                    let tokens = highlighter.tokenize(line.text, inBlockComment: &inBlock)
                    // Context lines: new-side pass runs last and wins.
                    result[line.id] = SyntaxHighlighter.attributed(tokens)
                default: continue
                }
            }
        }
        return result
    }
}

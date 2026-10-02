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

/// Builds the styled text of every diff line: syntax colors + GitHub-style changed-word background.
enum DiffRenderer {
    static func render(_ lines: [DiffLine], rows: [SplitDiffRow], path: String, syntax: Bool) -> [Int: AttributedString] {
        var result = syntax ? highlight(lines, path: path) : [:]
        for line in lines where result[line.id] == nil && line.kind != .hunk && line.kind != .meta {
            result[line.id] = AttributedString(line.text)
        }
        // Paired removed/added lines get their differing middle section emphasized.
        for row in rows {
            guard let old = row.left, let new = row.right, old.kind == .removed, new.kind == .added,
                  let (oldRange, newRange) = IntralineDiff.changedRanges(old.text, new.text) else { continue }
            emphasize(&result[old.id], oldRange, Theme.removedWord)
            emphasize(&result[new.id], newRange, Theme.addedWord)
        }
        return result
    }

    private static func emphasize(_ text: inout AttributedString?, _ range: Range<Int>, _ color: Color) {
        guard var attr = text, !range.isEmpty, range.upperBound <= attr.characters.count else { return }
        let start = attr.characters.index(attr.startIndex, offsetBy: range.lowerBound)
        let end = attr.characters.index(attr.startIndex, offsetBy: range.upperBound)
        attr[start..<end].backgroundColor = color
        text = attr
    }

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

/// Common-prefix / common-suffix word diff (what GitHub Desktop shows for edited lines).
enum IntralineDiff {
    /// Character ranges that differ in `old` and `new`; nil when lines share nothing or are identical.
    static func changedRanges(_ old: String, _ new: String) -> (Range<Int>, Range<Int>)? {
        let a = Array(old), b = Array(new)
        guard a != b, a.count <= 2_000, b.count <= 2_000 else { return nil }
        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < a.count - prefix, suffix < b.count - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
        guard prefix + suffix > 0 else { return nil }   // completely different line: tint whole line only
        // Emphasis only helps when the edit is small; a mostly-rewritten line reads better without it.
        let changedA = a.count - suffix - prefix, changedB = b.count - suffix - prefix
        guard Double(max(changedA, changedB)) <= 0.6 * Double(max(a.count, b.count)) else { return nil }
        return (prefix..<(a.count - suffix), prefix..<(b.count - suffix))
    }
}

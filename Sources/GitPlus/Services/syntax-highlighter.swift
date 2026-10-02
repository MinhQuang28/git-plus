import SwiftUI

enum SyntaxTokenKind: Sendable, Equatable { case plain, keyword, string, comment, number, type }

struct SyntaxToken: Sendable, Equatable {
    let text: String
    let kind: SyntaxTokenKind
}

/// Line-based tokenizer. `inBlockComment` carries `/* … */` state across consecutive lines.
struct SyntaxHighlighter: Sendable {
    let language: SyntaxLanguage
    /// Lines longer than this are left plain to keep rendering fast.
    var maxLineLength = 1_000

    func tokenize(_ line: String, inBlockComment: inout Bool) -> [SyntaxToken] {
        guard line.count <= maxLineLength else { return [SyntaxToken(text: line, kind: .plain)] }
        if language.hashHeadings, !inBlockComment, line.hasPrefix("#") { return [SyntaxToken(text: line, kind: .keyword)] }
        let chars = Array(line)
        var tokens: [SyntaxToken] = []
        var plain = ""
        var i = 0

        func flushPlain() {
            if !plain.isEmpty { tokens.append(SyntaxToken(text: plain, kind: .plain)); plain = "" }
        }
        func emit(_ from: Int, _ to: Int, _ kind: SyntaxTokenKind) {
            flushPlain()
            tokens.append(SyntaxToken(text: String(chars[from..<to]), kind: kind))
        }
        func matches(_ s: String, at index: Int) -> Bool {
            let p = Array(s)
            return index + p.count <= chars.count && Array(chars[index..<index + p.count]) == p
        }
        /// Index just past the block-comment end, or `chars.count` if it continues.
        func blockEnd(from index: Int, end: String) -> Int {
            var j = index
            while j < chars.count {
                if matches(end, at: j) { inBlockComment = false; return j + end.count }
                j += 1
            }
            inBlockComment = true
            return chars.count
        }

        if inBlockComment, let block = language.blockComment {
            let end = blockEnd(from: 0, end: block.end)
            emit(0, end, .comment)
            i = end
        }

        while i < chars.count {
            let c = chars[i]
            if language.lineComments.contains(where: { matches($0, at: i) }) {
                emit(i, chars.count, .comment)
                break
            }
            if let block = language.blockComment, matches(block.start, at: i) {
                let end = blockEnd(from: i + block.start.count, end: block.end)
                emit(i, end, .comment)
                i = end
                continue
            }
            if language.stringDelimiters.contains(c) {
                var j = i + 1
                while j < chars.count, chars[j] != c { j += chars[j] == "\\" ? 2 : 1 }
                let end = min(j + 1, chars.count)
                emit(i, end, .string)
                i = end
                continue
            }
            if c.isNumber, i == 0 || !isIdentifier(chars[i - 1]) {
                var j = i
                while j < chars.count, chars[j].isHexDigit || chars[j] == "." || chars[j] == "_" || chars[j] == "x" { j += 1 }
                emit(i, j, .number)
                i = j
                continue
            }
            if isIdentifier(c) {
                var j = i
                while j < chars.count, isIdentifier(chars[j]) { j += 1 }
                let word = String(chars[i..<j])
                if language.keywords.contains(word) {
                    emit(i, j, .keyword)
                } else if language.capitalizedAreTypes, c.isUppercase {
                    emit(i, j, .type)
                } else {
                    plain += word
                }
                i = j
                continue
            }
            plain.append(c)
            i += 1
        }
        flushPlain()
        return tokens
    }

    private func isIdentifier(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" || c == "@" || c == "$" }

    static func attributed(_ tokens: [SyntaxToken]) -> AttributedString {
        tokens.reduce(into: AttributedString()) { result, token in
            var part = AttributedString(token.text)
            if let color = color(token.kind) { part.foregroundColor = color }
            result += part
        }
    }

    private static func color(_ kind: SyntaxTokenKind) -> Color? {
        switch kind {
        case .plain: nil
        case .keyword: Theme.dynamic(light: NSColor(srgbRed: 0.81, green: 0.13, blue: 0.18, alpha: 1), dark: NSColor(srgbRed: 1, green: 0.48, blue: 0.45, alpha: 1))
        case .string: Theme.dynamic(light: NSColor(srgbRed: 0.04, green: 0.19, blue: 0.41, alpha: 1), dark: NSColor(srgbRed: 0.65, green: 0.84, blue: 1, alpha: 1))
        case .comment: .gray
        case .number: Theme.dynamic(light: NSColor(srgbRed: 0.02, green: 0.31, blue: 0.68, alpha: 1), dark: NSColor(srgbRed: 0.47, green: 0.75, blue: 1, alpha: 1))
        case .type: Theme.dynamic(light: NSColor(srgbRed: 0.51, green: 0.31, blue: 0.87, alpha: 1), dark: NSColor(srgbRed: 0.82, green: 0.66, blue: 1, alpha: 1))
        }
    }
}

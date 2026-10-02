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

    // Delimiters as character arrays, built once (not per character while scanning).
    private let lineCommentChars: [[Character]]
    private let blockStartChars: [Character]?
    private let blockEndChars: [Character]?

    init(language: SyntaxLanguage, maxLineLength: Int = 1_000) {
        self.language = language
        self.maxLineLength = maxLineLength
        lineCommentChars = language.lineComments.map { Array($0) }
        blockStartChars = language.blockComment.map { Array($0.start) }
        blockEndChars = language.blockComment.map { Array($0.end) }
    }

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
        /// Allocation-free comparison of `p` against the line at `index`.
        func matches(_ p: [Character], at index: Int) -> Bool {
            guard !p.isEmpty, index + p.count <= chars.count else { return false }
            for k in 0..<p.count where chars[index + k] != p[k] { return false }
            return true
        }
        /// Index just past the block-comment end, or `chars.count` if it continues.
        func blockEnd(from index: Int, end: [Character]) -> Int {
            var j = index
            while j < chars.count {
                if matches(end, at: j) { inBlockComment = false; return j + end.count }
                j += 1
            }
            inBlockComment = true
            return chars.count
        }

        if inBlockComment, let endChars = blockEndChars {
            let end = blockEnd(from: 0, end: endChars)
            emit(0, end, .comment)
            i = end
        }

        while i < chars.count {
            let c = chars[i]
            if lineCommentChars.contains(where: { matches($0, at: i) }) {
                emit(i, chars.count, .comment)
                break
            }
            if let start = blockStartChars, let endChars = blockEndChars, matches(start, at: i) {
                let end = blockEnd(from: i + start.count, end: endChars)
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

    // Dynamic colors are created once; building one per token was a hot spot in large diffs.
    private static let keywordColor = Theme.dynamic(light: NSColor(srgbRed: 0.81, green: 0.13, blue: 0.18, alpha: 1), dark: NSColor(srgbRed: 1, green: 0.48, blue: 0.45, alpha: 1))
    private static let stringColor = Theme.dynamic(light: NSColor(srgbRed: 0.04, green: 0.19, blue: 0.41, alpha: 1), dark: NSColor(srgbRed: 0.65, green: 0.84, blue: 1, alpha: 1))
    private static let numberColor = Theme.dynamic(light: NSColor(srgbRed: 0.02, green: 0.31, blue: 0.68, alpha: 1), dark: NSColor(srgbRed: 0.47, green: 0.75, blue: 1, alpha: 1))
    private static let typeColor = Theme.dynamic(light: NSColor(srgbRed: 0.51, green: 0.31, blue: 0.87, alpha: 1), dark: NSColor(srgbRed: 0.82, green: 0.66, blue: 1, alpha: 1))

    private static func color(_ kind: SyntaxTokenKind) -> Color? {
        switch kind {
        case .plain: nil
        case .keyword: keywordColor
        case .string: stringColor
        case .comment: .gray
        case .number: numberColor
        case .type: typeColor
        }
    }
}

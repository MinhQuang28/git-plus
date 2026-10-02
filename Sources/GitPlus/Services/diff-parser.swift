import Foundation

/// Converts unified diff text into numbered, typed lines for rendering.
enum DiffParser {
    static func parse(_ raw: String, maxLines: Int = 20_000) -> (lines: [DiffLine], truncated: Bool) {
        var result: [DiffLine] = []
        var oldNo = 0, newNo = 0
        var inHunk = false

        for (index, sub) in raw.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if result.count >= maxLines { return (result, true) }
            let text = String(sub)

            if text.hasPrefix("@@") {
                inHunk = true
                (oldNo, newNo) = hunkStarts(text)
                result.append(DiffLine(id: index, kind: .hunk, oldNumber: nil, newNumber: nil, text: text))
                continue
            }
            if !inHunk || text.hasPrefix("diff --git") {
                inHunk = false
                // File headers (diff --git, index, ---/+++) are shown in the file list instead.
                if text.hasPrefix("Binary files") || text.hasPrefix("rename ") || text.hasPrefix("new file") || text.hasPrefix("deleted file") {
                    result.append(DiffLine(id: index, kind: .meta, oldNumber: nil, newNumber: nil, text: text))
                }
                continue
            }

            switch text.first {
            case "+":
                result.append(DiffLine(id: index, kind: .added, oldNumber: nil, newNumber: newNo, text: String(text.dropFirst())))
                newNo += 1
            case "-":
                result.append(DiffLine(id: index, kind: .removed, oldNumber: oldNo, newNumber: nil, text: String(text.dropFirst())))
                oldNo += 1
            case " ":
                result.append(DiffLine(id: index, kind: .context, oldNumber: oldNo, newNumber: newNo, text: String(text.dropFirst())))
                oldNo += 1; newNo += 1
            case "\\":
                result.append(DiffLine(id: index, kind: .meta, oldNumber: nil, newNumber: nil, text: text))
            default:
                continue   // trailing empty line
            }
        }
        return (result, false)
    }

    /// Parses `@@ -a,b +c,d @@` → (a, c).
    static func hunkStarts(_ header: String) -> (Int, Int) {
        let parts = header.split(separator: " ")
        guard parts.count >= 3 else { return (0, 0) }
        func start(_ s: Substring) -> Int { Int(s.dropFirst().split(separator: ",").first ?? "") ?? 0 }
        return (start(parts[1]), start(parts[2]))
    }

    /// Renders a file with conflict markers as a pseudo-diff: "ours" blocks as removed (red),
    /// "theirs" blocks as added (green), markers as meta rows.
    static func conflictDiff(_ text: String) -> String {
        var out = ["@@ conflicts: red = ours (current branch) · green = theirs (incoming) @@"]
        var side: Character = " "
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("<<<<<<<") { side = "-"; out.append("\\ " + line); continue }
            if line.hasPrefix("|||||||") { side = "~"; out.append("\\ " + line); continue }
            if line.hasPrefix("=======") && side != " " { side = "+"; out.append("\\ " + line); continue }
            if line.hasPrefix(">>>>>>>") { side = " "; out.append("\\ " + line); continue }
            if side == "~" { continue }   // diff3 base section
            out.append(String(side) + line)
        }
        return out.joined(separator: "\n")
    }
}

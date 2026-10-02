import Foundation

/// Builds partial patches from a single-file unified diff for hunk / line staging.
///
/// Line ids are indices into `raw.split("\n")`, the same ids `DiffParser` assigns to `DiffLine`s.
/// - Forward (stage, applied to the index): unselected `-` lines become context, unselected `+` lines are dropped.
/// - Reverse (unstage / discard, applied with `-R`): unselected `+` lines become context, unselected `-` lines are dropped.
enum PatchBuilder {
    static func patch(raw: String, selected: Set<Int>, reverse: Bool) -> String? {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let firstHunk = lines.firstIndex(where: { $0.hasPrefix("@@") }) else { return nil }
        var out = Array(lines[..<firstHunk])   // file header: diff --git / index / --- / +++

        var i = firstHunk
        var emittedAny = false
        while i < lines.count {
            guard lines[i].hasPrefix("@@") else { i += 1; continue }
            let header = lines[i]
            var body: [String] = []
            var oldCount = 0, newCount = 0, changes = 0
            var lastKept = false
            i += 1
            while i < lines.count, !lines[i].hasPrefix("@@"), !lines[i].hasPrefix("diff --git") {
                let line = lines[i], id = i
                i += 1
                guard let first = line.first else { continue }   // trailing empty line
                switch first {
                case " ":
                    body.append(line); oldCount += 1; newCount += 1; lastKept = true
                case "-", "+":
                    let isSelected = selected.contains(id)
                    let keepAsChange = isSelected
                    // Which unselected kind survives as context depends on the apply direction.
                    let survivesAsContext = !isSelected && ((first == "-" && !reverse) || (first == "+" && reverse))
                    if keepAsChange {
                        body.append(line); changes += 1; lastKept = true
                        if first == "-" { oldCount += 1 } else { newCount += 1 }
                    } else if survivesAsContext {
                        body.append(" " + line.dropFirst()); oldCount += 1; newCount += 1; lastKept = true
                    } else {
                        lastKept = false
                    }
                case "\\":
                    if lastKept { body.append(line) }   // "\ No newline at end of file" belongs to the previous line
                default:
                    continue
                }
            }
            guard changes > 0 else { continue }
            let (oldStart, newStart) = DiffParser.hunkStarts(header)
            out.append("@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@")
            out += body
            emittedAny = true
        }
        return emittedAny ? out.joined(separator: "\n") + "\n" : nil
    }

    /// All change lines of the hunk starting at `hunkID` (a `@@` line id).
    static func changeLines(inHunk hunkID: Int, raw: String) -> Set<Int> {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        var ids = Set<Int>()
        var i = hunkID + 1
        while i < lines.count, !lines[i].hasPrefix("@@"), !lines[i].hasPrefix("diff --git") {
            if lines[i].hasPrefix("+") || lines[i].hasPrefix("-") { ids.insert(i) }
            i += 1
        }
        return ids
    }
}

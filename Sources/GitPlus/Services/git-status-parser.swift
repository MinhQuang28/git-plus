import Foundation

/// Parses `git status --porcelain=v2 -z --branch` into both the repo summary and the file lists,
/// so one process (one worktree scan) serves the toolbar, the repo list and the Changes tab.
extension GitParsers {
    private static let conflictPairs: Set<String> = ["DD", "AU", "UD", "UA", "DU", "AA", "UU"]

    static func snapshot(_ output: String) -> (status: RepoStatus, tree: WorkingTree) {
        var s = RepoStatus()
        var tree = WorkingTree()
        var tokens = output.split(separator: "\0", omittingEmptySubsequences: true).makeIterator()

        /// v2 uses "." for "unchanged"; the rest of the app expects v1-style letters.
        func letter(_ c: Character) -> String? { c == "." ? nil : String(c) }

        while let token = tokens.next() {
            switch token.first {
            case "#":
                if token.hasPrefix("# branch.head ") {
                    s.branch = String(token.dropFirst("# branch.head ".count))
                } else if token.hasPrefix("# branch.upstream ") {
                    s.upstream = String(token.dropFirst("# branch.upstream ".count))
                } else if token.hasPrefix("# branch.ab ") {
                    let parts = token.split(separator: " ")
                    if parts.count >= 4 {
                        s.ahead = Int(parts[2].dropFirst()) ?? 0
                        s.behind = Int(parts[3].dropFirst()) ?? 0
                    }
                }
            case "?":
                s.changedFiles += 1
                tree.unstaged.append(ChangedFile(status: "?", path: String(token.dropFirst(2)), oldPath: nil, area: .unstaged))
            case "u":
                // u XY sub m1 m2 m3 mW h1 h2 h3 path
                let f = token.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
                guard f.count == 11 else { continue }
                s.changedFiles += 1
                s.conflicts += 1
                let code = String(f[1])
                tree.conflicted.append(ChangedFile(status: "U", path: String(f[10]), oldPath: nil, area: .conflicted,
                                                   conflictCode: conflictPairs.contains(code) ? code : "UU"))
            case "1", "2":
                // 1 XY sub mH mI mW hH hI path   |   2 XY sub mH mI mW hH hI Xscore path \0 origPath
                let isRename = token.first == "2"
                let f = token.split(separator: " ", maxSplits: isRename ? 9 : 8, omittingEmptySubsequences: false)
                guard f.count == (isRename ? 10 : 9), f[1].count == 2 else { continue }
                let path = String(f[isRename ? 9 : 8])
                let orig = isRename ? tokens.next().map(String.init) : nil
                s.changedFiles += 1
                let xy = Array(f[1])
                if let x = letter(xy[0]) {
                    let renamed = x == "R" || x == "C"
                    tree.staged.append(ChangedFile(status: renamed ? "R" : x, path: path, oldPath: renamed ? orig : nil, area: .staged))
                }
                if let y = letter(xy[1]) {
                    tree.unstaged.append(ChangedFile(status: y == "R" || y == "C" ? "M" : y, path: path, oldPath: nil, area: .unstaged))
                }
            default:
                continue   // "!" ignored entries
            }
        }
        tree.staged.sort { $0.path < $1.path }
        tree.unstaged.sort { $0.path < $1.path }
        tree.conflicted.sort { $0.path < $1.path }
        return (s, tree)
    }

    /// `git diff --raw --numstat -z -M`: raw records (status + paths) followed by numstat records, same order.
    static func changedFiles(rawNumstat output: String) -> [ChangedFile] {
        var files: [ChangedFile] = []
        var statIndex = 0
        var tokens = output.split(separator: "\0", omittingEmptySubsequences: false).makeIterator()
        while let token = tokens.next() {
            if token.isEmpty { continue }
            if token.first == ":" {
                // :oldmode newmode oldsha newsha STATUS[score]  \0 path  (\0 newpath for R/C)
                guard let field = token.split(separator: " ").last, let letter = field.first, let first = tokens.next() else { continue }
                if letter == "R" || letter == "C", let second = tokens.next() {
                    files.append(ChangedFile(status: String(letter), path: String(second), oldPath: String(first)))
                } else {
                    files.append(ChangedFile(status: String(letter), path: String(first), oldPath: nil))
                }
            } else {
                // adds \t dels \t path   — renames leave path empty and add \0 old \0 new
                let cols = token.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                guard cols.count == 3 else { continue }
                if cols[2].isEmpty { _ = tokens.next(); _ = tokens.next() }
                if statIndex < files.count {
                    files[statIndex].additions = Int(cols[0]) ?? 0   // "-" for binary files
                    files[statIndex].deletions = Int(cols[1]) ?? 0
                }
                statIndex += 1
            }
        }
        return files
    }
}

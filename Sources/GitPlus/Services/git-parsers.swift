import Foundation

/// Pure parsers for git CLI output (kept separate for unit testing).
enum GitParsers {
    private static let fieldSep: Character = "\u{1f}"
    private static let recordSep: Character = "\u{1e}"

    /// hash, short hash, parents, author, email, ISO date, subject, decorations.
    static let logFormat = "%H%x1f%h%x1f%P%x1f%an%x1f%ae%x1f%aI%x1f%s%x1f%D%x1e"

    static func commits(_ output: String) -> [Commit] {
        let iso = ISO8601DateFormatter()
        return output.split(separator: recordSep).compactMap { record in
            let f = record.trimmingCharacters(in: .newlines).split(separator: fieldSep, omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 8 else { return nil }
            let refs = f[7].split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "HEAD -> ", with: "") }
                .filter { !$0.isEmpty }
            return Commit(
                hash: f[0], shortHash: f[1],
                parents: f[2].split(separator: " ").map(String.init),
                author: f[3], email: f[4],
                date: iso.date(from: f[5]) ?? .distantPast,
                subject: f[6], refs: refs
            )
        }
    }

    static func status(_ output: String) -> RepoStatus {
        var s = RepoStatus()
        for line in output.split(separator: "\n") {
            if line.hasPrefix("# branch.head ") {
                s.branch = String(line.dropFirst("# branch.head ".count))
            } else if line.hasPrefix("# branch.upstream ") {
                s.upstream = String(line.dropFirst("# branch.upstream ".count))
            } else if line.hasPrefix("# branch.ab ") {
                let parts = line.split(separator: " ")
                if parts.count >= 4 {
                    s.ahead = Int(parts[2].dropFirst()) ?? 0
                    s.behind = Int(parts[3].dropFirst()) ?? 0
                }
            } else if !line.hasPrefix("#") {
                s.changedFiles += 1
                if line.hasPrefix("u ") { s.conflicts += 1 }
            }
        }
        return s
    }

    /// Merges `--name-status` and `--numstat` output (same order, same -M setting).
    static func changedFiles(nameStatus: String, numstat: String) -> [ChangedFile] {
        var files: [ChangedFile] = nameStatus.split(separator: "\n").compactMap { line in
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 2, let letter = cols[0].first else { return nil }
            if (letter == "R" || letter == "C"), cols.count >= 3 {
                return ChangedFile(status: String(letter), path: cols[2], oldPath: cols[1])
            }
            return ChangedFile(status: String(letter), path: cols[1], oldPath: nil)
        }
        let stats = numstat.split(separator: "\n").map { $0.split(separator: "\t") }
        for i in files.indices where i < stats.count && stats[i].count >= 2 {
            files[i].additions = Int(stats[i][0]) ?? 0   // "-" for binary files
            files[i].deletions = Int(stats[i][1]) ?? 0
        }
        return files
    }

    private static let conflictCodes: Set<String> = ["DD", "AU", "UD", "UA", "DU", "AA", "UU"]

    /// Parses `git status --porcelain=v1 -z` into staged / unstaged / conflicted lists.
    /// Index renames are encoded as `R  new\0old\0`.
    static func workingTree(_ output: String) -> WorkingTree {
        var tree = WorkingTree()
        var entries = output.split(separator: "\0", omittingEmptySubsequences: true).makeIterator()
        while let entry = entries.next() {
            guard entry.count >= 4 else { continue }
            let x = String(entry.prefix(1)), y = String(entry.dropFirst().prefix(1))
            let path = String(entry.dropFirst(3))
            if x == "?" {
                tree.unstaged.append(ChangedFile(status: "?", path: path, oldPath: nil, area: .unstaged))
                continue
            }
            if conflictCodes.contains(x + y) {
                tree.conflicted.append(ChangedFile(status: "U", path: path, oldPath: nil, area: .conflicted))
                continue
            }
            if x == "R" || x == "C" {
                tree.staged.append(ChangedFile(status: "R", path: path, oldPath: entries.next().map(String.init), area: .staged))
            } else if x != " " {
                tree.staged.append(ChangedFile(status: x, path: path, oldPath: nil, area: .staged))
            }
            if y != " " {
                tree.unstaged.append(ChangedFile(status: y, path: path, oldPath: nil, area: .unstaged))
            }
        }
        tree.staged.sort { $0.path < $1.path }
        tree.unstaged.sort { $0.path < $1.path }
        tree.conflicted.sort { $0.path < $1.path }
        return tree
    }
}

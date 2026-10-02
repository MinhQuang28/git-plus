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

    // MARK: Tags, remotes, file history, blame

    /// `for-each-ref refs/tags` with fields separated by \u{1f}: name, target, ISO date, subject.
    static func tags(_ output: String) -> [TagInfo] {
        let iso = ISO8601DateFormatter()
        return output.split(separator: "\n").compactMap { line in
            let f = line.split(separator: fieldSep, omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 4, !f[0].isEmpty else { return nil }
            return TagInfo(name: f[0], target: f[1], date: iso.date(from: f[2]), subject: f[3])
        }
    }

    /// `git remote -v`: `origin\tgit@host:a/b.git (fetch)` / `(push)` pairs.
    static func remotes(_ output: String) -> [RemoteEntry] {
        var result: [RemoteEntry] = []
        for line in output.split(separator: "\n") {
            let cols = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard cols.count == 2 else { continue }
            let name = cols[0]
            var url = cols[1], kind = "fetch"
            if url.hasSuffix(" (push)") { url.removeLast(7); kind = "push" } else if url.hasSuffix(" (fetch)") { url.removeLast(8) }
            if let i = result.firstIndex(where: { $0.name == name }) {
                if kind == "push" { result[i].pushURL = url } else { result[i].fetchURL = url }
            } else {
                result.append(RemoteEntry(name: name, fetchURL: url, pushURL: url))
            }
        }
        return result
    }

    /// `git log --follow --name-status --format=%x1e<logFormat without the record separator>`.
    static func fileHistory(_ output: String) -> [FileRevision] {
        output.split(separator: recordSep).compactMap { record in
            let lines = record.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let header = lines.first, let commit = commits(header + String(recordSep)).first else { return nil }
            guard let change = lines.dropFirst().last(where: { $0.contains("\t") }) else { return nil }
            let cols = change.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 2, let letter = cols[0].first else { return nil }
            let file = (letter == "R" || letter == "C") && cols.count >= 3
                ? ChangedFile(status: String(letter), path: cols[2], oldPath: cols[1])
                : ChangedFile(status: String(letter), path: cols[1], oldPath: nil)
            return FileRevision(commit: commit, file: file)
        }
    }

    /// `git blame --porcelain`. Commit details appear only the first time a commit is mentioned.
    static func blame(_ output: String) -> [BlameLine] {
        struct Info { var author = "", summary = "", time = Date.distantPast }
        var infos: [String: Info] = [:]
        var result: [BlameLine] = []
        var hash = "", lineNumber = 0
        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if raw.hasPrefix("\t") {
                let info = infos[hash] ?? Info()
                result.append(BlameLine(number: lineNumber, hash: hash, author: info.author, date: info.time,
                                        summary: info.summary, text: String(raw.dropFirst())))
                continue
            }
            let parts = raw.split(separator: " ", maxSplits: 1).map(String.init)
            guard let key = parts.first else { continue }
            if key.count == 40, key.allSatisfy(\.isHexDigit) {
                hash = key
                let numbers = (parts.count > 1 ? parts[1] : "").split(separator: " ")
                lineNumber = numbers.count >= 2 ? Int(numbers[1]) ?? 0 : 0
                if infos[hash] == nil { infos[hash] = Info() }
            } else if parts.count == 2 {
                switch key {
                case "author": infos[hash]?.author = parts[1]
                case "summary": infos[hash]?.summary = parts[1]
                case "author-time": infos[hash]?.time = Date(timeIntervalSince1970: TimeInterval(parts[1]) ?? 0)
                default: break
                }
            }
        }
        return result
    }
}

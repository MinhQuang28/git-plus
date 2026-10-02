import Foundation

/// Lane layout for drawing a commit graph next to a date-ordered commit list.
///
/// Each row describes line segments inside that row's rectangle: `top` segments run from the
/// top edge (lane `from`) to the node's vertical middle (lane `to`); `bottom` segments run from
/// the middle (lane `from`) to the bottom edge (lane `to`). Rows stacked together form the graph.
struct GraphRow: Hashable, Sendable {
    struct Segment: Hashable, Sendable {
        let from: Int
        let to: Int
    }

    let node: Int
    let top: [Segment]
    let bottom: [Segment]
    /// Number of lanes this row needs to draw.
    let width: Int
    var isMerge: Bool
}

/// Incremental: keeps the open lanes, so loading another history page lays out only the new commits.
struct CommitGraph: Sendable {
    private var lanes: [String?] = []

    /// `commits` must be ordered newest first, children before parents (`git log --date-order`).
    static func layout(_ commits: [Commit]) -> [GraphRow] {
        var graph = CommitGraph()
        return graph.append(commits)
    }

    /// Lays out the next commits (continuing from the previous call).
    mutating func append(_ commits: [Commit]) -> [GraphRow] {
        var rows: [GraphRow] = []
        rows.reserveCapacity(commits.count)

        func freeSlot() -> Int {
            if let i = lanes.firstIndex(where: { $0 == nil }) { return i }
            lanes.append(nil)
            return lanes.count - 1
        }

        for commit in commits {
            let node = lanes.firstIndex(where: { $0 == commit.hash }) ?? freeSlot()

            // Segments from the top edge, computed before this commit's lanes are released.
            var top: [GraphRow.Segment] = []
            for (i, hash) in lanes.enumerated() {
                guard let hash else { continue }
                top.append(GraphRow.Segment(from: i, to: hash == commit.hash ? node : i))
            }
            for i in lanes.indices where lanes[i] == commit.hash { lanes[i] = nil }

            var bottom: [GraphRow.Segment] = []
            // Lanes that just pass through this row.
            for (i, hash) in lanes.enumerated() where hash != nil {
                bottom.append(GraphRow.Segment(from: i, to: i))
            }
            for (k, parent) in commit.parents.enumerated() {
                if k == 0, let existing = lanes.firstIndex(where: { $0 == parent }), existing > node, lanes[node] == nil {
                    // Pull the parent's lane left into this node's lane so the main line stays leftmost.
                    lanes[node] = parent
                    lanes[existing] = nil
                    bottom.removeAll { $0 == GraphRow.Segment(from: existing, to: existing) }
                    bottom.append(GraphRow.Segment(from: existing, to: node))
                    bottom.append(GraphRow.Segment(from: node, to: node))
                } else if let existing = lanes.firstIndex(where: { $0 == parent }) {
                    bottom.append(GraphRow.Segment(from: node, to: existing))
                } else {
                    // The first parent continues straight down in the node's own lane.
                    let slot = k == 0 && lanes[node] == nil ? node : freeSlot()
                    lanes[slot] = parent
                    bottom.append(GraphRow.Segment(from: node, to: slot))
                }
            }
            while let last = lanes.last, last == nil { lanes.removeLast() }

            let used = ([node] + top.flatMap { [$0.from, $0.to] } + bottom.flatMap { [$0.from, $0.to] }).max() ?? 0
            rows.append(GraphRow(node: node, top: top, bottom: bottom, width: used + 1, isMerge: commit.parents.count > 1))
        }
        return rows
    }
}

/// Subsequence matching with a score (higher is better), for the command palette.
enum FuzzyMatch {
    static func score(_ query: String, _ candidate: String) -> Int? {
        let q = Array(query.lowercased().filter { !$0.isWhitespace })
        guard !q.isEmpty else { return 0 }
        let c = Array(candidate.lowercased())
        var qi = 0, score = 0, streak = 0
        var previous: Character = " "
        for ch in c {
            guard qi < q.count else { break }
            if ch == q[qi] {
                streak += 1
                score += 1 + streak * 2
                // Bonus for word starts ("fp" → "Force Push").
                if previous == " " || previous == "/" || previous == "-" || previous == "_" || previous == "." { score += 6 }
                qi += 1
            } else {
                streak = 0
            }
            previous = ch
        }
        guard qi == q.count else { return nil }
        if c.starts(with: q) { score += 20 }
        return score - c.count / 8
    }
}

/// History search: plain words search messages (and authors); `author:`, `path:` narrow it down.
struct HistoryQuery: Equatable, Sendable {
    var text = ""
    var author: String?
    var paths: [String] = []

    var isEmpty: Bool { text.isEmpty && author == nil && paths.isEmpty }
    /// A plain hex word that may be a commit SHA.
    var looksLikeHash: Bool { text.count >= 4 && text.count <= 40 && text.allSatisfy(\.isHexDigit) }

    init(text: String = "", author: String? = nil, paths: [String] = []) {
        self.text = text
        self.author = author
        self.paths = paths
    }

    init(parsing raw: String) {
        var words: [String] = []
        for token in raw.split(whereSeparator: \.isWhitespace).map(String.init) {
            let lower = token.lowercased()
            if lower.hasPrefix("author:"), token.count > 7 {
                author = String(token.dropFirst(7))
            } else if lower.hasPrefix("path:"), token.count > 5 {
                paths.append(String(token.dropFirst(5)))
            } else {
                words.append(token)
            }
        }
        text = words.joined(separator: " ")
    }
}

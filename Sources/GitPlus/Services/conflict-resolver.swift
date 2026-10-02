import Foundation

/// Splits a file with conflict markers into common text and conflict blocks, and rebuilds it
/// from per-block choices (block-level conflict resolution).
enum ConflictResolver {
    enum Choice: String, CaseIterable, Sendable {
        case ours, theirs, oursThenTheirs, theirsThenOurs

        var title: String {
            switch self {
            case .ours: "Use Ours"
            case .theirs: "Use Theirs"
            case .oursThenTheirs: "Both (Ours First)"
            case .theirsThenOurs: "Both (Theirs First)"
            }
        }
    }

    struct Block: Identifiable, Hashable, Sendable {
        let id: Int
        let ours: [String]
        let base: [String]?
        let theirs: [String]
        let oursLabel: String
        let theirsLabel: String
    }

    enum Segment: Hashable, Sendable {
        case common([String])
        case conflict(Block)
    }

    static func parse(_ text: String) -> [Segment] {
        var segments: [Segment] = []
        var common: [String] = []
        var ours: [String] = [], base: [String] = [], theirs: [String] = []
        var oursLabel = "", theirsLabel = ""
        var hasBase = false
        enum State { case common, ours, base, theirs }
        var state = State.common
        var count = 0

        func label(_ line: String) -> String { line.dropFirst(7).trimmingCharacters(in: .whitespaces) }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            switch state {
            case .common:
                if line.hasPrefix("<<<<<<<") {
                    if !common.isEmpty { segments.append(.common(common)); common = [] }
                    ours = []; base = []; theirs = []; hasBase = false
                    oursLabel = label(line)
                    state = .ours
                } else {
                    common.append(line)
                }
            case .ours:
                if line.hasPrefix("|||||||") { hasBase = true; state = .base }
                else if line.hasPrefix("=======") { state = .theirs }
                else { ours.append(line) }
            case .base:
                if line.hasPrefix("=======") { state = .theirs } else { base.append(line) }
            case .theirs:
                if line.hasPrefix(">>>>>>>") {
                    theirsLabel = label(line)
                    segments.append(.conflict(Block(id: count, ours: ours, base: hasBase ? base : nil, theirs: theirs,
                                                    oursLabel: oursLabel, theirsLabel: theirsLabel)))
                    count += 1
                    state = .common
                } else {
                    theirs.append(line)
                }
            }
        }
        // An unterminated conflict is kept verbatim so nothing is lost.
        if state != .common {
            common += ["<<<<<<< \(oursLabel)"] + ours
            if hasBase { common += ["|||||||"] + base }
            if state == .theirs { common += ["======="] + theirs }
        }
        if !common.isEmpty { segments.append(.common(common)) }
        return segments
    }

    static func blocks(_ segments: [Segment]) -> [Block] {
        segments.compactMap { if case .conflict(let b) = $0 { b } else { nil } }
    }

    /// Rebuilds the file. Blocks without a choice keep their markers.
    static func resolve(_ segments: [Segment], choices: [Int: Choice]) -> String {
        var out: [String] = []
        for segment in segments {
            switch segment {
            case .common(let lines):
                out += lines
            case .conflict(let b):
                switch choices[b.id] {
                case .ours: out += b.ours
                case .theirs: out += b.theirs
                case .oursThenTheirs: out += b.ours + b.theirs
                case .theirsThenOurs: out += b.theirs + b.ours
                case nil:
                    out.append("<<<<<<< \(b.oursLabel)")
                    out += b.ours
                    if let base = b.base { out.append("|||||||"); out += base }
                    out.append("=======")
                    out += b.theirs
                    out.append(">>>>>>> \(b.theirsLabel)")
                }
            }
        }
        return out.joined(separator: "\n")
    }
}

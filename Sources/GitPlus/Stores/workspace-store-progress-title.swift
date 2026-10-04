import Foundation

extension WorkspaceStore {
    /// Operation label → present-progressive title: "push" → "Pushing…", "force push" → "Force pushing…",
    /// "checkout remote branch" → "Checking out remote branch…".
    nonisolated static func progressTitle(_ label: String) -> String {
        var words = label.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return "Working…" }
        let verbIndex = words[0] == "force" && words.count > 1 ? 1 : 0
        words[verbIndex] = progressive(words[verbIndex])
        let text = words.joined(separator: " ")
        return text.prefix(1).uppercased() + text.dropFirst() + "…"
    }

    private nonisolated static let irregular = ["commit": "committing", "checkout": "checking out", "skip": "skipping", "stop": "stopping"]

    private nonisolated static func progressive(_ verb: String) -> String {
        if let known = irregular[verb] { return known }
        if verb.hasSuffix("e") && !verb.hasSuffix("ee") { return verb.dropLast() + "ing" }
        return verb + "ing"
    }
}

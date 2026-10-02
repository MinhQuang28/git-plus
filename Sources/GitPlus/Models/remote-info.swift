import Foundation

enum GitProvider: String, Sendable {
    case github, gitlab, other

    /// CLI used to talk to the provider API.
    var cliName: String? {
        switch self {
        case .github: "gh"
        case .gitlab: "glab"
        case .other: nil
        }
    }

    var reviewNoun: String { self == .gitlab ? "Merge Requests" : "Pull Requests" }
}

/// Parsed remote URL, e.g. `git@gitlab.com:acme/backend/api.git`.
struct RemoteInfo: Hashable, Sendable {
    let host: String
    /// Owner / group path, e.g. `acme/backend`.
    let namespace: String
    let name: String

    var provider: GitProvider {
        let h = host.lowercased()
        if h.contains("github") { return .github }
        if h.contains("gitlab") { return .gitlab }
        return .other
    }

    /// Key used for auto-grouping: `host/namespace`.
    var groupKey: String { "\(host)/\(namespace)" }
    var webURL: URL? { URL(string: "https://\(host)/\(namespace)/\(name)") }

    func commitURL(_ hash: String) -> URL? {
        let sep = provider == .gitlab ? "/-/commit/" : "/commit/"
        return URL(string: "https://\(host)/\(namespace)/\(name)\(sep)\(hash)")
    }

    /// Supports scp-like (`git@host:ns/repo.git`), ssh://, http(s):// and git:// forms.
    static func parse(_ raw: String) -> RemoteInfo? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.hasSuffix(".git") { s.removeLast(4) }
        while s.hasSuffix("/") { s.removeLast() }

        let host: String
        let path: String
        if let schemeRange = s.range(of: "://") {
            let rest = s[schemeRange.upperBound...]
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            var authority = String(rest[..<slash])
            if let at = authority.lastIndex(of: "@") { authority = String(authority[authority.index(after: at)...]) }
            if let colon = authority.firstIndex(of: ":") { authority = String(authority[..<colon]) }
            host = authority
            path = String(rest[rest.index(after: slash)...])
        } else if let colon = s.firstIndex(of: ":") {
            var authority = String(s[..<colon])
            if let at = authority.lastIndex(of: "@") { authority = String(authority[authority.index(after: at)...]) }
            host = authority
            path = String(s[s.index(after: colon)...])
        } else {
            return nil
        }

        var parts = path.split(separator: "/").map(String.init)
        guard !host.isEmpty, parts.count >= 2, let name = parts.popLast() else { return nil }
        return RemoteInfo(host: host, namespace: parts.joined(separator: "/"), name: name)
    }
}

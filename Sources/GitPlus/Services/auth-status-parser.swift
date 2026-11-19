import Foundation

/// Per-host result of `gh auth status` / `glab auth status`.
struct AuthHostStatus: Equatable, Identifiable {
    let host: String
    /// Account name when signed in.
    let user: String?
    var id: String { host }
    var isSignedIn: Bool { user != nil }
}

/// Splits `auth status` output into hosts. Both CLIs exit non-zero when *any* configured host fails
/// (e.g. gitlab.com without a token next to a working self-hosted GitLab), so the exit code alone
/// can't say whether the CLI is usable.
enum AuthStatusParser {
    static func hosts(_ output: String) -> [AuthHostStatus] {
        var result: [AuthHostStatus] = []
        var host: String?
        var user: String?

        func flush() {
            if let host { result.append(AuthHostStatus(host: host, user: user)) }
        }

        for raw in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // A host header is an unindented single token such as "github.com" or "gitlab.abcsoft.vn".
            if !line.hasPrefix(" "), !trimmed.isEmpty, !trimmed.contains(" "), trimmed.contains(".") {
                flush()
                host = trimmed
                user = nil
                continue
            }
            guard host != nil, trimmed.hasPrefix("✓"), trimmed.contains("Logged in to") else { continue }
            // glab: "Logged in to HOST as USER (keyring)"; gh: "Logged in to HOST account USER (keyring)".
            let words = trimmed.split(separator: " ").map(String.init)
            if let i = words.firstIndex(where: { $0 == "as" || $0 == "account" }), i + 1 < words.count {
                user = words[i + 1]
            }
        }
        flush()
        return result
    }
}

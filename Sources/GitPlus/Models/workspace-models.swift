import Foundation

/// A user-defined group of repositories (e.g. "Backend", "github.com/acme").
struct RepoGroup: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
}

/// A local git repository registered in the workspace.
struct RepoEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var path: String
    var groupID: UUID?
    /// Shown in the sidebar's Pinned section (nil = not pinned; optional so older workspace files still decode).
    var isPinned: Bool?

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
}

/// Persisted workspace state.
struct Workspace: Codable {
    var groups: [RepoGroup] = []
    var repos: [RepoEntry] = []
}

/// Sidebar selection target.
enum SidebarSelection: Hashable {
    case group(UUID)
    case ungrouped
    case repo(UUID)

    /// String form for `@AppStorage` (restores the last opened repo/group).
    var rawValue: String {
        switch self {
        case .group(let id): "group:\(id)"
        case .ungrouped: "ungrouped"
        case .repo(let id): "repo:\(id)"
        }
    }

    init?(rawValue: String) {
        if rawValue == "ungrouped" { self = .ungrouped; return }
        let parts = rawValue.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let id = UUID(uuidString: String(parts[1])) else { return nil }
        switch parts[0] {
        case "group": self = .group(id)
        case "repo": self = .repo(id)
        default: return nil
        }
    }
}

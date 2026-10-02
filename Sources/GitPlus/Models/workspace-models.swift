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
}

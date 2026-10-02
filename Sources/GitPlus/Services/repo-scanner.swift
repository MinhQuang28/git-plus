import Foundation

/// Finds git repositories inside a folder without descending into found repos.
enum RepoScanner {
    private static let skipped: Set<String> = ["node_modules", ".build", "build", "DerivedData", "Pods", "vendor", ".git"]

    static func findRepositories(in root: URL, maxDepth: Int = 3) -> [URL] {
        if GitService.isRepository(root) { return [root] }
        guard maxDepth > 0 else { return [] }
        let children = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        return children
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { !skipped.contains($0.lastPathComponent) }
            .flatMap { findRepositories(in: $0, maxDepth: maxDepth - 1) }
    }
}

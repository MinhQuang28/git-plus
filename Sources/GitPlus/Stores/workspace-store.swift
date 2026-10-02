import Foundation
import Observation

/// Owns the workspace (groups + repos), persists it, and tracks live repo status.
@MainActor @Observable
final class WorkspaceStore {
    private(set) var workspace = Workspace()
    private(set) var statuses: [UUID: RepoStatus] = [:]
    private(set) var busy: Set<UUID> = []
    var errorMessage: String?

    private let fileURL: URL

    init(fileURL: URL = WorkspaceStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    nonisolated static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("GitPlus/workspace.json")
    }

    // MARK: Queries

    var groups: [RepoGroup] { workspace.groups.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }

    func repos(in groupID: UUID?) -> [RepoEntry] {
        workspace.repos.filter { $0.groupID == groupID }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func repo(_ id: UUID) -> RepoEntry? { workspace.repos.first { $0.id == id } }
    func group(_ id: UUID) -> RepoGroup? { workspace.groups.first { $0.id == id } }

    // MARK: Groups

    @discardableResult
    func createGroup(named name: String) -> RepoGroup {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let existing = workspace.groups.first(where: { $0.name == trimmed }) { return existing }
        let group = RepoGroup(name: trimmed.isEmpty ? "New Group" : trimmed)
        workspace.groups.append(group)
        save()
        return group
    }

    func renameGroup(_ id: UUID, to name: String) {
        guard let i = workspace.groups.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        workspace.groups[i].name = name
        save()
    }

    /// Deletes the group; its repos become ungrouped (never removed).
    func deleteGroup(_ id: UUID) {
        workspace.groups.removeAll { $0.id == id }
        for i in workspace.repos.indices where workspace.repos[i].groupID == id { workspace.repos[i].groupID = nil }
        save()
    }

    func move(repoIDs: [UUID], to groupID: UUID?) {
        for i in workspace.repos.indices where repoIDs.contains(workspace.repos[i].id) { workspace.repos[i].groupID = groupID }
        save()
    }

    /// Groups every ungrouped repo by `host/namespace` of its remote (e.g. `github.com/acme`).
    func autoGroupByRemote() async {
        let ungrouped = repos(in: nil)
        await refreshStatus(ungrouped.map(\.id))
        for repo in ungrouped {
            guard let key = statuses[repo.id]?.remote?.groupKey else { continue }
            move(repoIDs: [repo.id], to: createGroup(named: key).id)
        }
    }

    // MARK: Repos

    /// Adds folders that are git repos; non-repo folders are scanned (depth 3) for nested repos.
    func add(folders: [URL], to groupID: UUID?) async {
        let found = await Task.detached { folders.flatMap { RepoScanner.findRepositories(in: $0) } }.value
        let known = Set(workspace.repos.map(\.path))
        let new = found.map(\.standardizedFileURL.path).filter { !known.contains($0) }
        guard !new.isEmpty else {
            if found.isEmpty { errorMessage = "No git repositories found in the selected folder." }
            return
        }
        let entries = Set(new).sorted().map { RepoEntry(path: $0, groupID: groupID) }
        workspace.repos += entries
        save()
        await refreshStatus(entries.map(\.id))
    }

    func remove(repoIDs: [UUID]) {
        workspace.repos.removeAll { repoIDs.contains($0.id) }
        repoIDs.forEach { statuses[$0] = nil }
        save()
    }

    // MARK: Git operations (concurrent across repos)

    func refreshStatus(_ ids: [UUID]? = nil) async {
        let targets = (ids ?? workspace.repos.map(\.id)).compactMap(repo)
        await withTaskGroup(of: (UUID, RepoStatus?).self) { group in
            for repo in targets {
                group.addTask { (repo.id, try? await GitService(repo: repo.url).status()) }
            }
            for await (id, status) in group { statuses[id] = status }
        }
    }

    func fetch(_ ids: [UUID]) async { await runEach(ids, label: "fetch") { try await $0.fetch() } }
    func pull(_ ids: [UUID]) async { await runEach(ids, label: "pull") { try await $0.pull() } }

    private func runEach(_ ids: [UUID], label: String, _ op: @escaping @Sendable (GitService) async throws -> Void) async {
        let targets = ids.compactMap(repo).filter { !busy.contains($0.id) }
        targets.forEach { busy.insert($0.id) }
        var failures: [String] = []
        await withTaskGroup(of: (UUID, String?).self) { group in
            for repo in targets {
                group.addTask {
                    do { try await op(GitService(repo: repo.url)); return (repo.id, nil) }
                    catch { return (repo.id, "\(repo.name): \(error.localizedDescription)") }
                }
            }
            for await (id, failure) in group {
                busy.remove(id)
                if let failure { failures.append(failure) }
            }
        }
        await refreshStatus(targets.map(\.id))
        if !failures.isEmpty { errorMessage = "\(label) failed:\n" + failures.joined(separator: "\n") }
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do { workspace = try JSONDecoder().decode(Workspace.self, from: data) }
        catch { errorMessage = "Could not read workspace: \(error.localizedDescription)" }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(workspace).write(to: fileURL, options: .atomic)
        } catch {
            errorMessage = "Could not save workspace: \(error.localizedDescription)"
        }
    }
}

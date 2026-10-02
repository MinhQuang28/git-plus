import Foundation
import Observation

/// Owns the workspace (groups + repos), persists it, and tracks live repo status.
@MainActor @Observable
final class WorkspaceStore {
    var workspace = Workspace()
    private(set) var statuses: [UUID: RepoStatus] = [:]
    private(set) var busy: Set<UUID> = []
    /// Bumped after every mutation of a repo so views can reload history/changes.
    private(set) var revisions: [UUID: Int] = [:]
    var errorMessage: String?

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        var isError = false
    }
    private(set) var toast: Toast?

    /// Shows a short confirmation that disappears after a few seconds.
    func showToast(_ message: String, isError: Bool = false) {
        let t = Toast(message: message, isError: isError)
        toast = t
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toast?.id == t.id { toast = nil }
        }
    }

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

    /// Runs one user-triggered git mutation, reports failures, refreshes status. Returns success.
    @discardableResult
    func perform(_ id: UUID, _ label: String, success: String? = nil,
                 _ op: @escaping @Sendable (GitService) async throws -> Void) async -> Bool {
        guard let repo = repo(id), !busy.contains(id) else { return false }
        busy.insert(id)
        defer { busy.remove(id) }
        var ok = true
        do { try await op(GitService(repo: repo.url)) } catch {
            errorMessage = "\(label) failed:\n\(error.localizedDescription)"
            ok = false
        }
        revisions[id, default: 0] += 1
        await refreshStatus([id])
        if ok, let success { showToast(success) }
        return ok
    }

    func push(_ id: UUID) async {
        let needsUpstream = statuses[id]?.upstream == nil
        let branch = statuses[id]?.branch ?? "branch"
        await perform(id, "push", success: needsUpstream ? "Published \(branch)" : "Pushed \(branch)") {
            try await $0.push(setUpstream: needsUpstream)
        }
    }

    func fetch(_ ids: [UUID]) async { await runEach(ids, label: "fetch", done: "Fetched") { try await $0.fetch() } }
    func pull(_ ids: [UUID]) async { await runEach(ids, label: "pull", done: "Pulled") { try await $0.pull() } }

    private func runEach(_ ids: [UUID], label: String, done: String, _ op: @escaping @Sendable (GitService) async throws -> Void) async {
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
        targets.forEach { revisions[$0.id, default: 0] += 1 }
        await refreshStatus(targets.map(\.id))
        if !failures.isEmpty {
            errorMessage = "\(label) failed:\n" + failures.joined(separator: "\n")
        } else if !targets.isEmpty {
            showToast(targets.count == 1 ? "\(done) \(targets[0].name)" : "\(done) \(targets.count) repositories")
        }
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do { workspace = try JSONDecoder().decode(Workspace.self, from: data) }
        catch { errorMessage = "Could not read workspace: \(error.localizedDescription)" }
    }

    func save() {
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

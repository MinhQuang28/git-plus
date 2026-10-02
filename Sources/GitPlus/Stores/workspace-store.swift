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
    /// Bumped when only the working tree / index changed outside Git Plus (history stays loaded).
    private(set) var worktreeRevisions: [UUID: Int] = [:]
    /// When each repository's last Git Plus operation finished; file events right after it are our own.
    @ObservationIgnored private var lastMutation: [UUID: Date] = [:]

    /// Last failure, shown as a non-blocking banner with a suggested fix.
    var failure: Failure?

    /// Plain error text (workspace I/O, scanning); shown through the same banner.
    var errorMessage: String? {
        get { failure?.detail }
        set { failure = newValue.map { Failure(title: "Git Plus", detail: $0) } }
    }

    struct Failure: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let detail: String
        var repoID: UUID? = nil
        var hint: GitErrorHint? = nil
    }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        var isError = false
        var actionTitle: String? = nil
        var action: (@MainActor () -> Void)? = nil

        static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
    }
    private(set) var toast: Toast?

    /// Shows a short confirmation that disappears after a few seconds (longer when it offers an action).
    func showToast(_ message: String, isError: Bool = false, actionTitle: String? = nil, action: (@MainActor () -> Void)? = nil) {
        let t = Toast(message: message, isError: isError, actionTitle: actionTitle, action: action)
        toast = t
        Task {
            try? await Task.sleep(for: .seconds(action == nil ? 3 : 7))
            if toast?.id == t.id { toast = nil }
        }
    }

    func dismissToast() { toast = nil }

    /// One git operation in the activity log.
    struct Activity: Identifiable, Equatable {
        let id = UUID()
        let repoName: String
        let label: String
        let started = Date()
        var finished: Date?
        var error: String?
        var isRunning: Bool { finished == nil }
    }
    private(set) var activities: [Activity] = []
    var runningActivityCount: Int { activities.filter(\.isRunning).count }

    private func beginActivity(_ repoName: String, _ label: String) -> UUID {
        let entry = Activity(repoName: repoName, label: label)
        activities.insert(entry, at: 0)
        if activities.count > 200 { activities.removeLast(activities.count - 200) }
        return entry.id
    }

    private func finishActivity(_ id: UUID, error: String? = nil) {
        guard let i = activities.firstIndex(where: { $0.id == id }) else { return }
        activities[i].finished = Date()
        activities[i].error = error
    }

    func clearFinishedActivities() { activities.removeAll { !$0.isRunning } }

    /// Default `git pull` behaviour (Settings → Sync).
    var defaultPullMode: PullMode {
        PullMode(rawValue: UserDefaults.standard.string(forKey: "pullMode") ?? "") ?? .fastForward
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

    var pinnedRepos: [RepoEntry] {
        workspace.repos.filter { $0.isPinned == true }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func togglePin(_ id: UUID) {
        guard let i = workspace.repos.firstIndex(where: { $0.id == id }) else { return }
        workspace.repos[i].isPinned = workspace.repos[i].isPinned == true ? nil : true
        save()
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

    /// Clones into `parent/name`, adds the result to the workspace and returns its id.
    func clone(_ remote: String, into destination: URL, groupID: UUID?) async -> UUID? {
        let activity = beginActivity(destination.lastPathComponent, "clone")
        do {
            try await GitService.clone(remote, into: destination)
            finishActivity(activity)
        } catch {
            finishActivity(activity, error: error.localizedDescription)
            report("Clone failed", error, repoID: nil)
            return nil
        }
        await add(folders: [destination], to: groupID)
        showToast("Cloned \(destination.lastPathComponent)")
        return workspace.repos.first { $0.path == destination.standardizedFileURL.path }?.id
    }

    func initRepository(at folder: URL, groupID: UUID?) async -> UUID? {
        do { try await GitService.initRepository(at: folder) } catch {
            report("Create repository failed", error, repoID: nil)
            return nil
        }
        await add(folders: [folder], to: groupID)
        showToast("Created repository \(folder.lastPathComponent)")
        return workspace.repos.first { $0.path == folder.standardizedFileURL.path }?.id
    }

    // MARK: Git operations (concurrent across repos)

    /// Most status refreshes / fetches allowed to run at once (each is a few git processes).
    private static let concurrencyLimit = 8

    /// Runs `work` for every repo with at most `concurrencyLimit` in flight; `handle` runs on the main actor.
    private func forEachBounded<T: Sendable>(_ repos: [RepoEntry], _ work: @escaping @Sendable (RepoEntry) async -> T,
                                             handle: (T) -> Void) async {
        await withTaskGroup(of: T.self) { group in
            var next = 0
            while next < min(Self.concurrencyLimit, repos.count) {
                let repo = repos[next]
                group.addTask { await work(repo) }
                next += 1
            }
            while let result = await group.next() {
                handle(result)
                if next < repos.count {
                    let repo = repos[next]
                    group.addTask { await work(repo) }
                    next += 1
                }
            }
        }
    }

    func refreshStatus(_ ids: [UUID]? = nil) async {
        let targets = (ids ?? workspace.repos.map(\.id)).compactMap(repo)
        await forEachBounded(targets, { repo -> (UUID, RepoStatus?) in (repo.id, try? await GitService(repo: repo.url).status()) }) { result in
            // Unchanged statuses are not written: every write re-renders all views reading `statuses`.
            if statuses[result.0] != result.1 { statuses[result.0] = result.1 }
        }
    }

    private func report(_ title: String, _ error: Error, repoID: UUID?) {
        let detail = error.localizedDescription
        failure = Failure(title: title, detail: detail, repoID: repoID, hint: GitErrorHint.classify(detail))
    }

    /// Runs one user-triggered git mutation, reports failures, refreshes status. Returns success.
    /// With `undo`, the success toast offers an Undo button that runs it.
    @discardableResult
    func perform(_ id: UUID, _ label: String, success: String? = nil,
                 undo: (@Sendable (GitService) async throws -> Void)? = nil,
                 _ op: @escaping @Sendable (GitService) async throws -> Void) async -> Bool {
        guard let repo = repo(id), !busy.contains(id) else { return false }
        busy.insert(id)
        let activity = beginActivity(repo.name, label)
        var ok = true
        do {
            try await op(GitService(repo: repo.url))
            finishActivity(activity)
        } catch {
            finishActivity(activity, error: error.localizedDescription)
            report("\(label.prefix(1).uppercased() + label.dropFirst()) failed", error, repoID: id)
            ok = false
        }
        busy.remove(id)
        revisions[id, default: 0] += 1
        await refreshStatus([id])
        lastMutation[id] = Date()
        if ok, let success {
            if let undo {
                showToast(success, actionTitle: "Undo") { [weak self] in
                    Task { _ = await self?.perform(id, "undo \(label)", success: "Undone", undo) }
                }
            } else {
                showToast(success)
            }
        }
        return ok
    }

    func push(_ id: UUID, force: Bool = false) async {
        let needsUpstream = statuses[id]?.upstream == nil
        let branch = statuses[id]?.branch ?? "branch"
        let label = force ? "force push" : "push"
        await perform(id, label, success: needsUpstream ? "Published \(branch)" : force ? "Force-pushed \(branch)" : "Pushed \(branch)") {
            try await $0.push(setUpstream: needsUpstream, force: force)
        }
    }

    /// Files changed outside Git Plus (FSEvents): reload status and the affected views.
    /// `affectsHistory == false` (an edited file, the index) leaves history and commit diffs alone.
    func noteExternalChange(_ id: UUID, affectsHistory: Bool) async {
        guard !busy.contains(id) else { return }
        // Events caused by our own operation arrive just after it; its refresh already covered them.
        if let last = lastMutation[id], Date().timeIntervalSince(last) < 1.5 { return }
        if affectsHistory { revisions[id, default: 0] += 1 } else { worktreeRevisions[id, default: 0] += 1 }
        await refreshStatus([id])
    }

    /// Silent background fetch (auto-fetch): no toast, no error banner.
    func backgroundFetch(_ id: UUID) async {
        guard let repo = repo(id), !busy.contains(id) else { return }
        try? await GitService(repo: repo.url).fetch()
        await refreshStatus([id])
    }

    func fetch(_ ids: [UUID]) async { await runEach(ids, label: "fetch", done: "Fetched") { try await $0.fetch() } }

    /// `mode == nil` → the default from Settings.
    func pull(_ ids: [UUID], mode: PullMode? = nil) async {
        let resolved = mode ?? defaultPullMode
        await runEach(ids, label: resolved == .fastForward ? "pull" : "pull (\(resolved.title.lowercased()))", done: "Pulled") {
            try await $0.pull(resolved)
        }
    }

    private func runEach(_ ids: [UUID], label: String, done: String, _ op: @escaping @Sendable (GitService) async throws -> Void) async {
        let targets = ids.compactMap(repo).filter { !busy.contains($0.id) }
        targets.forEach { busy.insert($0.id) }
        var activityIDs: [UUID: UUID] = [:]
        for repo in targets { activityIDs[repo.id] = beginActivity(repo.name, label) }
        var failures: [(UUID, String)] = []
        await forEachBounded(targets, { repo -> (UUID, String?) in
            do { try await op(GitService(repo: repo.url)); return (repo.id, nil) }
            catch { return (repo.id, "\(repo.name): \(error.localizedDescription)") }
        }) { result in
            busy.remove(result.0)
            if let id = activityIDs[result.0] { finishActivity(id, error: result.1) }
            if let failure = result.1 { failures.append((result.0, failure)) }
        }
        targets.forEach { revisions[$0.id, default: 0] += 1 }
        await refreshStatus(targets.map(\.id))
        let now = Date()
        targets.forEach { lastMutation[$0.id] = now }
        if !failures.isEmpty {
            let detail = failures.map(\.1).joined(separator: "\n")
            failure = Failure(title: "\(label.prefix(1).uppercased() + label.dropFirst()) failed", detail: detail,
                              repoID: failures.count == 1 ? failures[0].0 : nil, hint: GitErrorHint.classify(detail))
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

# Performance Review: Git Plus (2026-10-02)

Scope: Sources/GitPlus (Stores, Services, Views). Every finding below was checked against the code; I left out anything speculative.
Ranking is by how much a user would notice it: big repos and big groups first, then smaller costs.
Context: Swift 5 language mode, no `NonisolatedNonsendingByDefault`. So `GitService` async methods (and the parsers they call) already run off the main actor. The work that lands on the main actor is anything computed in view bodies or `@MainActor` view methods.

## Critical / High

### H1. Every action and every refresh runs `git status` twice, about 7 processes per click
- `GitService.status()` (git-service.swift:13-29) runs `status --porcelain=v2 --branch`, `rev-parse` and `config --get-regexp`.
- `RepoWorkspaceView.reload()` (repo-workspace-view.swift:175-184) runs `workingTree()` (`status --porcelain=v1 -z --untracked-files=all`, git-service-working-tree.swift:6) and `stash list`.
- `perform()` (workspace-store.swift:229-231) bumps `revisions` and calls `refreshStatus`. Staging one file therefore costs stage + 3 (status) + 2 (reload) + 1 (FileDiffView reload) = 7 processes, and two of them walk the whole worktree.
- An external edit takes the same path (check-ignore + 6), and so does every app activation (`activationTick`, repo-workspace-view.swift:95-98).
- Why it is slow: on large repos (monorepos, node_modules not ignored) each `git status` takes 100-500 ms. Doing it twice puts that delay on every stage/unstage/discard and every editor save.
- Fix: for the open repo, run one `git status --porcelain=v2 -z --branch --untracked-files=all` and derive both `RepoStatus` and `WorkingTree` from it (add `GitParsers.statusAndTree`). Then let `reload()` publish the status into the store (e.g. a `store.setStatus(id, …)` API) instead of calling `refreshStatus`. Cache `remoteURLs()` and refresh it only when `.git/config` changes, or only in `refreshStatus` for non-open repos.
- Impact: about half the git CPU per action, and roughly 100-400 ms less latency per stage/discard on large repos.

### H2. Cancelling a task does not stop git, and detached diff rendering keeps running
- `ProcessRunner.runData` (process-runner.swift:43-49) uses a continuation with no `withTaskCancellationHandler`. When `.task(id:)` is cancelled, the `git` child keeps running to the end.
- Triggers:
  - Arrow-keying through History. Each commit starts `CommitDetailView.load` (commit-detail-view.swift:40, 2 diffs + `show`) plus `FileDiffView.load`.
  - Typing in history search (history-pane-view.swift:56-63). The 300 ms debounce helps, but each search still runs 2-3 full-history `git log --grep` processes.
- `FileDiffView.load` (file-diff-view.swift:192-196) runs parse + split + highlight in `Task.detached`, which ignores the parent's cancellation. Fast file switching (`.id(file.id)`) leaves 20k-line highlight jobs piling up.
- Fix:
  - Wrap `runData` in `withTaskCancellationHandler { … } onCancel: { process.terminate() }`, keeping the `Process` in a lock-protected box.
  - Replace `Task.detached` with a child task (`async let`, or a nonisolated `static func prepare(...) async`) and check `Task.isCancelled` between the parse, split and highlight stages.
- Impact: much less CPU and process churn when scrolling quickly through history or files; the latest selection shows up sooner.

### H3. Broad `@Observable` reads plus one-write-per-repo refresh cause cascades of whole-view re-renders
- `refreshStatus` writes `statuses[id]` once per finished repo (workspace-store.swift:200-203). `runEach` mutates `busy` once per repo (:291), and `revisions` once per target (:295).
- Reading `store.statuses[x]`, `store.busy.contains`, or `store.revisions[x]` tracks the *whole* dictionary. Readers include:
  - RepoWorkspaceView (repo-workspace-view.swift:46-49)
  - HistoryPaneView (history-pane-view.swift:35)
  - CommitBoxView (commit-box-view.swift:25-31)
  - SyncToolbarButton (repo-toolbar.swift:86)
  - RepositoryListPanel (:115-121)
  - GroupWorkspaceView (:16, :43, :64)
  - GroupDashboardView/RepoCard (:29-30, :105-111)
- What happens: launch refresh of N repos, or Fetch All, re-renders every reader N or 2N times, even for repos that are not on screen. A status change in another repo re-runs `RepoWorkspaceView.body`, which recomputes `tree.all` and `tree.count` (a Set over all paths; git-models.swift:143-145) and `selectedFiles` (:114).
- Amplifier: `.environment(\.inspectFile, { … })` (repo-workspace-view.swift:75) passes a new closure on every body pass. Closures never compare equal, so ChangesPaneView and CommitDetailView (the readers) are invalidated every time. CommitDetailView then gives `ChangedFileList` a fresh `AnyView` closure (commit-detail-view.swift:26, :112-124), which re-renders the file list.
- Fix:
  1. Batch store writes: collect results in `forEachBounded` and assign `statuses` once (or flush every ~150 ms). Do the same for `busy` and `revisions` in `runEach`.
  2. Better: make per-repo state an `@Observable final class RepoLive { status; busy; revision; worktreeRevision }` held in `[UUID: RepoLive]`, created when a repo is added. Views then read `store.live(id).status`, so only that repo's views invalidate.
  3. Make `inspectFile` stable. Inject a reference-type `@Observable FileInspector` (or an `Equatable` action struct whose identity is `repo.id`) via `.environment(obj)`.
  4. Store `tree.count` and `tree.all` as properties computed once in `reload()`.
- Impact: launch and Fetch All in a 50-repo workspace go from about 100+ full-window body passes to a few. Fewer idle re-renders while background refreshes run.

## Medium

### M1. Group dashboard recomputes sparklines and 6 filter counts on every status write
- `GroupDashboardView.body` calls `count(f)` for all 6 filters (group-dashboard-view.swift:30, :36). That is 6×N `passes`, each building `SyncSuggestion`.
- It also calls `Self.sparklines(activity)` (:63), which runs 2 `Calendar` operations for up to 30×N commits, and `repos.filter(matches)` (:61).
- Combined with H3: N status writes × (6N + 60N calendar ops). With 50 repos that is about 150k calendar calls during a Fetch All.
- In `GroupWorkspaceView`, `repos` (sort with `localizedStandardCompare`) is evaluated 4+ times per body (:15-16, :42, :62, :106).
- Fix: compute sparklines once in `loadActivity()` and keep them in `@State`. Compute filter counts in one pass (one loop that increments 6 counters). Cache `let repos = store.repos(in:)` once per body and pass it down.
- Impact: smoother group view during refresh and fetch; makes large groups usable.

### M2. Hunk rows re-split the whole raw diff on every render
- `hunkActions` (file-diff-view.swift:155-165) calls `PatchBuilder.changeLines(inHunk:raw:)` while building the view. `changeLines` splits the *entire* `raw` text (patch-builder.swift:60) for every visible hunk header, on every `FileDiffView` body pass.
- Body passes happen on each line click (`selected`), hunk jump and scroll target change.
- Fix: compute the ids inside the button actions (`{ perform(.stage, ids: PatchBuilder.changeLines(...)) }`), or precompute `[hunkID: Set<Int>]` in `load()` off the main thread.
- Impact: removes O(diff size × visible hunks) main-thread work per interaction. Noticeable stutter on multi-MB diffs.

### M3. Diff is re-parsed and re-highlighted even when the text did not change
- `FileDiffView.task(id: …reloadKey)` (file-diff-view.swift:94) fires on every revision, every worktree revision and every app activation (repo-workspace-view.swift:124).
- `load()` always re-parses and re-highlights (up to 20k lines), resets `currentHunk`, and replaces `styles` (a new dictionary, so every visible row is re-diffed).
- Fix: `if text == raw, error == nil { return }` right after loading. Optionally hash the text.
- Impact: Cmd-Tab back into the app and stage operations stop costing a full highlight pass. A big diff stays responsive.

### M4. `changedFiles` runs two full diffs with rename detection
- git-service.swift:127-132 runs `diff --name-status -M` and `diff --numstat -M` in parallel. Rename detection, which is the expensive part, runs twice for every commit selected in History and every group-activity commit.
- Fix: run one process, `git diff --raw --numstat -z -M base head --`, and parse both sections. With `-z`, paths with tabs or newlines are handled too.
- Impact: about 2× faster file list for large commits and merges.

### M5. History paging re-walks history and recomputes the graph on the main actor
- `loadMore` (history-pane-view.swift:208-218) uses `--skip=N --date-order -n 200`. Each page re-walks N commits. Without a commit-graph file, `--date-order` must sort topologically over the reachable graph before printing anything. On big repos (Linux, Chromium-class) each page can take seconds.
- `CommitGraph.layout(commits)` (:217) recomputes all rows from scratch on the main actor for every page. It also copies `lanes` per commit (commit-graph.swift:36).
- Fix:
  - Make the layout incremental: keep `lanes` state and lay out only the new page. Run it off-main via a nonisolated static async helper.
  - Suggest or run `git commit-graph write --reachable` once per repo, or use `--topo-order` only when the graph is visible. Alternatively, page with `<lastHash>^@ --not <seen tips>`.
- Impact: page N stays as cheap as page 1; no main-thread hitch at 2-5k commits.

### M6. ProcessRunner blocks two GCD threads per git process
- process-runner.swift:45 + :85-91: each call occupies a `global(qos:)` thread (blocking `readDataToEndOfFile` + `waitUntilExit`) plus a second thread for stderr.
- `refreshStatus` runs 8 repos × 3 processes in parallel, so up to 48 blocked threads, near GCD's ~64-thread soft limit. Other `DispatchQueue.global` work (including FSEvents follow-ups) can stall during launch or Fetch All.
- Pipe handling itself is correct: stdout and stderr are drained concurrently, so there is no deadlock.
- Fix: use `process.terminationHandler` plus `FileHandle.readabilityHandler` (or `fileHandle.bytes`) to resume the continuation without blocking. This also makes H2 cancellation easy. Alternatively, run on a dedicated `OperationQueue` with `maxConcurrentOperationCount`.
- Impact: no thread starvation under load; this also enables H2.

### M7. Own background fetch triggers a second full reload
- `backgroundFetch` (workspace-store.swift:265-269) neither marks `busy` nor sets `lastMutation`. When the fetch updates `refs/remotes`, FSEvents fire `noteExternalChange(affectsHistory: true)` (repo-workspace-view.swift:170). That bumps `revisions` again: history log + graph + branches + headHash + tree + stashes + another status run.
- Fix: set `lastMutation[id] = Date()` after the background fetch (and its refresh). Only bump `revisions` if `status.behind` or the refs actually changed.
- Impact: avoids a redundant 8-10 process burst every auto-fetch that brings new commits.

## Low

- L1. ChangesPaneView builds `conflicted`, `staged` and `unstaged` as filtered arrays 2-3× per body (changes-pane-view.swift:23-25, used at :32-53), with `localizedCaseInsensitiveContains` per file. `--untracked-files=all` can produce 10k+ rows. `WorkingFileRow` takes a closure (:142), so rows cannot be skipped during diffing. Fix: compute the filtered lists once per body (`let s = staged`), and pass `ChangedFile` + area to an `Equatable` row that calls the store itself.
- L2. RepositoryListPanel re-sorts every group (`store.groups`, `store.repos(in:)` = filter + `localizedStandardCompare`) on every render (repository-list-panel.swift:44, :53, :66). The rows read `statuses` and `busy` inline, so each status write rebuilds the whole panel while it is open. Fix: extract `RepoListRow` (per-repo observation after H3) and cache sorted group membership in the store (invalidate on `workspace` mutation).
- L3. HistoryPaneView: `ForEach(Array(commits.enumerated()))` (history-pane-view.swift:148) allocates and diffs n items per body. Body re-runs on any repo's `revisions` change (H3). `CommitListRow.help` formats a date on every row render (commit-list-row.swift:54). Fix: store `GraphRow` inside a row model (`struct HistoryRow: Identifiable { commit; graph }`) and use `ForEach(rows)`.
- L4. SplitDiffRowView receives the full `styles` dictionary (diff-line-views.swift:112, file-diff-view.swift:116). Pass `styles[left.id]` / `styles[right.id]` so row inputs stay small and comparable. Unified `DiffLineView` gets an `onSelect` closure (file-diff-view.swift:125), which defeats row diffing. Pass `selectable: Bool` and handle selection via an environment action.
- L5. History `.task(id: revision)` also runs `branches()` + `headHash()` on every revision (history-pane-view.swift:52-55). `perform()` bumps `revisions` even for index-only operations (stage/unstage/discard, workspace-store.swift:230). Bump `worktreeRevisions` for those so history and branch reloads are skipped.

## Verified OK (no action)
- Login-shell PATH is resolved once (`static let environment`, process-runner.swift:20). The first git call pays about 0.1-1 s. Optional: warm it at launch with `_ = ProcessRunner.environment` in a background task.
- stdout/stderr pipes are drained concurrently, so large output cannot deadlock.
- The diff pipeline (parse, split, highlight, intraline) runs off-main. The highlighter is allocation-conscious. The ChangeMark strip is bucketed.
- Auto-fetch loop: one per open repo, cancelled with the view; no leak. Note: since `RepoWorkspaceView` uses `.id(repo.id)`, switching repos restarts the 10-minute timer.
- FileWatcher: FSEvents with a 0.6 s latency plus a 400 ms debounce, ignore filters, `check-ignore` capped at 200 paths.

## Recommended order
1. H1 (single status call), then H3 steps 1 + 3 (batched writes, stable `inspectFile`): quick wins with the biggest effect.
2. H2 + M6 together (non-blocking, cancellable ProcessRunner).
3. M2, M3, M4: small, local changes.
4. H3 step 2 (per-repo observable state), M1, M5.

## Unresolved questions
- Typical repo and group sizes for target users? This decides whether M5 (commit-graph) and M1 should move up the list.
- Should auto-fetch survive repo switching? That is a product decision, not a performance one.

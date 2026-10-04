import AppKit
import SwiftUI

/// Left pane "Changes" tab: Conflicts / Staged / Unstaged sections + commit box.
/// Multi-select with ⌘ / ⇧-click; Space stages or unstages the selection, ⌫ discards it.
struct ChangesPaneView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.inspectFile) private var inspectFile
    let repo: RepoEntry
    let tree: WorkingTree
    @Binding var selection: Set<ChangedFile.ID>

    @State private var discarding: [ChangedFile] = []
    @State private var confirmDiscardAll = false
    @State private var showStash = false
    @State private var filter = ""

    private func matches(_ file: ChangedFile) -> Bool {
        let q = filter.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || file.path.localizedCaseInsensitiveContains(q)
    }

    private var conflicted: [ChangedFile] { tree.conflicted.filter(matches) }
    private var staged: [ChangedFile] { tree.staged.filter(matches) }
    private var unstaged: [ChangedFile] { tree.unstaged.filter(matches) }
    private var hasConflicts: Bool { !tree.conflicted.isEmpty }

    var body: some View {
        // Filtered once per render (each is a pass over possibly thousands of files).
        let conflicted = self.conflicted, staged = self.staged, unstaged = self.unstaged
        VStack(spacing: 0) {
            if !tree.isEmpty { filterField }
            List(selection: $selection) {
                if !conflicted.isEmpty {
                    Section {
                        ForEach(conflicted) { row($0) }
                    } header: {
                        SectionHeader(title: "Conflicts", count: conflicted.count) {
                            IconButton(symbol: "wand.and.stars", help: "Resolve conflicts…") { RepoActions.post(.showConflicts) }
                        }
                    }
                }
                Section {
                    ForEach(staged) { row($0) }
                } header: {
                    SectionHeader(title: "Staged", count: staged.count) {
                        if !tree.staged.isEmpty {
                            IconButton(symbol: "minus.circle", help: "Unstage all") { run("unstage") { try await $0.unstageAll() } }
                        }
                    }
                }
                Section {
                    ForEach(unstaged) { row($0) }
                } header: {
                    SectionHeader(title: "Changes", count: unstaged.count) {
                        if !tree.unstaged.isEmpty {
                            IconButton(symbol: "plus.circle", help: "Stage all") { run("stage") { try await $0.stageAll() } }
                        }
                        if !tree.isEmpty { moreMenu }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: ChangedFile.ID.self) { ids in
                menu(files(ids))
            } primaryAction: { ids in
                toggle(files(ids))
            }
            .onKeyPress(.space) {
                let picked = files(selection)
                guard !picked.isEmpty else { return .ignored }
                toggle(picked)
                return .handled
            }
            .onDeleteCommand {
                let picked = files(selection).filter { $0.area != .conflicted }
                if !picked.isEmpty { discarding = picked }
            }
            .overlay {
                if tree.isEmpty {
                    ContentUnavailableView("No local changes", systemImage: "checkmark.seal",
                                           description: Text("Your working directory is clean."))
                }
            }
            Rectangle().fill(Theme.separator).frame(height: 1)
            CommitBoxView(repo: repo, stagedCount: tree.staged.count, hasChanges: !tree.isEmpty)
        }
        .sheet(isPresented: $showStash) { StashSheet(repo: repo) }
        .confirmationDialog(discardTitle, isPresented: Binding(get: { !discarding.isEmpty }, set: { if !$0 { discarding = [] } })) {
            Button("Discard Changes", role: .destructive) {
                store.discard(discarding, in: repo.id)
            }
        } message: {
            Text("You can undo this right after.")
        }
        .confirmationDialog("Discard all changes?", isPresented: $confirmDiscardAll) {
            Button("Discard All Changes", role: .destructive) {
                run("discard all", success: "Discarded all changes", undo: { try await $0.popLatestStash() }) { try await $0.discardAll() }
            }
        } message: {
            Text("Every change, including untracked files, is set aside in a stash, so you can still undo this.")
        }
    }

    private var filterField: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "line.3.horizontal.decrease").foregroundStyle(.secondary)
            TextField("Filter changed files", text: $filter).textFieldStyle(.plain)
            if !filter.isEmpty {
                Button { filter = "" } label: { Label("Clear filter", systemImage: "xmark.circle.fill").labelStyle(.iconOnly) }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .appFont(.callout)
        .padding(.horizontal, Spacing.s).padding(.vertical, 5)
        .background(Capsule().fill(Theme.headerBackground))
        .overlay(Capsule().stroke(Theme.separator))
        .padding(.horizontal, Spacing.s).padding(.top, Spacing.xs)
    }

    private var moreMenu: some View {
        Menu {
            Button("Stash Changes…") { showStash = true }
            Divider()
            Button("Discard All Changes…", role: .destructive) { confirmDiscardAll = true }
                .disabled(hasConflicts)
        } label: {
            Label("More actions", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More actions")
    }

    private var discardTitle: String {
        discarding.count == 1 ? "Discard changes to \(discarding[0].path)?" : "Discard changes to \(discarding.count) files?"
    }

    private func files(_ ids: Set<ChangedFile.ID>) -> [ChangedFile] { tree.all.filter { ids.contains($0.id) } }

    private func row(_ file: ChangedFile) -> some View {
        WorkingFileRow(file: file) { toggle([file]) }.tag(file.id)
    }

    /// Stage ↔ unstage (double-click, Space or the row button). Conflicted files open the resolver.
    private func toggle(_ files: [ChangedFile]) {
        let unstaged = files.filter { $0.area == .unstaged }
        let staged = files.filter { $0.area == .staged }
        if !unstaged.isEmpty || !staged.isEmpty {
            run(staged.isEmpty ? "stage" : unstaged.isEmpty ? "unstage" : "stage / unstage") {
                if !unstaged.isEmpty { try await $0.stage(unstaged) }
                if !staged.isEmpty { try await $0.unstage(staged) }
            }
        }
        if files.contains(where: { $0.area == .conflicted }) && unstaged.isEmpty && staged.isEmpty { RepoActions.post(.showConflicts) }
    }

    @ViewBuilder private func menu(_ files: [ChangedFile]) -> some View {
        let unstaged = files.filter { $0.area == .unstaged }
        let staged = files.filter { $0.area == .staged }
        let conflicted = files.filter { $0.area == .conflicted }
        if let file = conflicted.first, files.count == 1 {
            Button("Resolve Conflicts…") { RepoActions.post(.showConflicts) }
            Button("Use Ours") { run("resolve") { try await $0.resolve(file, side: .ours) } }
            Button("Use Theirs") { run("resolve") { try await $0.resolve(file, side: .theirs) } }
            Button("Mark as Resolved") { run("mark resolved") { try await $0.markResolved(file) } }
            Divider()
        }
        if !unstaged.isEmpty {
            Button(unstaged.count == 1 ? "Stage" : "Stage \(unstaged.count) Files") { run("stage") { try await $0.stage(unstaged) } }
        }
        if !staged.isEmpty {
            Button(staged.count == 1 ? "Unstage" : "Unstage \(staged.count) Files") { run("unstage") { try await $0.unstage(staged) } }
        }
        if conflicted.isEmpty && !files.isEmpty {
            Button(files.count == 1 ? "Stash File…" : "Stash \(files.count) Files") {
                let paths = Array(Set(files.flatMap(\.pathspec)))
                run("stash", success: "Stashed \(files.count == 1 ? files[0].path : "\(files.count) files")") {
                    try await $0.stash(message: "", includeUntracked: true, paths: paths)
                }
            }
        }
        if files.count == 1, let file = files.first {
            Divider()
            if file.status != "?" {
                Button("Show File History") { inspectFile?(FileInspection(path: file.path, mode: .history)) }
                Button("Blame") { inspectFile?(FileInspection(path: file.path, mode: .blame)) }
            }
            if file.status == "?" {
                Menu("Ignore") {
                    Button("Ignore “\((file.path as NSString).lastPathComponent)”") { ignore("/" + file.path) }
                    let ext = (file.path as NSString).pathExtension
                    if !ext.isEmpty { Button("Ignore All .\(ext) Files") { ignore("*.\(ext)") } }
                    let dir = (file.path as NSString).deletingLastPathComponent
                    if !dir.isEmpty { Button("Ignore Folder “\(dir)/”") { ignore("/" + dir + "/") } }
                }
            }
            Divider()
            Button("Open in Default App") { NSWorkspace.shared.open(repo.url.appendingPathComponent(file.path)) }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([repo.url.appendingPathComponent(file.path)]) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.path, forType: .string)
            }
        }
        if conflicted.isEmpty && !files.isEmpty {
            Divider()
            Button(files.count == 1 ? "Discard Changes…" : "Discard \(files.count) Files…", role: .destructive) { discarding = files }
        }
    }

    private func ignore(_ pattern: String) {
        run("ignore", success: "Added \(pattern) to .gitignore") { try $0.addToGitignore(pattern) }
    }

    private func run(_ label: String, success: String? = nil, undo: (@Sendable (GitService) async throws -> Void)? = nil,
                     _ op: @escaping @Sendable (GitService) async throws -> Void) {
        Task { await store.perform(repo.id, label, success: success, undo: undo, op) }
    }
}

/// File row: type icon, name over dimmed folder, stage/unstage button on hover, status letter.
struct WorkingFileRow: View {
    let file: ChangedFile
    let toggle: () -> Void
    @State private var hovering = false
    /// `.increased` while the row is selected — the stage button shows then too, not only on hover.
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        let showButton = hovering || prominence == .increased
        HStack(spacing: 6) {
            FileNameLabel(file: file)
            Spacer(minLength: 4)
            if file.additions + file.deletions > 0 {
                Text("+\(file.additions) −\(file.deletions)").appFont(.caption, monospacedDigit: true).foregroundStyle(.secondary)
            }
            // Fixed slot: the button fades in/out without shifting the row.
            IconButton(symbol: icon, help: help, action: toggle)
                .opacity(showButton ? 1 : 0)
                .allowsHitTesting(showButton)
                .accessibilityHidden(true)
            FileStatusLetter(status: file.status)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityValue(file.area == .staged ? "Staged" : file.area == .conflicted ? "Conflicted" : "Not staged")
        .accessibilityAction(named: help, toggle)
        .help(file.oldPath.map { "\($0) → \(file.path)" } ?? file.path)
    }

    private var icon: String {
        switch file.area {
        case .staged: "minus.circle"
        case .conflicted: "wand.and.stars"
        default: "plus.circle"
        }
    }

    private var help: String {
        switch file.area {
        case .staged: "Unstage"
        case .conflicted: "Resolve conflicts"
        default: "Stage"
        }
    }
}

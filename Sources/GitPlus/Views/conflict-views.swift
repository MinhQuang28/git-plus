import AppKit
import SwiftUI

/// Names of both sides of the operation in progress ("ours" / "theirs" as branch names).
struct ConflictSides: Equatable {
    var ours = "current branch"
    var theirs = "incoming branch"

    func name(_ side: ConflictSide) -> String { side == .ours ? ours : theirs }
}

// MARK: - Resolve conflicts dialog (GitHub Desktop style)

/// Lists every conflicted file; each one is resolved by picking the branch whose version to keep,
/// by resolving it block by block, or in the editor. Continue / Abort finish the operation.
struct ConflictsSheet: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let dismiss: () -> Void

    @State private var files: [ChangedFile] = []
    @State private var markers: [String: Int] = [:]
    @State private var resolved: [String] = []
    @State private var sides = ConflictSides()
    @State private var blockFile: ChangedFile?
    @State private var confirmAbort = false
    @State private var loaded = false

    private var git: GitService { GitService(repo: repo.url) }
    private var status: RepoStatus? { store.statuses[repo.id] }
    private var operation: GitOperation? { status?.operation }
    private var revision: Int { store.revisions[repo.id] ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            if let blockFile {
                HStack {
                    Button { self.blockFile = nil } label: { Label("All Conflicts", systemImage: "chevron.left") }
                        .buttonStyle(.glass)
                    Spacer()
                }
                .padding(Spacing.m)
                Divider()
                ConflictFileView(repo: repo, file: blockFile, sides: sides) { self.blockFile = nil }
            } else {
                header
                Divider()
                list
                Divider()
                footer
            }
        }
        .frame(width: blockFile == nil ? 620 : 980, height: blockFile == nil ? 520 : 680)
        .task(id: revision) { await load() }
        .confirmationDialog("Abort \(operation?.title.lowercased() ?? "operation")?", isPresented: $confirmAbort) {
            if let operation {
                Button("Abort \(operation.title)", role: .destructive) {
                    dismiss()
                    Task { await store.perform(repo.id, "abort", success: "\(operation.title) aborted") { try await $0.abortOperation(operation) } }
                }
            }
        } message: {
            Text("Your branch returns to the state before the \(operation?.title.lowercased() ?? "operation") started. Resolutions made so far are lost.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title).appFont(.title3, weight: .semibold)
            Text(subtitle).appFont(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.l)
    }

    private var title: String {
        switch operation {
        case .merge: "Resolve conflicts before merging \(sides.theirs) into \(sides.ours)"
        case .rebase: "Resolve conflicts before rebasing \(sides.theirs) onto \(sides.ours)"
        case .cherryPick: "Resolve conflicts before cherry-picking"
        case .revert: "Resolve conflicts before reverting"
        case nil: loaded && files.isEmpty && resolved.isEmpty ? "No conflicts" : "Resolve conflicts between \(sides.ours) and \(sides.theirs)"
        }
    }

    /// No merge/rebase to continue: the resolved files just need a commit.
    private var needsCommit: Bool { operation == nil && (!files.isEmpty || !resolved.isEmpty) }

    private var remaining: Int { files.count }

    private var subtitle: String {
        if operation == nil && !needsCommit { return "There is nothing to resolve." }
        if remaining == 0 { return operation == nil ? "All conflicts resolved. Commit the changes to finish." : "All conflicts resolved. Continue to finish." }
        return "\(remaining) conflicted file\(remaining == 1 ? "" : "s") · choose which branch's version to keep, or resolve block by block."
    }

    private var list: some View {
        List {
            ForEach(files) { file in row(file) }
            ForEach(resolved, id: \.self) { path in
                HStack(spacing: Spacing.s) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.added)
                    pathLabel(path)
                    Spacer()
                    Text("Resolved").appFont(.callout).foregroundStyle(Theme.added)
                }
                .padding(.vertical, Spacing.xs)
            }
        }
        .listStyle(.inset)
        .overlay {
            if loaded && files.isEmpty && resolved.isEmpty {
                ContentUnavailableView("No Conflicts", systemImage: "checkmark.seal")
            }
        }
    }

    private func row(_ file: ChangedFile) -> some View {
        let count = markers[file.path] ?? 0
        return HStack(spacing: Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.conflict)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                pathLabel(file.path)
                Text(rowDetail(file, markers: count)).appFont(.callout).foregroundStyle(count > 0 || file.deletedSide != nil ? Theme.conflict : Theme.added)
            }
            Spacer()
            if file.deletedSide == nil && count == 0 {
                Button("Mark as Resolved") { run(file, "mark resolved") { try await $0.markResolved(file) } }
                    .buttonStyle(.glassProminent)
            }
            Menu {
                resolveMenu(file, markers: count)
            } label: {
                Text("Resolve")
            }
            .menuStyle(.button)
            .fixedSize()
        }
        .padding(.vertical, Spacing.xs)
        .contextMenu { resolveMenu(file, markers: count) }
    }

    private func rowDetail(_ file: ChangedFile, markers count: Int) -> String {
        if let deleted = file.deletedSide {
            return "Deleted on \(sides.name(deleted)), modified on \(sides.name(deleted == .ours ? .theirs : .ours))"
        }
        if file.conflictCode == "DD" { return "Deleted on both branches" }
        return count > 0 ? "\(count) conflict\(count == 1 ? "" : "s")" : "No conflict markers left — mark it as resolved"
    }

    @ViewBuilder private func resolveMenu(_ file: ChangedFile, markers count: Int) -> some View {
        ForEach([ConflictSide.ours, .theirs], id: \.self) { side in
            let isDeleted = file.deletedSide == side || file.conflictCode == "DD"
            Button(isDeleted ? "Use deleted file from \(sides.name(side))" : "Use modified file from \(sides.name(side))") {
                run(file, "resolve \(file.path)") { try await $0.resolve(file, side: side) }
            }
        }
        if count > 0 {
            Divider()
            Button("Resolve Block by Block…") { blockFile = file }
        }
        Divider()
        if let editor = ExternalAppLauncher.preferredEditor(UserDefaults.standard.string(forKey: "preferredEditor") ?? "") {
            Button("Open in \(editor.name)") { editor.open(repo.url.appendingPathComponent(file.path)) }
        }
        Button("Open in Default App") { NSWorkspace.shared.open(repo.url.appendingPathComponent(file.path)) }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([repo.url.appendingPathComponent(file.path)]) }
    }

    private func pathLabel(_ path: String) -> some View {
        let dir = (path as NSString).deletingLastPathComponent
        return (Text(dir.isEmpty ? "" : dir + "/").foregroundColor(.secondary) + Text((path as NSString).lastPathComponent).fontWeight(.medium))
            .lineLimit(1).truncationMode(.middle)
    }

    private var footer: some View {
        HStack(spacing: Spacing.s) {
            if let operation {
                Button("Abort \(operation.title)…", role: .destructive) { confirmAbort = true }
                if operation == .rebase {
                    Button("Skip Commit") { finish("skip", nil) { try await $0.skipRebaseCommit() } }
                }
            }
            Spacer()
            Button("Close", action: dismiss).keyboardShortcut(.cancelAction)
            if let operation {
                Button("Continue \(operation.title)") {
                    finish("continue \(operation.rawValue)", "\(operation.title) completed") { try await $0.continueOperation(operation) }
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(remaining > 0)
            } else if needsCommit {
                Button("Commit Changes") {
                    dismiss()
                    RepoActions.show(.changes)
                    store.focusCommitMessage = repo.id
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(remaining > 0)
            }
        }
        .buttonStyle(.glass)
        .padding(Spacing.m)
    }

    private func run(_ file: ChangedFile, _ label: String, _ op: @escaping @Sendable (GitService) async throws -> Void) {
        Task {
            if await store.perform(repo.id, label, op) { resolved.append(file.path) }
        }
    }

    private func finish(_ label: String, _ success: String?, _ op: @escaping @Sendable (GitService) async throws -> Void) {
        Task {
            let ok = await store.perform(repo.id, label, success: success, op)
            // A rebase may stop again on the next commit; keep the dialog open then.
            if ok, store.statuses[repo.id]?.operation == nil { dismiss() } else { resolved = [] }
        }
    }

    private func load() async {
        let tree = (try? await git.workingTree()) ?? WorkingTree()
        files = tree.conflicted
        // Reading and parsing (possibly large) files stays off the main thread.
        let service = git, conflicted = tree.conflicted
        markers = await Task.detached {
            var counts: [String: Int] = [:]
            for file in conflicted { counts[file.path] = service.conflictMarkerCount(file) }
            return counts
        }.value
        resolved.removeAll { path in files.contains { $0.path == path } }
        let names = await git.conflictSides(operation)
        sides = ConflictSides(ours: names.ours, theirs: names.theirs)
        loaded = true
    }
}

// MARK: - Block-by-block resolver

/// Shows each conflict block with both versions side by side; pick a side (or both) per block,
/// then save the file and mark it resolved. Also used in the Changes tab for a conflicted file.
struct ConflictFileView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.diffFontSize) private var fontSize
    let repo: RepoEntry
    let file: ChangedFile
    var sides = ConflictSides()
    var onDone: () -> Void = {}

    @State private var segments: [ConflictResolver.Segment] = []
    @State private var choices: [Int: ConflictResolver.Choice] = [:]
    @State private var error: String?
    @State private var loadedSides: ConflictSides?

    private var git: GitService { GitService(repo: repo.url) }
    private var blocks: [ConflictResolver.Block] { ConflictResolver.blocks(segments) }
    private var names: ConflictSides { loadedSides ?? sides }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let error {
                Text(error).foregroundStyle(.red).padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if file.deletedSide != nil || file.conflictCode == "DD" {
                deletedConflict
            } else if blocks.isEmpty {
                ContentUnavailableView {
                    Label("No Conflict Markers", systemImage: "checkmark.seal")
                } description: {
                    Text("This file no longer contains conflict markers.")
                } actions: {
                    Button("Mark as Resolved") { save(text: nil) }.buttonStyle(.glassProminent)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.m) {
                        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                            switch segment {
                            case .common(let lines): commonLines(lines)
                            case .conflict(let block): blockCard(block)
                            }
                        }
                    }
                    .padding(Spacing.m)
                }
                .neutralScrollIndicator()
            }
        }
        .background(Theme.contextLine)
        .task(id: file.id) { await load() }
    }

    private var toolbar: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.conflict)
            Text(file.path).appFont(.body, weight: .medium).lineLimit(1).truncationMode(.head)
            Spacer()
            if !blocks.isEmpty {
                Text("\(choices.count) of \(blocks.count) resolved").appFont(.callout).foregroundStyle(.secondary).monospacedDigit()
                Menu("All Blocks") {
                    ForEach(ConflictResolver.Choice.allCases, id: \.self) { choice in
                        Button(label(choice)) { for b in blocks { choices[b.id] = choice } }
                    }
                    Divider()
                    Button("Clear Choices") { choices = [:] }
                }
                .fixedSize()
                Button("Save & Mark Resolved") { save(text: ConflictResolver.resolve(segments, choices: choices)) }
                    .buttonStyle(.glassProminent)
                    .disabled(choices.count < blocks.count)
                    .help(choices.count < blocks.count ? "Choose a version for every block first" : "Write the file and stage it")
            }
        }
        .padding(.horizontal, Spacing.m)
        .frame(minHeight: 44)
        .background(Theme.headerBackground)
    }

    private func label(_ choice: ConflictResolver.Choice) -> String {
        switch choice {
        case .ours: "Use \(names.ours)"
        case .theirs: "Use \(names.theirs)"
        case .oursThenTheirs: "Both (\(names.ours) first)"
        case .theirsThenOurs: "Both (\(names.theirs) first)"
        }
    }

    private func commonLines(_ lines: [String]) -> some View {
        // Only a little context around blocks; the rest collapses into a count.
        let shown = lines.count <= 6 ? lines : Array(lines.prefix(3)) + ["⋯ \(lines.count - 6) unchanged lines ⋯"] + Array(lines.suffix(3))
        return Text(shown.joined(separator: "\n"))
            .font(.system(size: fontSize, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.s)
    }

    private func blockCard(_ block: ConflictResolver.Block) -> some View {
        let choice = choices[block.id]
        return VStack(alignment: .leading, spacing: Spacing.s) {
            HStack {
                Text("Conflict \(block.id + 1) of \(blocks.count)").appFont(.headline)
                Spacer()
                if let choice { StatusPill(text: label(choice), symbol: "checkmark", tint: Theme.added) }
            }
            HStack(alignment: .top, spacing: Spacing.s) {
                side(title: names.ours, caption: "current", lines: block.ours, tint: Theme.ahead,
                     isChosen: choice == .ours || choice == .oursThenTheirs || choice == .theirsThenOurs) { choices[block.id] = .ours }
                side(title: names.theirs, caption: "incoming", lines: block.theirs, tint: Theme.lane(1),
                     isChosen: choice == .theirs || choice == .oursThenTheirs || choice == .theirsThenOurs) { choices[block.id] = .theirs }
            }
            HStack(spacing: Spacing.s) {
                Button("Use \(names.ours)") { choices[block.id] = .ours }
                Button("Use \(names.theirs)") { choices[block.id] = .theirs }
                Menu("Use Both") {
                    Button(label(.oursThenTheirs)) { choices[block.id] = .oursThenTheirs }
                    Button(label(.theirsThenOurs)) { choices[block.id] = .theirsThenOurs }
                }
                .fixedSize()
                if choice != nil {
                    Button("Reset") { choices[block.id] = nil }
                }
            }
            .controlSize(.small)
            .buttonStyle(.glass)
        }
        .padding(Spacing.m)
        .background(RoundedRectangle(cornerRadius: Radius.m).fill(Theme.paneBackground))
        .overlay(RoundedRectangle(cornerRadius: Radius.m).stroke(choice == nil ? Theme.conflict.opacity(0.6) : Theme.separator))
    }

    private func side(title: String, caption: String, lines: [String], tint: Color, isChosen: Bool, choose: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(title).appFont(.callout, weight: .semibold).lineLimit(1).truncationMode(.middle)
                Text(caption).appFont(.caption).foregroundStyle(.secondary)
                Spacer()
                if isChosen { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.added) }
            }
            Text(lines.isEmpty ? "(empty)" : lines.joined(separator: "\n"))
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(lines.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(Spacing.s)
                .background(RoundedRectangle(cornerRadius: Radius.s).fill(tint.opacity(isChosen ? 0.16 : 0.07)))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: choose)
        .help("Double-click to use this version")
    }

    private var deletedConflict: some View {
        let deleted = file.deletedSide ?? .ours
        let kept: ConflictSide = deleted == .ours ? .theirs : .ours
        return ContentUnavailableView {
            Label("Deleted on \(names.name(deleted))", systemImage: "trash")
        } description: {
            Text(file.conflictCode == "DD"
                 ? "Both branches deleted this file."
                 : "\(names.name(deleted)) deleted this file while \(names.name(kept)) modified it. Keep the modified file or the deletion.")
        } actions: {
            HStack {
                Button("Keep Modified File from \(names.name(kept))") { resolve(kept) }.buttonStyle(.glassProminent)
                    .disabled(file.conflictCode == "DD")
                Button("Delete File") { resolve(deleted) }.buttonStyle(.glass)
            }
        }
    }

    private func resolve(_ side: ConflictSide) {
        let file = self.file
        Task {
            if await store.perform(repo.id, "resolve \(file.path)", success: "Resolved \(file.path)", { try await $0.resolve(file, side: side) }) {
                finished()
            }
        }
    }

    /// Without a merge/rebase to continue (stash conflicts), the last resolution still needs a commit.
    private func finished() {
        onDone()
        guard let status = store.statuses[repo.id], status.operation == nil, status.conflicts == 0 else { return }
        store.showToast("All conflicts resolved — commit the changes to finish", actionTitle: "Commit") {
            RepoActions.show(.changes)
            store.focusCommitMessage = repo.id
        }
    }

    /// `text == nil` → keep the file as it is on disk, just mark it resolved.
    private func save(text: String?) {
        let file = self.file
        Task {
            let ok = await store.perform(repo.id, "resolve \(file.path)", success: "Resolved \(file.path)") {
                if let text { try await $0.saveResolution(file, text: text) } else { try await $0.markResolved(file) }
            }
            if ok { finished() }
        }
    }

    private func load() async {
        do {
            let text = try String(contentsOf: repo.url.appendingPathComponent(file.path), encoding: .utf8)
            segments = ConflictResolver.parse(text)
            choices = [:]
            error = nil
        } catch {
            segments = []
            if file.deletedSide == nil && file.conflictCode != "DD" {
                self.error = "Could not read the file as text: \(error.localizedDescription)"
            }
        }
        let n = await git.conflictSides(store.statuses[repo.id]?.operation)
        loadedSides = ConflictSides(ours: n.ours, theirs: n.theirs)
    }
}

// MARK: - Merge dialog

/// "Merge into <current branch>": pick a branch, preview conflicts, then merge, squash or rebase.
struct MergeSheet: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let dismiss: () -> Void

    enum Strategy: String, CaseIterable {
        case merge = "Create a merge commit", squash = "Squash and merge", rebase = "Rebase onto it"
    }

    @State private var branches = BranchList()
    @State private var filter = ""
    @State private var selected: String?
    @State private var strategy = Strategy.merge
    @State private var preview: [String]?
    @State private var incoming = 0
    @State private var isChecking = false

    private var git: GitService { GitService(repo: repo.url) }
    private var current: String { branches.current ?? store.statuses[repo.id]?.branch ?? "HEAD" }
    private var candidates: [String] {
        let localSet = Set(branches.local)
        let all = branches.local.filter { $0 != branches.current }
            + branches.remote.filter { !localSet.contains(BranchPickerView.shortName($0)) || BranchPickerView.shortName($0) == branches.current }
        let q = filter.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Merge into \(current)").appFont(.title3, weight: .semibold)
                TextField("Filter branches", text: $filter).textFieldStyle(.roundedBorder)
            }
            .padding(Spacing.l)
            List(candidates, id: \.self, selection: $selected) { name in
                Label(name, systemImage: branches.local.contains(name) ? "arrow.triangle.branch" : "cloud")
            }
            .listStyle(.inset)
            Divider()
            VStack(alignment: .leading, spacing: Spacing.m) {
                Picker("Strategy", selection: $strategy) {
                    ForEach(Strategy.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                previewLabel
                HStack {
                    Spacer()
                    Button("Cancel", action: dismiss).keyboardShortcut(.cancelAction)
                    Button(actionTitle) { start() }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(selected == nil || store.busy.contains(repo.id))
                }
            }
            .padding(Spacing.l)
        }
        .frame(width: 520, height: 560)
        .task { branches = (try? await git.branches()) ?? BranchList() }
        .task(id: selected) { await check() }
    }

    private var actionTitle: String {
        guard let selected else { return "Merge" }
        switch strategy {
        case .merge: return "Merge \(selected) into \(current)"
        case .squash: return "Squash \(selected) into \(current)"
        case .rebase: return "Rebase \(current) onto \(selected)"
        }
    }

    @ViewBuilder private var previewLabel: some View {
        if selected == nil {
            Label("Choose a branch to merge.", systemImage: "info.circle").foregroundStyle(.secondary)
        } else if isChecking {
            HStack(spacing: Spacing.s) { ProgressView().controlSize(.small); Text("Checking for conflicts…").foregroundStyle(.secondary) }
        } else if incoming == 0 {
            Label("\(current) is already up to date with \(selected ?? "").", systemImage: "checkmark.circle").foregroundStyle(.secondary)
        } else if let preview, !preview.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label("\(preview.count) conflicted file\(preview.count == 1 ? "" : "s") — you'll resolve \(preview.count == 1 ? "it" : "them") next.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.conflict)
                Text(preview.prefix(4).joined(separator: ", ") + (preview.count > 4 ? " …" : ""))
                    .appFont(.caption, design: .monospaced).foregroundStyle(.secondary).lineLimit(2)
            }
        } else if preview != nil {
            Label("No conflicts — \(incoming) commit\(incoming == 1 ? "" : "s") will be merged.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.added)
        } else {
            Label("\(incoming) commit\(incoming == 1 ? "" : "s") will be merged (conflict preview needs git 2.38+).", systemImage: "info.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func check() async {
        guard let selected else { return }
        isChecking = true
        defer { isChecking = false }
        incoming = await git.aheadBehind(selected).behind
        if incoming > 0 { preview = await git.mergePreview(selected) } else { preview = [] }
    }

    private func start() {
        guard let branch = selected else { return }
        let strategy = self.strategy, current = self.current
        dismiss()
        Task {
            let ok: Bool
            switch strategy {
            case .merge:
                ok = await store.perform(repo.id, "merge", success: "Merged \(branch) into \(current)") { try await $0.merge(branch) }
            case .squash:
                ok = await store.perform(repo.id, "squash merge", success: "Squashed \(branch) — review and commit the staged changes") {
                    try await $0.mergeSquash(branch)
                }
                if ok { RepoActions.show(.changes) }
            case .rebase:
                ok = await store.perform(repo.id, "rebase", success: "Rebased onto \(branch)") { try await $0.rebase(onto: branch) }
            }
            if !ok, (store.statuses[repo.id]?.conflicts ?? 0) > 0 {
                store.failure = nil
                RepoActions.post(.showConflicts)
            }
        }
    }
}

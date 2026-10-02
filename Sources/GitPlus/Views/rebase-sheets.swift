import SwiftUI

/// Edit the message of any commit on the current branch.
struct RewordSheet: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let commit: Commit
    let dismiss: () -> Void
    @State private var message = ""
    @State private var isPushed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Edit message of \(commit.shortHash)").font(.title3.weight(.semibold))
            TextEditor(text: $message)
                .font(.mono)
                .scrollContentBackground(.hidden)
                .padding(Spacing.xs)
                .background(RoundedRectangle(cornerRadius: Radius.s).fill(Theme.contextLine))
                .overlay(RoundedRectangle(cornerRadius: Radius.s).stroke(Theme.separator))
                .frame(height: 160)
            if isPushed {
                Label("This commit is already pushed; you'll need to force push afterwards.", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(Theme.modified)
            }
            Text("Commits after it are rewritten too (new SHAs).").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", action: dismiss).keyboardShortcut(.cancelAction)
                Button("Save") {
                    let text = message.trimmingCharacters(in: .whitespacesAndNewlines), c = commit
                    dismiss()
                    Task { await store.perform(repo.id, "edit message", success: "Updated message of \(c.shortHash)") { try await $0.reword(c, message: text) } }
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Spacing.l)
        .frame(width: 520)
        .task {
            let git = GitService(repo: repo.url)
            message = ((try? await git.commitMessage(commit.hash)) ?? commit.subject).trimmingCharacters(in: .whitespacesAndNewlines)
            isPushed = await isOnUpstream(git)
        }
    }

    private func isOnUpstream(_ git: GitService) async -> Bool {
        guard store.statuses[repo.id]?.upstream != nil else { return false }
        return (try? await git.git(["merge-base", "--is-ancestor", commit.hash, "@{upstream}"])) != nil
    }
}

/// Interactive rebase of the commits from `from` up to HEAD: reorder by dragging, choose
/// pick / reword / squash / fixup / drop per commit.
struct InteractiveRebaseSheet: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let from: Commit
    let dismiss: () -> Void

    @State private var steps: [RebaseStep] = []
    @State private var hasMerges = false
    @State private var pushedCount = 0
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Interactive Rebase").font(.title3.weight(.semibold))
                Text("\(steps.count) commit\(steps.count == 1 ? "" : "s") from \(from.shortHash) to HEAD, oldest first. Drag to reorder.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(Spacing.l)
            Divider()
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if hasMerges {
                ContentUnavailableView("Merge Commits in Range", systemImage: "arrow.triangle.merge",
                                       description: Text("Rewriting history across merge commits would flatten them. Pick a commit after the last merge."))
            } else {
                List {
                    ForEach($steps) { $step in row($step) }
                        .onMove { from, to in steps.move(fromOffsets: from, toOffset: to) }
                }
                .listStyle(.inset)
            }
            Divider()
            footer.padding(Spacing.l)
        }
        .frame(width: 680, height: 560)
        .task { await load() }
    }

    private func row(_ step: Binding<RebaseStep>) -> some View {
        let s = step.wrappedValue
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                Picker("", selection: step.action) {
                    ForEach(RebaseStep.Action.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 100)
                Text(s.commit.shortHash).font(.mono).foregroundStyle(.secondary)
                Text(s.commit.subject).lineLimit(1)
                    .strikethrough(s.action == .drop)
                    .foregroundStyle(s.action == .drop ? .secondary : .primary)
                Spacer()
                Text(s.commit.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if s.action == .reword {
                TextField("New message", text: step.message, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .padding(.leading, 28)
            }
            if s.action.meldsIntoPrevious {
                Text(s.action == .squash ? "Combined into the commit above (messages are kept)." : "Combined into the commit above (its message is discarded).")
                    .font(.caption).foregroundStyle(.secondary).padding(.leading, 28)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }

    private var footer: some View {
        let problem = RebaseStep.problem(steps)
        return VStack(alignment: .leading, spacing: Spacing.s) {
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(Theme.deleted)
            } else if pushedCount > 0 {
                Label("\(pushedCount) of these commits are already pushed — you'll need to force push afterwards.", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(Theme.modified)
            }
            HStack {
                Text("Conflicts stop the rebase; resolve them and continue from the banner.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: dismiss).keyboardShortcut(.cancelAction)
                Button("Start Rebase") { start() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil || hasMerges || isLoading || store.busy.contains(repo.id))
            }
        }
    }

    private func load() async {
        let git = GitService(repo: repo.url)
        let base = from.parents.first
        let commits = (try? await git.log(ref: base.map { "\($0)..HEAD" } ?? "HEAD", limit: 2000)) ?? []
        hasMerges = commits.contains { $0.parents.count > 1 }
        steps = commits.reversed().map { RebaseStep(commit: $0, message: $0.subject) }
        if store.statuses[repo.id]?.upstream != nil {
            let unpushed = (try? await git.log(ref: "@{upstream}..HEAD", limit: 2000)) ?? []
            let unpushedSet = Set(unpushed.map(\.hash))
            pushedCount = steps.filter { !unpushedSet.contains($0.commit.hash) }.count
        }
        isLoading = false
    }

    private func start() {
        let steps = self.steps, base = from.parents.first
        dismiss()
        Task {
            await store.perform(repo.id, "interactive rebase", success: "Rebase completed") { try await $0.rebaseInteractive(base: base, steps: steps) }
        }
    }
}

import SwiftUI

/// Summary / description / amend + commit button (⌘↩) with "Commit & Push", Conventional Commit
/// prefixes and co-authors.
struct CommitBoxView: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let stagedCount: Int
    let hasChanges: Bool

    @State private var summary = ""
    @State private var details = ""
    @State private var amend = false
    @State private var recentAuthors: [Author] = []

    struct Author: Hashable {
        let name: String
        let email: String
    }

    private static let prefixes = ["feat", "fix", "docs", "refactor", "perf", "test", "build", "ci", "chore", "style", "revert"]

    private var status: RepoStatus? { store.statuses[repo.id] }
    private var branch: String { status?.branch ?? "HEAD" }
    /// Nothing staged → the button stages everything first.
    private var stagesAll: Bool { stagedCount == 0 && !amend }
    private var canCommit: Bool {
        !summary.trimmingCharacters(in: .whitespaces).isEmpty && (amend || hasChanges) && !store.busy.contains(repo.id)
            && (status?.conflicts ?? 0) == 0
    }
    /// Amending a commit that is already on the remote needs a force push afterwards.
    private var lastCommitPushed: Bool { amend && status?.upstream != nil && (status?.ahead ?? 0) == 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.xs) {
                TextField("Summary (required)", text: $summary)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.medium))
                Menu {
                    ForEach(Self.prefixes, id: \.self) { p in
                        Button("\(p):") { applyPrefix(p) }
                    }
                } label: {
                    Image(systemName: "tag")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Conventional Commit prefix")
            }
            .padding(Spacing.s)
            .background(field)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $details)
                    .font(.callout)
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.xs)
                if details.isEmpty {
                    Text("Description").foregroundStyle(.tertiary).padding(.horizontal, 9).padding(.vertical, Spacing.xs).allowsHitTesting(false)
                }
            }
            .frame(height: 64)
            .background(field)
            HStack(spacing: Spacing.s) {
                Toggle("Amend", isOn: $amend).toggleStyle(.checkbox).font(.callout)
                    .help("Amend the last commit")
                Menu {
                    if recentAuthors.isEmpty { Text("No other authors in recent history") }
                    ForEach(recentAuthors, id: \.self) { author in
                        Button("\(author.name) <\(author.email)>") { addCoAuthor(author) }
                    }
                } label: {
                    Label("Co-author", systemImage: "person.badge.plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .font(.callout)
                Spacer()
                let count = summary.count
                if count > 50 {
                    Text("\(count)/72").font(.caption.monospacedDigit()).foregroundStyle(count > 72 ? Theme.deleted : Theme.modified)
                        .help("Keep the summary under 50 characters (72 at most)")
                }
            }
            if lastCommitPushed {
                Label("The last commit is already pushed — amending requires a force push.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Theme.modified)
            }
            HStack(spacing: Spacing.xs) {
                Button { commit(push: false) } label: {
                    Text(buttonTitle).font(.body.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .help("⌘↩")
                Menu {
                    Button(pushTitle) { commit(push: true) }
                        .disabled(status?.remote == nil)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("\(pushTitle) (⌘⇧↩)")
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!canCommit)
            .background {
                // Carries the ⌘⇧↩ shortcut for "Commit & Push".
                Button("") { commit(push: true) }
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .disabled(!canCommit || status?.remote == nil)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
        .padding(Spacing.m)
        .task { await loadAuthors() }
        .onChange(of: amend) { _, on in
            guard on, summary.isEmpty else { return }
            Task {
                let last = await GitService(repo: repo.url).lastCommitMessage()
                summary = last.summary
                details = last.description
            }
        }
    }

    private var pushTitle: String {
        status?.upstream == nil ? "Commit & Publish" : amend ? "Commit & Force Push" : "Commit & Push"
    }

    private var field: some View {
        RoundedRectangle(cornerRadius: Radius.s).fill(Theme.contextLine)
            .overlay(RoundedRectangle(cornerRadius: Radius.s).stroke(Theme.separator))
    }

    private var buttonTitle: AttributedString {
        let text = amend ? "Amend last commit on **\(branch)**"
            : stagesAll ? "Stage all & commit to **\(branch)**"
            : "Commit \(stagedCount) file\(stagedCount == 1 ? "" : "s") to **\(branch)**"
        return (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    /// Replaces an existing `type:` / `type(scope):` prefix or adds one.
    private func applyPrefix(_ prefix: String) {
        var rest = summary
        if let colon = rest.firstIndex(of: ":"), Self.prefixes.contains(where: { p in [":", "(", "!"].contains { rest.hasPrefix(p + $0) } }), rest.distance(from: rest.startIndex, to: colon) < 20 {
            rest = String(rest[rest.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        summary = "\(prefix): \(rest)"
    }

    private func addCoAuthor(_ author: Author) {
        let trailer = "Co-authored-by: \(author.name) <\(author.email)>"
        guard !details.contains(trailer) else { return }
        let body = details.trimmingCharacters(in: .whitespacesAndNewlines)
        details = body.isEmpty ? trailer : body + (body.contains("Co-authored-by:") ? "\n" : "\n\n") + trailer
    }

    private func loadAuthors() async {
        let git = GitService(repo: repo.url)
        let me = ((try? await git.git(["config", "user.email"])) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let log = (try? await git.log(allRefs: true, limit: 400)) ?? []
        var seen = Set<String>()
        let authors = log.compactMap { c -> Author? in
            let key = c.email.lowercased()
            guard key != me.lowercased(), seen.insert(key).inserted else { return nil }
            return Author(name: c.author, email: c.email)
        }
        recentAuthors = Array(authors.prefix(15))
    }

    private func commit(push: Bool) {
        guard canCommit else { return }
        let s = summary.trimmingCharacters(in: .whitespaces), d = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let stageFirst = stagesAll, isAmend = amend
        let needsUpstream = status?.upstream == nil
        let id = repo.id, branch = branch
        let undo: (@Sendable (GitService) async throws -> Void)? = isAmend ? nil : { git in try await git.undoLastCommit() }
        Task {
            let ok = await store.perform(id, "commit", success: push ? nil : isAmend ? "Amended last commit" : "Committed to \(branch)",
                                         undo: undo) {
                if stageFirst { try await $0.stageAll() }
                try await $0.commit(summary: s, description: d, amend: isAmend)
            }
            guard ok else { return }
            summary = ""; details = ""; amend = false
            if push { await store.push(id, force: isAmend && !needsUpstream) }
        }
    }
}

/// "Stash changes" sheet.
struct StashSheet: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let repo: RepoEntry
    @State private var message = ""
    @State private var includeUntracked = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stash Changes").font(.headline)
            TextField("Message (optional)", text: $message).textFieldStyle(.roundedBorder)
            Toggle("Include untracked files", isOn: $includeUntracked)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Stash") {
                    let m = message, u = includeUntracked
                    dismiss()
                    Task { await store.perform(repo.id, "stash", success: "Changes stashed") { try await $0.stash(message: m, includeUntracked: u) } }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

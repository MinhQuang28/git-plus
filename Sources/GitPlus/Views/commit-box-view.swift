import SwiftUI

/// Summary / description / amend + commit button (⌘↩) with "Commit & Push", Conventional Commit
/// prefixes and co-authors.
struct CommitBoxView: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let stagedCount: Int
    let hasChanges: Bool

    @AppStorage(CommitDefaults.summaryKey) private var defaultSummary = ""
    @AppStorage(CommitDefaults.descriptionKey) private var defaultDetails = ""
    @State private var recentAuthors: [Author] = []
    @FocusState private var summaryFocused: Bool
    @FocusState private var detailsFocused: Bool
    @Environment(\.uiTextScale) private var scale

    /// Lives in the store, so switching tab or repository doesn't throw the message away.
    private var draft: CommitDraft {
        get { store.draft(for: repo.id) }
        nonmutating set { store.commitDrafts[repo.id] = newValue }
    }
    private var summary: String { get { draft.summary } nonmutating set { draft.summary = newValue } }
    private var details: String { get { draft.details } nonmutating set { draft.details = newValue } }
    private var amend: Bool { get { draft.amend } nonmutating set { draft.amend = newValue } }
    private func binding<T>(_ path: WritableKeyPath<CommitDraft, T>) -> Binding<T> {
        Binding(get: { draft[keyPath: path] }, set: { draft[keyPath: path] = $0 })
    }

    struct Author: Hashable {
        let name: String
        let email: String
    }

    private static let prefixes = ["feat", "fix", "docs", "refactor", "perf", "test", "build", "ci", "chore", "style", "revert"]

    private var status: RepoStatus? { store.statuses[repo.id] }
    private var branch: String { status?.branch ?? "HEAD" }
    /// Nothing staged → the button stages everything first.
    private var stagesAll: Bool { stagedCount == 0 && !amend }
    private var canCommit: Bool { store.canCommit(repo.id) }
    /// Commit (incl. hooks) running: the button shows progress and can't be pressed twice.
    private var isCommitting: Bool { store.busyLabels[repo.id] == "commit" }
    /// Amending a commit that is already on the remote needs a force push afterwards.
    private var lastCommitPushed: Bool { amend && status?.upstream != nil && (status?.ahead ?? 0) == 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.xs) {
                TextField(store.isWritingMessage(repo.id) ? "Writing message…" : "Summary (required)", text: binding(\.summary))
                    .textFieldStyle(.plain)
                    .focused($summaryFocused)
                    .appFont(.body, weight: .medium)
                if !AISettings.isDisabled(repoPath: repo.path) {
                    AICommitMessageButton(repoID: repo.id, isAvailable: !amend && hasChanges, amend: amend)
                }
                Menu {
                    ForEach(Self.prefixes, id: \.self) { p in
                        Button("\(p):") { applyPrefix(p) }
                    }
                } label: {
                    Label("Commit type prefix", systemImage: "tag").labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Conventional Commit prefix")
            }
            .padding(Spacing.s)
            .background(field)
            ZStack(alignment: .topLeading) {
                TextEditor(text: binding(\.details))
                    .appFont(.callout)
                    .focused($detailsFocused)
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.xs)
                if details.isEmpty {
                    Text("Description").foregroundStyle(.tertiary).padding(.horizontal, 9).padding(.vertical, Spacing.xs).allowsHitTesting(false)
                }
            }
            // One line until it's used, so the file list keeps the space.
            .frame(height: (detailsFocused || !details.isEmpty ? 64 : 30) * scale)
            .animation(.easeOut(duration: 0.15), value: detailsFocused)
            .background(field)
            HStack(spacing: Spacing.s) {
                Toggle("Amend", isOn: binding(\.amend)).toggleStyle(.checkbox).appFont(.callout)
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
                .appFont(.callout)
                Spacer()
                let count = summary.count
                if count > 50 {
                    Text("\(count)/72").appFont(.caption, monospacedDigit: true).foregroundStyle(count > 72 ? Theme.deleted : Theme.modified)
                        .help("Keep the summary under 50 characters (72 at most)")
                }
            }
            if lastCommitPushed {
                Label("The last commit is already pushed — amending requires a force push.", systemImage: "exclamationmark.triangle")
                    .appFont(.caption).foregroundStyle(Theme.modified)
            }
            HStack(spacing: Spacing.xs) {
                Button { commit(push: false) } label: {
                    HStack(spacing: Spacing.xs) {
                        if isCommitting { ProgressView().controlSize(.small) }
                        Text(isCommitting ? AttributedString("Committing…") : buttonTitle).appFont(.body, weight: .semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .help(disabledReason ?? "Commit (⌘↩)")
                Menu {
                    Button(pushTitle) { commit(push: true) }
                        .disabled(status?.remote == nil)
                } label: {
                    Label("More commit options", systemImage: "chevron.down").labelStyle(.iconOnly)
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("\(pushTitle) (⌘⇧↩)")
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!canCommit)
        }
        .padding(Spacing.m)
        .task { await loadAuthors() }
        .onAppear(perform: takeFocusRequest)
        .onChange(of: store.focusCommitMessage) { takeFocusRequest() }
        .onChange(of: amend) { _, on in
            // Load the last message unless the user has typed something beyond the defaults.
            guard on, isUntouched else { return }
            Task {
                let last = await GitService(repo: repo.url).lastCommitMessage()
                summary = last.summary
                details = last.description
            }
        }
    }

    private func takeFocusRequest() {
        guard store.focusCommitMessage == repo.id else { return }
        store.focusCommitMessage = nil
        DispatchQueue.main.async { summaryFocused = true }   // after a tab switch has laid the field out
    }

    /// Why the commit button is greyed out (shown as its tooltip).
    private var disabledReason: String? {
        if isCommitting { return "Committing… (running hooks)" }
        if (status?.conflicts ?? 0) > 0 { return "Resolve conflicts before committing" }
        if !amend && !hasChanges { return "No changes to commit" }
        if summary.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter a summary to commit" }
        return nil
    }

    private var isUntouched: Bool {
        (summary.isEmpty || summary == defaultSummary) && (details.isEmpty || details == defaultDetails)
    }

    /// Back to the "Default commit message" from Settings → Commit.
    private func resetToDefaults() { store.commitDrafts[repo.id] = nil }

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

    /// Recent authors per repository path, reused for 10 minutes (the commit box is recreated on every
    /// tab or repository switch; re-reading 400 commits each time was wasted work).
    @MainActor private static var authorCache: [String: (date: Date, authors: [Author])] = [:]

    private func loadAuthors() async {
        if let cached = Self.authorCache[repo.path], Date().timeIntervalSince(cached.date) < 600 {
            recentAuthors = cached.authors
            return
        }
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
        Self.authorCache[repo.path] = (Date(), recentAuthors)
    }

    private func commit(push: Bool) { store.commit(repo.id, push: push) }
}

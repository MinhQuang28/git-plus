import AppKit
import SwiftUI

/// Actions that need extra input before running.
enum CommitRequest: Identifiable {
    case reset(Commit), branch(Commit), tag(Commit), cherryPick(Commit)

    var id: String {
        switch self {
        case .reset(let c): "reset" + c.hash
        case .branch(let c): "branch" + c.hash
        case .tag(let c): "tag" + c.hash
        case .cherryPick(let c): "pick" + c.hash
        }
    }
}

/// Right-click menu for a commit, modelled on GitHub Desktop.
struct CommitContextMenu: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let commit: Commit
    /// Reset is only offered for ancestors of HEAD that are not HEAD itself.
    let canReset: Bool
    let remote: RemoteInfo?
    let request: (CommitRequest) -> Void

    private var tags: [String] { commit.refs.filter { $0.hasPrefix("tag: ") }.map { String($0.dropFirst(5)) } }

    var body: some View {
        Button("Reset to Commit…") { request(.reset(commit)) }.disabled(!canReset)
        Button("Checkout Commit") { perform("checkout commit") { try await $0.checkout(commit: commit.hash) } }
        Button("Revert Changes in Commit") { perform("revert") { [commit] in try await $0.revert(commit) } }
        Divider()
        Button("Create Branch from Commit") { request(.branch(commit)) }
        Button("Create Tag…") { request(.tag(commit)) }
        Button("Cherry-pick Commit…") { request(.cherryPick(commit)) }
        Divider()
        Button("Copy SHA") { copy(commit.hash) }
        Button("Copy Tag") { copy(tags.joined(separator: " ")) }.disabled(tags.isEmpty)
        if let remote, let url = remote.commitURL(commit.hash) {
            Button(remote.provider == .gitlab ? "View on GitLab" : remote.provider == .github ? "View on GitHub" : "View on \(remote.host)") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func perform(_ label: String, _ op: @escaping @Sendable (GitService) async throws -> Void) {
        Task { await store.perform(repo.id, label, op) }
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

/// Presents the confirmation / name prompt / branch chooser for a `CommitRequest`.
struct CommitRequestPresenter: ViewModifier {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    @Binding var request: CommitRequest?
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: isPresented(for: { if case .cherryPick = $0 { return false }; return true })) {
                if case .reset = request {
                    Button("Reset", role: .destructive) { run() }
                } else {
                    TextField("Name", text: $name)
                    Button("Create") { run() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button("Cancel", role: .cancel) { request = nil }
            } message: {
                if case .reset(let c) = request {
                    Text("Moves the current branch to \(c.shortHash). Changes from later commits are kept in your working directory.")
                }
            }
            .sheet(isPresented: isPresented(for: { if case .cherryPick = $0 { return true }; return false })) {
                if case .cherryPick(let c) = request {
                    CherryPickSheet(repo: repo, commit: c) { request = nil }
                }
            }
    }

    private var title: String {
        switch request {
        case .reset(let c): "Reset to \(c.shortHash)?"
        case .branch(let c): "Create branch from \(c.shortHash)"
        case .tag(let c): "Create tag on \(c.shortHash)"
        default: ""
        }
    }

    private func isPresented(for match: @escaping (CommitRequest) -> Bool) -> Binding<Bool> {
        Binding(get: { request.map(match) ?? false }, set: { if !$0 { request = nil } })
    }

    private func run() {
        guard let req = request else { return }
        let n = name.trimmingCharacters(in: .whitespaces)
        request = nil
        name = ""
        Task {
            switch req {
            case .reset(let c): await store.perform(repo.id, "reset") { try await $0.reset(to: c.hash) }
            case .branch(let c): await store.perform(repo.id, "create branch") { try await $0.createBranch(n, at: c.hash) }
            case .tag(let c): await store.perform(repo.id, "create tag") { try await $0.createTag(n, at: c.hash) }
            case .cherryPick: break
            }
        }
    }
}

/// Choose the target branch for a cherry-pick.
struct CherryPickSheet: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let commit: Commit
    let dismiss: () -> Void
    @State private var branches = BranchList()
    @State private var target: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cherry-pick \(commit.shortHash) onto…").font(.headline)
            Text(commit.subject).foregroundStyle(.secondary).lineLimit(1)
            List(branches.local.filter { $0 != branches.current }, id: \.self, selection: $target) { Text($0) }
                .frame(height: 260)
            HStack {
                Spacer()
                Button("Cancel", action: dismiss).keyboardShortcut(.cancelAction)
                Button("Cherry-pick") {
                    guard let target else { return }
                    let hash = commit.hash
                    dismiss()
                    Task { await store.perform(repo.id, "cherry-pick") { try await $0.cherryPick(hash, onto: target) } }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(target == nil)
            }
        }
        .padding(16)
        .frame(width: 420)
        .task { branches = (try? await GitService(repo: repo.url).branches()) ?? BranchList() }
    }
}

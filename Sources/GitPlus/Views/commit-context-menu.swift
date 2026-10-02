import AppKit
import SwiftUI

/// Actions that need extra input before running.
enum CommitRequest: Identifiable {
    case reset(Commit, ResetMode), branch(Commit), tag(Commit), cherryPick(Commit)

    var id: String {
        switch self {
        case .reset(let c, let m): "reset\(m.rawValue)" + c.hash
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
        Menu("Reset Current Branch to Here") {
            ForEach(ResetMode.allCases, id: \.self) { mode in
                Button("\(mode.rawValue.capitalized) — \(mode.summary)") { request(.reset(commit, mode)) }
            }
        }
        .disabled(!canReset)
        Button("Checkout Commit (detached)") { perform("checkout commit", "Checked out \(commit.shortHash)") { try await $0.checkout(commit: commit.hash) } }
        Button("Revert Changes in Commit") { perform("revert", "Reverted \(commit.shortHash)") { [commit] in try await $0.revert(commit) } }
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

    private func perform(_ label: String, _ success: String, _ op: @escaping @Sendable (GitService) async throws -> Void) {
        Task { await store.perform(repo.id, label, success: success, op) }
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
                if case .reset(_, let mode) = request {
                    Button("\(mode.rawValue.capitalized) Reset", role: mode == .hard ? .destructive : nil) { run() }
                } else {
                    TextField("Name", text: $name)
                    Button("Create") { run() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button("Cancel", role: .cancel) { request = nil }
            } message: {
                if case .reset(let c, let mode) = request {
                    Text("Moves the current branch to \(c.shortHash). \(mode.summary).")
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
        case .reset(let c, let mode): "\(mode.rawValue.capitalized) reset to \(c.shortHash)?"
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
            case .reset(let c, let mode):
                await store.perform(repo.id, "reset", success: "Reset to \(c.shortHash)") { try await $0.reset(to: c.hash, mode: mode) }
            case .branch(let c):
                await store.perform(repo.id, "create branch", success: "Created branch \(n)") { try await $0.createBranch(n, at: c.hash) }
            case .tag(let c):
                await store.perform(repo.id, "create tag", success: "Created tag \(n)") { try await $0.createTag(n, at: c.hash) }
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
                    Task { await store.perform(repo.id, "cherry-pick", success: "Cherry-picked onto \(target)") { try await $0.cherryPick(hash, onto: target) } }
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

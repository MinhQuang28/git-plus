import AppKit
import SwiftUI

extension Notification.Name {
    static let showRepositoryPicker = Notification.Name("gitplus.showRepositoryPicker")
    static let showBranchPicker = Notification.Name("gitplus.showBranchPicker")
    static let showCommandPalette = Notification.Name("gitplus.showCommandPalette")
    static let showClone = Notification.Name("gitplus.showClone")
    static let showRemotes = Notification.Name("gitplus.showRemotes")
    static let showMerge = Notification.Name("gitplus.showMerge")
    static let showConflicts = Notification.Name("gitplus.showConflicts")
}

/// Actions shared by the menu bar, keyboard shortcuts and the command palette.
/// They act on the repository shown in the window (persisted in `selection`).
@MainActor
enum RepoActions {
    static var currentRepoID: UUID? {
        if case .repo(let id) = SidebarSelection(rawValue: UserDefaults.standard.string(forKey: "selection") ?? "") { return id }
        return nil
    }

    static func select(_ selection: SidebarSelection) { UserDefaults.standard.set(selection.rawValue, forKey: "selection") }
    static func show(_ tab: RepoTab) { UserDefaults.standard.set(tab.rawValue, forKey: "repoTab") }
    static func post(_ name: Notification.Name) { NotificationCenter.default.post(name: name, object: nil) }

    static func open(_ repo: RepoEntry, editor: Bool) {
        let defaults = UserDefaults.standard
        let app = editor
            ? ExternalAppLauncher.preferredEditor(defaults.string(forKey: "preferredEditor") ?? "")
            : ExternalAppLauncher.preferredTerminal(defaults.string(forKey: "preferredTerminal") ?? "")
        if let app { app.open(repo.url) } else { NSWorkspace.shared.activateFileViewerSelecting([repo.url]) }
    }

    static func reveal(_ repo: RepoEntry) { NSWorkspace.shared.activateFileViewerSelecting([repo.url]) }

    static func addRepositories(_ store: WorkspaceStore) {
        let urls = FolderPicker.choose()
        Task { await store.add(folders: urls, to: nil) }
    }

    /// Choose (or create) a folder and run `git init` in it.
    static func newRepository(_ store: WorkspaceStore) {
        let panel = NSSavePanel()
        panel.title = "New Repository"
        panel.prompt = "Create"
        panel.nameFieldLabel = "Repository name:"
        panel.nameFieldStringValue = "new-repository"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            if let id = await store.initRepository(at: url, groupID: nil) { select(.repo(id)); show(.changes) }
        }
    }

    static func undoLastCommit(_ store: WorkspaceStore, _ id: UUID) {
        Task { await store.perform(id, "undo commit", success: "Undid last commit — its changes are staged") { try await $0.undoLastCommit() } }
    }
}

/// Menu bar commands + keyboard shortcuts.
struct AppCommands: Commands {
    let store: WorkspaceStore

    private var currentRepoID: UUID? { RepoActions.currentRepoID }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Repository…") { RepoActions.newRepository(store) }
                .keyboardShortcut("n")
            Button("Add Repositories…") { RepoActions.addRepositories(store) }
                .keyboardShortcut("o")
            Button("Clone Repository…") { RepoActions.post(.showClone) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Auto-Group by Remote") { Task { await store.autoGroupByRemote() } }
        }
        CommandGroup(after: .sidebar) {
            Button("Command Palette…") { RepoActions.post(.showCommandPalette) }
                .keyboardShortcut("k")
        }
        CommandMenu("Repository") {
            Button("Show Repository List") { RepoActions.post(.showRepositoryPicker) }
                .keyboardShortcut("t")
            Button("Show Branch List") { RepoActions.post(.showBranchPicker) }
                .keyboardShortcut("b")
            Button("Merge into Current Branch…") { RepoActions.post(.showMerge) }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Button("Resolve Conflicts…") { RepoActions.post(.showConflicts) }
            Divider()
            Button("Fetch") { if let id = currentRepoID { Task { await store.fetch([id]) } } }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Pull") { if let id = currentRepoID { Task { await store.pull([id]) } } }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Menu("Pull With") {
                ForEach(PullMode.allCases, id: \.self) { mode in
                    Button(mode.title) { if let id = currentRepoID { Task { await store.pull([id], mode: mode) } } }
                }
            }
            Button("Push") { if let id = currentRepoID { Task { await store.push(id) } } }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("Force Push (with Lease)…") { if let id = currentRepoID { confirmForcePush(id) } }
                .keyboardShortcut("p", modifiers: [.command, .shift, .option])
            Divider()
            Button("Undo Last Commit") { if let id = currentRepoID { RepoActions.undoLastCommit(store, id) } }
            Button("Remotes…") { RepoActions.post(.showRemotes) }
            Divider()
            Button("Open in Editor") { if let repo = currentRepo { RepoActions.open(repo, editor: true) } }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Open in Terminal") { if let repo = currentRepo { RepoActions.open(repo, editor: false) } }
                .keyboardShortcut("`", modifiers: .control)
            Button("Reveal in Finder") { if let repo = currentRepo { RepoActions.reveal(repo) } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Divider()
            Button("Refresh All Status") { Task { await store.refreshStatus() } }
                .keyboardShortcut("r")
        }
        CommandGroup(before: .toolbar) {
            Button("Changes") { RepoActions.show(.changes) }.keyboardShortcut("1")
            Button("History") { RepoActions.show(.history) }.keyboardShortcut("2")
            Button("Stashes") { RepoActions.show(.stashes) }.keyboardShortcut("3")
            Divider()
            Button("Larger Diff Text") { adjustFont(+1) }.keyboardShortcut("=")
            Button("Smaller Diff Text") { adjustFont(-1) }.keyboardShortcut("-")
            Button("Default Diff Text Size") { UserDefaults.standard.set(12.5, forKey: "diffFontSize") }.keyboardShortcut("0")
            Divider()
        }
    }

    private var currentRepo: RepoEntry? { currentRepoID.flatMap { store.repo($0) } }

    private func adjustFont(_ delta: Double) {
        let current = UserDefaults.standard.object(forKey: "diffFontSize") as? Double ?? 12.5
        UserDefaults.standard.set(min(max(current + delta, 9), 22), forKey: "diffFontSize")
    }

    @MainActor private func confirmForcePush(_ id: UUID) { ForcePushConfirmation.run(store, id) }
}

/// "Force push?" confirmation, shared by the menu, the sync button and the command palette.
@MainActor
enum ForcePushConfirmation {
    static func run(_ store: WorkspaceStore, _ id: UUID) {
        let branch = store.statuses[id]?.branch ?? "this branch"
        let alert = NSAlert()
        alert.messageText = "Force push \(branch)?"
        alert.informativeText = "This replaces the remote branch with your local one. Git Plus uses --force-with-lease, "
            + "so the push is refused if someone else pushed commits you haven't fetched."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Force Push")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await store.push(id, force: true) }
    }
}

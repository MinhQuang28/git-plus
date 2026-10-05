import AppKit
import SwiftUI

/// "Changes" menu: the review → stage → commit → push loop from the keyboard, with real disabled states.
/// Shortcuts follow GitHub Desktop where it has one (⌘⇧S stash, ⌘⇧⌫ discard all).
struct ChangesCommands: Commands {
    let store: WorkspaceStore
    /// Same key `RepoActions` uses; @AppStorage keeps the enabled states live.
    @AppStorage("selection") private var selectionRaw = ""

    private var repoID: UUID? {
        if case .repo(let id) = SidebarSelection(rawValue: selectionRaw), store.repo(id) != nil { return id }
        return nil
    }

    var body: some Commands {
        CommandMenu("Changes") {
            let tree = repoID.flatMap { store.trees[$0] }
            let hasRemote = repoID.flatMap { store.statuses[$0]?.remote } != nil
            Button("Commit") { run { RepoActions.show(.changes); store.commit($0, push: false) } }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!(repoID.map(store.canCommit) ?? false))
            Button("Commit & Push") { run { RepoActions.show(.changes); store.commit($0, push: true) } }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(!(repoID.map(store.canCommit) ?? false) || !hasRemote)
            Button("Write Commit Message with AI") { run { RepoActions.show(.changes); store.generateCommitMessage($0) } }
                .keyboardShortcut("g", modifiers: [.command, .option])
                .disabled(repoID == nil || (tree?.isEmpty ?? true) || repoID.map(store.isWritingMessage) == true)
            Button("Go to Commit Message") { run { RepoActions.show(.changes); store.focusCommitMessage = $0 } }
                .keyboardShortcut("l")
                .disabled(repoID == nil)
            Divider()
            Button("Stage All") { run { id in Task { await store.perform(id, "stage", success: "Staged all changes") { try await $0.stageAll() } } } }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(tree?.unstaged.isEmpty ?? true)
            Button("Unstage All") { run { id in Task { await store.perform(id, "unstage", success: "Unstaged all changes") { try await $0.unstageAll() } } } }
                .keyboardShortcut("u", modifiers: [.command, .option])
                .disabled(tree?.staged.isEmpty ?? true)
            Divider()
            Button("Stash All Changes") { run(stashAll) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(tree?.isEmpty ?? true)
            Button("Discard All Changes…") { run(confirmDiscardAll) }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled((tree?.isEmpty ?? true) || !(tree?.conflicted.isEmpty ?? true))
            Divider()
            Button("Undo Last Commit") { run { RepoActions.undoLastCommit(store, $0) } }
                .keyboardShortcut("z", modifiers: [.command, .option])
                .disabled(repoID == nil)
        }
    }

    private func run(_ action: (UUID) -> Void) { if let repoID { action(repoID) } }

    private func stashAll(_ id: UUID) {
        Task {
            await store.perform(id, "stash", success: "Stashed all changes", undo: { try await $0.popLatestStash() }) {
                try await $0.stash(message: "", includeUntracked: true)
            }
        }
    }

    @MainActor private func confirmDiscardAll(_ id: UUID) {
        let alert = NSAlert()
        alert.messageText = "Discard all changes?"
        alert.informativeText = "Every change, including untracked files, is set aside in a stash, so you can still undo this."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Discard All Changes")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            await store.perform(id, "discard all", success: "Discarded all changes", undo: { try await $0.popLatestStash() }) {
                try await $0.discardAll()
            }
        }
    }
}

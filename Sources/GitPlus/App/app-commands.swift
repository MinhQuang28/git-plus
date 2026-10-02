import AppKit
import SwiftUI

extension Notification.Name {
    static let showRepositoryPicker = Notification.Name("gitplus.showRepositoryPicker")
    static let showBranchPicker = Notification.Name("gitplus.showBranchPicker")
}

/// Menu bar commands + keyboard shortcuts. They act on the repository shown in the window
/// (persisted in `selection`) and drive view state through the same `@AppStorage` keys.
struct AppCommands: Commands {
    let store: WorkspaceStore

    private var currentRepoID: UUID? {
        if case .repo(let id) = SidebarSelection(rawValue: UserDefaults.standard.string(forKey: "selection") ?? "") { return id }
        return nil
    }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Add Repositories…") {
                let urls = FolderPicker.choose()
                Task { await store.add(folders: urls, to: nil) }
            }
            .keyboardShortcut("o")
            Button("Auto-Group by Remote") { Task { await store.autoGroupByRemote() } }
        }
        CommandMenu("Repository") {
            Button("Show Repository List") { NotificationCenter.default.post(name: .showRepositoryPicker, object: nil) }
                .keyboardShortcut("t")
            Button("Show Branch List") { NotificationCenter.default.post(name: .showBranchPicker, object: nil) }
                .keyboardShortcut("b")
            Divider()
            Button("Fetch") { if let id = currentRepoID { Task { await store.fetch([id]) } } }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Pull") { if let id = currentRepoID { Task { await store.pull([id]) } } }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Push") { if let id = currentRepoID { Task { await store.push(id) } } }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Divider()
            Button("Open in Editor") { open(editor: true) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Open in Terminal") { open(editor: false) }
                .keyboardShortcut("`", modifiers: .control)
            Button("Reveal in Finder") {
                if let id = currentRepoID, let repo = store.repo(id) { NSWorkspace.shared.activateFileViewerSelecting([repo.url]) }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            Divider()
            Button("Refresh All Status") { Task { await store.refreshStatus() } }
                .keyboardShortcut("r")
        }
        CommandGroup(before: .toolbar) {
            Button("Changes") { UserDefaults.standard.set(0, forKey: "repoTab") }.keyboardShortcut("1")
            Button("History") { UserDefaults.standard.set(1, forKey: "repoTab") }.keyboardShortcut("2")
            Button("Stashes") { UserDefaults.standard.set(2, forKey: "repoTab") }.keyboardShortcut("3")
            Divider()
            Button("Larger Diff Text") { adjustFont(+1) }.keyboardShortcut("=")
            Button("Smaller Diff Text") { adjustFont(-1) }.keyboardShortcut("-")
            Button("Default Diff Text Size") { UserDefaults.standard.set(12.5, forKey: "diffFontSize") }.keyboardShortcut("0")
            Divider()
        }
    }

    private func adjustFont(_ delta: Double) {
        let current = UserDefaults.standard.object(forKey: "diffFontSize") as? Double ?? 12.5
        UserDefaults.standard.set(min(max(current + delta, 9), 22), forKey: "diffFontSize")
    }

    private func open(editor: Bool) {
        guard let id = currentRepoID, let repo = store.repo(id) else { return }
        let defaults = UserDefaults.standard
        let app = editor
            ? ExternalAppLauncher.preferredEditor(defaults.string(forKey: "preferredEditor") ?? "")
            : ExternalAppLauncher.preferredTerminal(defaults.string(forKey: "preferredTerminal") ?? "")
        app?.open(repo.url)
    }
}

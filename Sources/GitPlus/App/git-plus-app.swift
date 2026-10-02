import AppKit
import SwiftUI

@main
struct GitPlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = WorkspaceStore()

    var body: some Scene {
        WindowGroup("Git Plus") {
            ContentView()
                .environment(store)
                .frame(minWidth: 1000, minHeight: 600)
                .onAppear { appDelegate.store = store }
        }
        .commands { AppCommands(store: store) }

        Settings {
            SettingsView()
        }
    }
}

/// Handles `open -a "Git Plus" <folder>` from the terminal and runs as a regular app under `swift run`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor var store: WorkspaceStore? {
        didSet { flushPending() }
    }
    @MainActor private var pending: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false   // frees ⌘T for the repository list
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Also accept folder paths passed as plain arguments: `GitPlus ~/code/foo`.
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        Task { @MainActor in
            pending += args.map { URL(fileURLWithPath: $0) }
            flushPending()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            pending += urls
            flushPending()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @MainActor private func flushPending() {
        guard let store, !pending.isEmpty else { return }
        let urls = pending
        pending = []
        Task { await store.add(folders: urls, to: nil) }
    }
}

/// Opens a folder chooser for repositories or parent folders to scan.
@MainActor
enum FolderPicker {
    static func choose(message: String = "Choose repositories or a parent folder to scan") -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = message
        panel.prompt = "Add"
        return panel.runModal() == .OK ? panel.urls : []
    }
}

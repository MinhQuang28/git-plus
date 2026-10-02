import AppKit

/// Editors / terminals installed on this Mac that can open a repository folder.
struct ExternalApp: Identifiable, Hashable {
    var id: String { bundleID }
    let name: String
    let bundleID: String
    let isTerminal: Bool

    var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    var icon: NSImage? { url.map { NSWorkspace.shared.icon(forFile: $0.path) } }

    func open(_ folder: URL) {
        guard let url else { return }
        NSWorkspace.shared.open([folder], withApplicationAt: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

enum ExternalAppLauncher {
    private static let candidates: [ExternalApp] = [
        ExternalApp(name: "Visual Studio Code", bundleID: "com.microsoft.VSCode", isTerminal: false),
        ExternalApp(name: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92", isTerminal: false),
        ExternalApp(name: "Zed", bundleID: "dev.zed.Zed", isTerminal: false),
        ExternalApp(name: "Sublime Text", bundleID: "com.sublimetext.4", isTerminal: false),
        ExternalApp(name: "Xcode", bundleID: "com.apple.dt.Xcode", isTerminal: false),
        ExternalApp(name: "IntelliJ IDEA", bundleID: "com.jetbrains.intellij", isTerminal: false),
        ExternalApp(name: "WebStorm", bundleID: "com.jetbrains.WebStorm", isTerminal: false),
        ExternalApp(name: "Terminal", bundleID: "com.apple.Terminal", isTerminal: true),
        ExternalApp(name: "iTerm", bundleID: "com.googlecode.iterm2", isTerminal: true),
        ExternalApp(name: "Warp", bundleID: "dev.warp.Warp-Stable", isTerminal: true),
        ExternalApp(name: "Ghostty", bundleID: "com.mitchellh.ghostty", isTerminal: true),
    ]

    /// Installed apps, resolved once (Launch Services lookups are not free).
    static let installed: [ExternalApp] = candidates.filter { $0.url != nil }
    static var editors: [ExternalApp] { installed.filter { !$0.isTerminal } }
    static var terminals: [ExternalApp] { installed.filter(\.isTerminal) }

    /// Preferred editor (Settings), falling back to the first installed one.
    static func preferredEditor(_ bundleID: String) -> ExternalApp? {
        editors.first { $0.bundleID == bundleID } ?? editors.first
    }

    static func preferredTerminal(_ bundleID: String) -> ExternalApp? {
        terminals.first { $0.bundleID == bundleID } ?? terminals.first
    }
}

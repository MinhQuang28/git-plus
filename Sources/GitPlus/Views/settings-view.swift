import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView().tabItem { Label("General", systemImage: "gearshape") }
            CommitSettingsView().tabItem { Label("Commit", systemImage: "text.badge.checkmark") }
            AccountsSettingsView().tabItem { Label("Accounts", systemImage: "person.crop.circle") }
        }
        .frame(width: 540, height: 480)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("preferredEditor") private var preferredEditor = ""
    @AppStorage("preferredTerminal") private var preferredTerminal = ""
    @AppStorage("autoFetch") private var autoFetch = true
    @AppStorage("diffFontSize") private var fontSize = 12.5
    @AppStorage("syntaxHighlight") private var syntaxHighlight = true
    @AppStorage("diffMode") private var mode = DiffDisplayMode.unified
    @AppStorage("pullMode") private var pullMode = PullMode.fastForward.rawValue
    @AppStorage("diffIgnoreWhitespace") private var ignoreWhitespace = false
    @AppStorage("historyGraph") private var historyGraph = false
    @AppStorage(UITextScale.key) private var textScale = UITextScale.standard.rawValue

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Text size", selection: $textScale) {
                    ForEach(UITextScale.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Text("Applies to lists, the commit box and toolbars. ⌃⌘= / ⌃⌘- change it from anywhere; diff text has its own size below.")
                    .appFont(.caption).foregroundStyle(.secondary)
            }
            Section("Integrations") {
                Picker("Editor", selection: $preferredEditor) {
                    Text("Automatic").tag("")
                    ForEach(ExternalAppLauncher.editors) { Text($0.name).tag($0.bundleID) }
                }
                Picker("Terminal", selection: $preferredTerminal) {
                    Text("Automatic").tag("")
                    ForEach(ExternalAppLauncher.terminals) { Text($0.name).tag($0.bundleID) }
                }
            }
            Section("Sync") {
                Toggle("Fetch the open repository every 10 minutes", isOn: $autoFetch)
                Picker("Pull", selection: $pullMode) {
                    ForEach(PullMode.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                Text("Used by Pull and Pull All. When a branch has diverged, Git Plus always asks how to combine it.")
                    .appFont(.caption).foregroundStyle(.secondary)
            }
            Section("Diff") {
                Picker("Layout", selection: $mode) {
                    ForEach(DiffDisplayMode.allCases, id: \.self) { Text($0.rawValue) }
                }
                Toggle("Syntax highlighting", isOn: $syntaxHighlight)
                Toggle("Ignore whitespace changes", isOn: $ignoreWhitespace)
                Toggle("Show the commit graph in History", isOn: $historyGraph)
                LabeledContent("Diff text size") {
                    HStack {
                        Slider(value: $fontSize, in: 9...22, step: 0.5).frame(width: 180)
                        Text(String(format: "%.1f pt", fontSize)).monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Settings → shows `gh auth status` / `glab auth status`.
struct AccountsSettingsView: View {
    @State private var results: [String: (ok: Bool, message: String)] = [:]

    var body: some View {
        Form {
            ForEach(["gh", "glab"], id: \.self) { cli in
                Section(cli == "gh" ? "GitHub (gh)" : "GitLab (glab)") {
                    if let r = results[cli] {
                        Label(r.ok ? "Authenticated" : "Not ready", systemImage: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(r.ok ? .green : .red)
                        Text(r.message).appFont(.caption, design: .monospaced).textSelection(.enabled)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text("Run `\(cli) auth login` in Terminal to sign in.").appFont(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            for cli in ["gh", "glab"] { results[cli] = await ProviderCLIService.authStatus(cli) }
        }
    }
}

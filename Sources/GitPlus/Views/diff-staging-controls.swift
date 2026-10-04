import AppKit
import SwiftUI

enum LineAction { case stage, unstage, discard }

/// Turns selected diff lines into a patch and applies it through the store.
@MainActor
enum DiffStagingActions {
    static func run(_ action: LineAction, ids: Set<Int>, raw: String, path: String, store: WorkspaceStore, repoID: UUID) {
        guard !ids.isEmpty else { return }
        if action == .discard {
            let alert = NSAlert()
            alert.messageText = "Discard \(ids.count) changed line\(ids.count == 1 ? "" : "s")?"
            alert.informativeText = "The selected changes will be removed from your working directory. You can undo this right after."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Discard")
            alert.addButton(withTitle: "Cancel")
            alert.buttons.first?.hasDestructiveAction = true
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        // Stage applies forward to the index; unstage/discard apply the selection in reverse.
        guard let patch = PatchBuilder.patch(raw: raw, selected: ids, reverse: action != .stage) else { return }
        if action == .discard { return store.discardLines(ids.count, path: path, patch: patch, in: repoID) }
        // Stage and unstage both work on the index; unstage applies the selection in reverse.
        let lines = "\(ids.count) line\(ids.count == 1 ? "" : "s")"
        let unstage = action == .unstage
        Task {
            await store.perform(repoID, unstage ? "unstage lines" : "stage lines", success: "\(unstage ? "Unstaged" : "Staged") \(lines)") {
                try await $0.apply(patch: patch, cached: true, reverse: unstage)
            }
        }
    }
}

struct HunkActionButton: View {
    let title: String
    let symbol: String
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(role: destructive ? .destructive : nil, action: action) {
            Label(title, systemImage: symbol).appFont(size: 11, weight: .medium)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
    }
}

/// Floating bar shown while diff lines are selected.
struct LineSelectionBar: View {
    let count: Int
    let area: ChangeArea
    let apply: (LineAction) -> Void
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(count) line\(count == 1 ? "" : "s") selected").appFont(size: 13, weight: .medium)
            Divider().frame(height: 18)
            if area == .unstaged {
                Button("Discard", role: .destructive) { apply(.discard) }.buttonStyle(.glass)
                Button("Stage Lines") { apply(.stage) }.buttonStyle(.glassProminent)
            } else {
                Button("Unstage Lines") { apply(.unstage) }.buttonStyle(.glassProminent)
            }
            IconButton(symbol: "xmark", help: "Clear selection (Esc)", action: clear)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 14)
    }
}

/// File path + display settings (layout, syntax, whole file, font size).
struct DiffHeaderView: View {
    let file: ChangedFile
    @Binding var mode: DiffDisplayMode
    @Binding var syntaxHighlight: Bool
    @Binding var fullContext: Bool
    @Binding var fontSize: Double
    @Binding var ignoreWhitespace: Bool
    var hunkCount = 0
    var currentHunk = 0
    var jump: (Int) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 8) {
            FileTypeIcon(path: file.path)
            HStack(spacing: 0) {
                let dir = (file.path as NSString).deletingLastPathComponent
                if !dir.isEmpty { Text(dir + "/").foregroundStyle(.secondary) }
                Text((file.path as NSString).lastPathComponent).fontWeight(.medium)
                if let old = file.oldPath { Text("  ← \(old)").foregroundStyle(.secondary) }
            }
            .lineLimit(1).truncationMode(.head)
            FileStatusLetter(status: file.status)
            Spacer()
            if ignoreWhitespace {
                StatusPill(text: "whitespace ignored", symbol: "eye.slash")
                    .help("Hunk and line staging is off while whitespace is ignored")
            }
            if hunkCount > 1 {
                HStack(spacing: 0) {
                    IconButton(symbol: "chevron.up", help: "Previous change (⌥⌘↑)") { jump(-1) }
                        .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                    Text("\(currentHunk + 1)/\(hunkCount)").appFont(.caption, monospacedDigit: true).foregroundStyle(.secondary).frame(minWidth: 34)
                    IconButton(symbol: "chevron.down", help: "Next change (⌥⌘↓)") { jump(1) }
                        .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                }
            }
            Picker("Diff layout", selection: $mode) {
                Label("Unified", systemImage: "rectangle.grid.1x2").labelStyle(.iconOnly).help("Unified").tag(DiffDisplayMode.unified)
                Label("Split", systemImage: "rectangle.split.2x1").labelStyle(.iconOnly).help("Split").tag(DiffDisplayMode.split)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Menu {
                Toggle("Syntax Highlighting", isOn: $syntaxHighlight)
                Toggle("Show Whole File", isOn: $fullContext)
                Toggle("Ignore Whitespace", isOn: $ignoreWhitespace)
                Divider()
                Button("Larger Text") { fontSize = min(fontSize + 1, 22) }
                Button("Smaller Text") { fontSize = max(fontSize - 1, 9) }
                Button("Default Size") { fontSize = 12.5 }
            } label: { Label("Diff options", systemImage: "gearshape").labelStyle(.iconOnly) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Diff options")
        }
        .appFont(size: 13)
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
        .background(Theme.headerBackground)
    }
}

import AppKit
import SwiftUI

enum LineAction { case stage, unstage, discard }

/// Turns selected diff lines into a patch and applies it through the store.
@MainActor
enum DiffStagingActions {
    static func run(_ action: LineAction, ids: Set<Int>, raw: String, store: WorkspaceStore, repoID: UUID) {
        guard !ids.isEmpty else { return }
        if action == .discard {
            let alert = NSAlert()
            alert.messageText = "Discard \(ids.count) changed line\(ids.count == 1 ? "" : "s")?"
            alert.informativeText = "The selected changes will be removed from your working directory. This cannot be undone."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Discard")
            alert.addButton(withTitle: "Cancel")
            alert.buttons.first?.hasDestructiveAction = true
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        // Stage applies forward to the index; unstage/discard apply the selection in reverse.
        guard let patch = PatchBuilder.patch(raw: raw, selected: ids, reverse: action != .stage) else { return }
        let (label, success, cached, reverse): (String, String, Bool, Bool) = switch action {
        case .stage: ("stage lines", "Staged \(ids.count) line\(ids.count == 1 ? "" : "s")", true, false)
        case .unstage: ("unstage lines", "Unstaged \(ids.count) line\(ids.count == 1 ? "" : "s")", true, true)
        case .discard: ("discard lines", "Discarded \(ids.count) line\(ids.count == 1 ? "" : "s")", false, true)
        }
        Task { await store.perform(repoID, label, success: success) { try await $0.apply(patch: patch, cached: cached, reverse: reverse) } }
    }
}

struct HunkActionButton: View {
    let title: String
    let symbol: String
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(role: destructive ? .destructive : nil, action: action) {
            Label(title, systemImage: symbol).font(.system(size: 11, weight: .medium))
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
            Text("\(count) line\(count == 1 ? "" : "s") selected").font(.system(size: 13, weight: .medium))
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

    var body: some View {
        HStack(spacing: 8) {
            FileStatusIcon(status: file.status)
            HStack(spacing: 0) {
                let dir = (file.path as NSString).deletingLastPathComponent
                if !dir.isEmpty { Text(dir + "/").foregroundStyle(.secondary) }
                Text((file.path as NSString).lastPathComponent).fontWeight(.medium)
                if let old = file.oldPath { Text("  ← \(old)").foregroundStyle(.secondary) }
            }
            .lineLimit(1).truncationMode(.head)
            Spacer()
            Picker("", selection: $mode) {
                Image(systemName: "rectangle.grid.1x2").help("Unified").tag(DiffDisplayMode.unified)
                Image(systemName: "rectangle.split.2x1").help("Split").tag(DiffDisplayMode.split)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Menu {
                Toggle("Syntax Highlighting", isOn: $syntaxHighlight)
                Toggle("Show Whole File", isOn: $fullContext)
                Divider()
                Button("Larger Text") { fontSize = min(fontSize + 1, 22) }
                Button("Smaller Text") { fontSize = max(fontSize - 1, 9) }
                Button("Default Size") { fontSize = 12.5 }
            } label: { Image(systemName: "gearshape") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Theme.headerBackground)
    }
}

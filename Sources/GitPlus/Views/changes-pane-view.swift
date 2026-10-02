import AppKit
import SwiftUI

/// Left pane "Changes" tab: Conflicts / Staged / Unstaged sections + commit box.
struct ChangesPaneView: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let tree: WorkingTree
    @Binding var selection: ChangedFile.ID?

    @State private var discarding: ChangedFile?
    @State private var showStash = false

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                if !tree.conflicted.isEmpty {
                    Section {
                        ForEach(tree.conflicted) { row($0) }
                    } header: {
                        SectionHeader(title: "Conflicts", count: tree.conflicted.count) {}
                    }
                }
                Section {
                    ForEach(tree.staged) { row($0) }
                } header: {
                    SectionHeader(title: "Staged", count: tree.staged.count) {
                        if !tree.staged.isEmpty {
                            IconButton(symbol: "minus.circle", help: "Unstage all") { run("unstage") { try await $0.unstageAll() } }
                        }
                    }
                }
                Section {
                    ForEach(tree.unstaged) { row($0) }
                } header: {
                    SectionHeader(title: "Changes", count: tree.unstaged.count) {
                        if !tree.unstaged.isEmpty {
                            IconButton(symbol: "tray.and.arrow.down", help: "Stash all changes…") { showStash = true }
                            IconButton(symbol: "plus.circle", help: "Stage all") { run("stage") { try await $0.stageAll() } }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: ChangedFile.ID.self) { ids in
                if let id = ids.first, let file = tree.all.first(where: { $0.id == id }) { menu(file) }
            } primaryAction: { ids in
                for id in ids { if let file = tree.all.first(where: { $0.id == id }) { toggle(file) } }
            }
            .overlay {
                if tree.isEmpty {
                    ContentUnavailableView("No local changes", systemImage: "checkmark.seal",
                                           description: Text("Your working directory is clean."))
                }
            }
            Rectangle().fill(Theme.separator).frame(height: 1)
            CommitBoxView(repo: repo, stagedCount: tree.staged.count, hasChanges: !tree.isEmpty)
        }
        .sheet(isPresented: $showStash) { StashSheet(repo: repo) }
        .confirmationDialog("Discard changes to \(discarding?.path ?? "")?",
                            isPresented: Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } })) {
            Button("Discard Changes", role: .destructive) {
                guard let file = discarding else { return }
                run("discard", success: "Discarded \(file.path)") { try await $0.discard(file) }
            }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func row(_ file: ChangedFile) -> some View {
        WorkingFileRow(file: file) { toggle(file) }.tag(file.id)
    }

    /// Stage ↔ unstage (double-click or the hover button).
    private func toggle(_ file: ChangedFile) {
        switch file.area {
        case .unstaged: run("stage") { try await $0.stage([file]) }
        case .staged: run("unstage") { try await $0.unstage([file]) }
        case .conflicted: run("mark resolved") { try await $0.markResolved(file) }
        case .revision: break
        }
    }

    @ViewBuilder private func menu(_ file: ChangedFile) -> some View {
        switch file.area {
        case .conflicted:
            Button("Use Ours (current branch)") { run("resolve") { try await $0.resolve(file, useOurs: true) } }
            Button("Use Theirs (incoming)") { run("resolve") { try await $0.resolve(file, useOurs: false) } }
            Button("Mark as Resolved") { toggle(file) }
        case .staged:
            Button("Unstage") { toggle(file) }
        default:
            Button("Stage") { toggle(file) }
        }
        Divider()
        Button("Open in Default App") { NSWorkspace.shared.open(repo.url.appendingPathComponent(file.path)) }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([repo.url.appendingPathComponent(file.path)]) }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(file.path, forType: .string)
        }
        if file.area != .conflicted {
            Divider()
            Button(file.area == .unstaged ? "Discard Changes…" : "Discard All Changes to File…", role: .destructive) { discarding = file }
        }
    }

    private func run(_ label: String, success: String? = nil, _ op: @escaping @Sendable (GitService) async throws -> Void) {
        Task { await store.perform(repo.id, label, success: success, op) }
    }
}

/// File row: name + dimmed folder, status icon, and a stage/unstage button on hover.
struct WorkingFileRow: View {
    let file: ChangedFile
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            FileStatusIcon(status: file.status)
            VStack(alignment: .leading, spacing: 0) {
                Text((file.path as NSString).lastPathComponent).lineLimit(1)
                let dir = (file.path as NSString).deletingLastPathComponent
                if !dir.isEmpty {
                    Text(dir).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
            }
            Spacer(minLength: 4)
            if hovering {
                IconButton(symbol: icon, help: help, action: toggle)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(file.oldPath.map { "\($0) → \(file.path)" } ?? file.path)
    }

    private var icon: String {
        switch file.area {
        case .staged: "minus.circle"
        case .conflicted: "checkmark.circle"
        default: "plus.circle"
        }
    }

    private var help: String {
        switch file.area {
        case .staged: "Unstage"
        case .conflicted: "Mark as resolved"
        default: "Stage"
        }
    }
}

import SwiftUI

/// Left pane "Changes" tab: working-tree files with checkboxes + commit box.
struct ChangesPaneView: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let files: [ChangedFile]
    @Binding var selection: ChangedFile.ID?
    @Binding var checked: Set<String>

    @State private var summary = ""
    @State private var details = ""
    @State private var discarding: ChangedFile?

    private var branch: String { store.statuses[repo.id]?.branch ?? "HEAD" }
    private var canCommit: Bool {
        !summary.trimmingCharacters(in: .whitespaces).isEmpty && !checked.isEmpty && !store.busy.contains(repo.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            ChangedFileList(files: files, selection: $selection, checked: $checked) { file in
                AnyView(Group {
                    Button("Discard Changes…", role: .destructive) { discarding = file }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([repo.url.appendingPathComponent(file.path)])
                    }
                    Button("Copy File Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(file.path, forType: .string)
                    }
                })
            }
            .overlay {
                if files.isEmpty {
                    ContentUnavailableView("No local changes", systemImage: "checkmark.circle",
                                           description: Text("There are no uncommitted changes in this repository."))
                }
            }
            Rectangle().fill(Theme.separator).frame(height: 1)
            commitBox
        }
        .confirmationDialog("Discard changes to \(discarding?.path ?? "")?", isPresented: Binding(
            get: { discarding != nil }, set: { if !$0 { discarding = nil } }
        )) {
            Button("Discard Changes", role: .destructive) {
                guard let file = discarding else { return }
                Task { await store.perform(repo.id, "discard") { try await $0.discard(file) } }
            }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private var commitBox: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                AvatarView(name: NSFullUserName(), email: NSUserName(), size: 22)
                TextField("Summary (required)", text: $summary).textFieldStyle(.roundedBorder)
            }
            TextEditor(text: $details)
                .font(.system(size: 12))
                .frame(height: 70)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 5).fill(Theme.contextLine))
                .overlay(alignment: .topLeading) {
                    if details.isEmpty { Text("Description").foregroundStyle(.tertiary).padding(8).allowsHitTesting(false) }
                }
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.separator))
            Button(action: commit) {
                Text("Commit \(checked.count) file\(checked.count == 1 ? "" : "s") to **\(branch)**")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canCommit)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(10)
        .background(Theme.headerBackground)
    }

    private func commit() {
        let selected = files.filter { checked.contains($0.id) }
        let s = summary.trimmingCharacters(in: .whitespaces), d = details.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            if await store.perform(repo.id, "commit", { try await $0.commit(files: selected, summary: s, description: d) }) {
                summary = ""
                details = ""
            }
        }
    }
}

import AppKit
import SwiftUI

/// Add, edit and remove remotes of a repository.
struct RemotesSheet: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let dismiss: () -> Void

    @State private var remotes: [RemoteEntry] = []
    @State private var editing: [String: String] = [:]
    @State private var newName = ""
    @State private var newURL = ""
    @State private var removing: RemoteEntry?

    private var git: GitService { GitService(repo: repo.url) }
    private var revision: Int { store.revisions[repo.id] ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Remotes of \(repo.name)").font(.title3.weight(.semibold)).padding(Spacing.l)
            Form {
                if remotes.isEmpty {
                    Text("No remotes yet. Add one below to push and pull.").foregroundStyle(.secondary)
                }
                ForEach(remotes) { remote in
                    Section(remote.name) {
                        HStack {
                            TextField("URL", text: Binding(get: { editing[remote.name] ?? remote.fetchURL }, set: { editing[remote.name] = $0 }))
                                .font(.mono)
                            if let edited = editing[remote.name], edited != remote.fetchURL, !edited.isEmpty {
                                Button("Save") { run("set remote URL", "Updated \(remote.name)") { try await $0.setRemoteURL(remote.name, url: edited) } }
                                    .buttonStyle(.glassProminent)
                            }
                            Button(role: .destructive) { removing = remote } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .help("Remove \(remote.name)")
                        }
                        if remote.pushURL != remote.fetchURL {
                            LabeledContent("Push URL", value: remote.pushURL).font(.caption)
                        }
                    }
                }
                Section("Add Remote") {
                    TextField("Name", text: $newName, prompt: Text(remotes.isEmpty ? "origin" : "upstream"))
                    TextField("URL", text: $newURL, prompt: Text("git@github.com:owner/repo.git")).font(.mono)
                    HStack {
                        Spacer()
                        Button("Add Remote") {
                            let name = newName.trimmingCharacters(in: .whitespaces).isEmpty ? (remotes.isEmpty ? "origin" : "upstream")
                                : newName.trimmingCharacters(in: .whitespaces)
                            let url = newURL.trimmingCharacters(in: .whitespaces)
                            run("add remote", "Added \(name)") { try await $0.addRemote(name, url: url) }
                            newName = ""; newURL = ""
                        }
                        .disabled(newURL.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Done", action: dismiss).keyboardShortcut(.defaultAction)
            }
            .padding(Spacing.l)
        }
        .frame(width: 560, height: 520)
        .task(id: revision) {
            remotes = (try? await git.remotes()) ?? []
            editing = [:]
        }
        .confirmationDialog("Remove remote \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            if let remote = removing {
                Button("Remove", role: .destructive) { run("remove remote", "Removed \(remote.name)") { try await $0.removeRemote(remote.name) } }
            }
        } message: {
            Text("Remote-tracking branches of this remote are deleted locally. Nothing changes on the server.")
        }
    }

    private func run(_ label: String, _ success: String, _ op: @escaping @Sendable (GitService) async throws -> Void) {
        Task { await store.perform(repo.id, label, success: success, op) }
    }
}

/// Clone a repository by URL into a chosen folder.
struct CloneSheet: View {
    @Environment(WorkspaceStore.self) private var store
    let dismiss: () -> Void

    @AppStorage("cloneParentFolder") private var parentPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Developer").path
    @State private var remote = ""
    @State private var name = ""
    @State private var nameEdited = false
    @State private var groupID: UUID?
    @State private var isCloning = false

    private var destination: URL { URL(fileURLWithPath: parentPath).appendingPathComponent(name) }
    private var exists: Bool { !name.isEmpty && FileManager.default.fileExists(atPath: destination.path) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Clone a Repository").font(.title3.weight(.semibold))
            Form {
                TextField("Repository URL", text: $remote, prompt: Text("https://github.com/owner/repo.git or git@…"))
                    .onChange(of: remote) { _, new in
                        if !nameEdited { name = GitService.repositoryName(fromRemote: new) ?? "" }
                    }
                TextField("Folder name", text: Binding(get: { name }, set: { name = $0; nameEdited = true }))
                LabeledContent("Location") {
                    HStack {
                        Text(parentPath).lineLimit(1).truncationMode(.head).foregroundStyle(.secondary)
                        Button("Choose…") { chooseParent() }
                    }
                }
                Picker("Group", selection: $groupID) {
                    Text("Ungrouped").tag(UUID?.none)
                    ForEach(store.groups) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            .formStyle(.grouped)
            if exists {
                Label("\(destination.path) already exists.", systemImage: "exclamationmark.triangle").foregroundStyle(Theme.modified).font(.callout)
            }
            Text("Uses your git credentials (SSH keys, credential helper, `gh auth setup-git`).").font(.caption).foregroundStyle(.secondary)
            HStack {
                if isCloning { ProgressView().controlSize(.small); Text("Cloning…").foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel", action: dismiss).keyboardShortcut(.cancelAction).disabled(isCloning)
                Button("Clone") { clone() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(remote.trimmingCharacters(in: .whitespaces).isEmpty || name.isEmpty || exists || isCloning)
            }
        }
        .padding(Spacing.l)
        .frame(width: 560)
    }

    private func chooseParent() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { parentPath = url.path }
    }

    private func clone() {
        isCloning = true
        let remote = self.remote.trimmingCharacters(in: .whitespaces), destination = self.destination, groupID = self.groupID
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        Task {
            let id = await store.clone(remote, into: destination, groupID: groupID)
            isCloning = false
            if let id {
                dismiss()
                RepoActions.select(.repo(id))
            }
        }
    }
}

/// Recent git operations with their outcome (Repository ▸ Activity, or the command palette).
struct ActivityView: View {
    @Environment(WorkspaceStore.self) private var store
    let dismiss: () -> Void
    @State private var expanded: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Activity").font(.title3.weight(.semibold))
                Spacer()
                Button("Clear Finished") { store.clearFinishedActivities() }.disabled(store.activities.allSatisfy(\.isRunning))
                Button("Done", action: dismiss).keyboardShortcut(.defaultAction)
            }
            .padding(Spacing.l)
            Divider()
            List(store.activities) { item in
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.s) {
                        if item.isRunning {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: item.error == nil ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(item.error == nil ? Theme.added : Theme.deleted)
                        }
                        Text(item.label.prefix(1).uppercased() + item.label.dropFirst()).fontWeight(.medium)
                        Text(item.repoName).foregroundStyle(.secondary)
                        Spacer()
                        Text(duration(item)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Text(item.started.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(.tertiary)
                    }
                    if let error = item.error {
                        Text(error)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(expanded.contains(item.id) ? nil : 2)
                            .textSelection(.enabled)
                            .onTapGesture { if expanded.contains(item.id) { expanded.remove(item.id) } else { expanded.insert(item.id) } }
                    }
                }
                .padding(.vertical, Spacing.xxs)
            }
            .listStyle(.inset)
            .overlay { if store.activities.isEmpty { ContentUnavailableView("No Activity Yet", systemImage: "list.bullet.rectangle") } }
        }
        .frame(width: 620, height: 460)
    }

    private func duration(_ item: WorkspaceStore.Activity) -> String {
        let seconds = (item.finished ?? .now).timeIntervalSince(item.started)
        return seconds < 1 ? "<1s" : String(format: "%.1fs", seconds)
    }
}

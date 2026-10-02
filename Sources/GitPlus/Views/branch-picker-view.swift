import SwiftUI

/// "Current Branch" dropdown: filter, switch, create, and branch management via right-click.
struct BranchPickerView: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    @Binding var isPresented: Bool

    @State private var branches = BranchList()
    @State private var filter = ""
    @State private var renaming: String?
    @State private var newName = ""
    @State private var deleting: (name: String, remote: Bool)?
    @State private var showTags = false
    @State private var tags: [TagInfo] = []
    @State private var deletingTag: TagInfo?

    private var trimmed: String { filter.trimmingCharacters(in: .whitespaces) }
    private func matches(_ b: String) -> Bool { trimmed.isEmpty || b.localizedCaseInsensitiveContains(trimmed) }
    private var current: String { branches.current ?? "HEAD" }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $showTags) {
                Text("Branches").tag(false)
                Text("Tags").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top], 10)
            TextField(showTags ? "Filter tags" : "Filter or create branch", text: $filter)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if !showTags { createIfNew() } }
                .padding(10)
            Divider()
            if showTags { tagList } else { branchList }
            Divider()
            HStack {
                if showTags {
                    Button("Push All Tags") { run("push tags", "Pushed all tags") { try await $0.pushAllTags() } }
                        .disabled(tags.isEmpty)
                } else {
                    Button("Merge into \(current)…") {
                        isPresented = false
                        RepoActions.post(.showMerge)
                    }
                }
                Spacer()
                Text(showTags ? "Right-click a tag for more" : "Right-click a branch for more").font(.caption).foregroundStyle(.secondary)
            }
            .controlSize(.small)
            .padding(8)
        }
        .frame(width: 380, height: 520)
        .task { branches = (try? await GitService(repo: repo.url).branches()) ?? BranchList() }
        .task(id: showTags) { if showTags { tags = (try? await GitService(repo: repo.url).tags()) ?? [] } }
        .alert("Rename \(renaming ?? "")", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("New name", text: $newName)
            Button("Rename") {
                guard let old = renaming else { return }
                let new = newName.trimmingCharacters(in: .whitespaces)
                run("rename branch", "Renamed to \(new)") { try await $0.renameBranch(old, to: new) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \(deleting?.name ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            if let target = deleting {
                if target.remote {
                    Button("Delete from Remote", role: .destructive) {
                        run("delete remote branch", "Deleted \(target.name)") { try await $0.deleteRemoteBranch(target.name) }
                    }
                } else {
                    Button("Delete", role: .destructive) { run("delete branch", "Deleted \(target.name)") { try await $0.deleteBranch(target.name, force: false) } }
                    Button("Force Delete (even if unmerged)", role: .destructive) {
                        run("delete branch", "Deleted \(target.name)") { try await $0.deleteBranch(target.name, force: true) }
                    }
                }
            }
        } message: {
            Text(deleting?.remote == true ? "The branch will be removed from the server for everyone." : "Unmerged commits on this branch may be lost.")
        }
    }

    private var tagList: some View {
        let q = trimmed
        let visible = tags.filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(visible) { tag in
                    row(icon: "tag", title: tag.name, detail: tag.date.map(RelativeTime.string)) {
                        run("checkout tag", "Checked out \(tag.name)") { try await $0.checkout(commit: "refs/tags/\(tag.name)") }
                    }
                    .help(tag.subject.isEmpty ? tag.target : "\(tag.target) — \(tag.subject)")
                    .contextMenu {
                        Button("Check Out (detached)") { run("checkout tag", "Checked out \(tag.name)") { try await $0.checkout(commit: "refs/tags/\(tag.name)") } }
                        Button("Push to Remote") { run("push tag", "Pushed \(tag.name)") { try await $0.pushTag(tag.name) } }
                        Button("Copy Name") { copy(tag.name) }
                        Divider()
                        Button("Delete…", role: .destructive) { deletingTag = tag }
                    }
                }
                if visible.isEmpty {
                    Text(tags.isEmpty ? "No tags yet — create one from a commit's menu in History." : "No tags match")
                        .font(.callout).foregroundStyle(.secondary).padding()
                }
            }
        }
        .confirmationDialog("Delete tag \(deletingTag?.name ?? "")?", isPresented: Binding(get: { deletingTag != nil }, set: { if !$0 { deletingTag = nil } })) {
            if let tag = deletingTag {
                Button("Delete Locally", role: .destructive) { run("delete tag", "Deleted tag \(tag.name)") { try await $0.deleteTag(tag.name) } }
                Button("Delete Locally and on Remote", role: .destructive) {
                    run("delete tag", "Deleted tag \(tag.name) everywhere") {
                        try await $0.deleteRemoteTag(tag.name)
                        try await $0.deleteTag(tag.name)
                    }
                }
            }
        }
    }

    private var branchList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if canCreate {
                    row(icon: "plus.circle.fill", title: "Create branch “\(trimmed)”", detail: "from \(current)", action: createIfNew)
                }
                sectionHeader("Local branches")
                ForEach(branches.local.filter(matches), id: \.self) { name in
                    let isCurrent = name == branches.current
                    row(icon: isCurrent ? "checkmark.circle.fill" : "arrow.triangle.branch", title: name,
                        detail: isCurrent ? "current" : nil) {
                        guard !isCurrent else { isPresented = false; return }
                        run("switch branch", "Switched to \(name)") { try await $0.switchBranch(name) }
                    }
                    .contextMenu { localMenu(name, isCurrent: isCurrent) }
                }
                let localSet = Set(branches.local)
                let remotes = branches.remote.filter { matches($0) && !localSet.contains(Self.shortName($0)) }
                if !remotes.isEmpty {
                    sectionHeader("Remote branches")
                    ForEach(remotes, id: \.self) { name in
                        row(icon: "cloud", title: name, detail: nil) {
                            run("checkout remote branch", "Checked out \(Self.shortName(name))") { try await $0.switchBranch(name, isRemote: true) }
                        }
                        .contextMenu { remoteMenu(name) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func localMenu(_ name: String, isCurrent: Bool) -> some View {
        if !isCurrent {
            Button("Switch to \(name)") { run("switch branch", "Switched to \(name)") { try await $0.switchBranch(name) } }
            Button("Merge \(name) into \(current)") { run("merge", "Merged \(name) into \(current)") { try await $0.merge(name) } }
            Button("Rebase \(current) onto \(name)") { run("rebase", "Rebased onto \(name)") { try await $0.rebase(onto: name) } }
            Divider()
        }
        Button("Rename…") { newName = name; renaming = name }
        Button("Copy Name") { copy(name) }
        if !isCurrent {
            Divider()
            Button("Delete…", role: .destructive) { deleting = (name, false) }
        }
    }

    @ViewBuilder private func remoteMenu(_ name: String) -> some View {
        Button("Checkout as Local Branch") { run("checkout", "Checked out \(Self.shortName(name))") { try await $0.switchBranch(name, isRemote: true) } }
        Button("Merge into \(current)") { run("merge", "Merged \(name)") { try await $0.merge(name) } }
        Button("Rebase \(current) onto \(name)") { run("rebase", "Rebased onto \(name)") { try await $0.rebase(onto: name) } }
        Button("Copy Name") { copy(name) }
        Divider()
        Button("Delete from Remote…", role: .destructive) { deleting = (name, true) }
    }

    /// `origin/feature/x` → `feature/x`.
    static func shortName(_ remoteBranch: String) -> String {
        remoteBranch.split(separator: "/", maxSplits: 1).dropFirst().first.map(String.init) ?? remoteBranch
    }

    private var canCreate: Bool { !trimmed.isEmpty && !trimmed.contains(" ") && !branches.local.contains(trimmed) }

    private func createIfNew() {
        guard canCreate else { return }
        let name = trimmed
        run("create branch", "Created \(name)") { try await $0.createBranch(name) }
    }

    private func run(_ label: String, _ success: String, _ op: @escaping @Sendable (GitService) async throws -> Void) {
        isPresented = false
        Task { await store.perform(repo.id, label, success: success, op) }
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold)).tracking(0.4)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
    }

    private func row(icon: String, title: String, detail: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 16).foregroundStyle(detail == "current" ? Color.accentColor : .secondary)
                Text(title).lineLimit(1).truncationMode(.middle)
                Spacer()
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
    }
}


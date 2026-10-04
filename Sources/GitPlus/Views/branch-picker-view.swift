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
    /// Keyboard highlight in `entries` (↑/↓ move it, Return activates it).
    @State private var highlighted = 0
    @FocusState private var filterFocused: Bool

    private enum Entry: Hashable { case create, local(String), remote(String) }

    /// Rows of the branch list in display order (create row, local, remote-only).
    private var entries: [Entry] {
        let localSet = Set(branches.local)
        return (canCreate ? [.create] : [])
            + branches.local.filter(matches).map(Entry.local)
            + branches.remote.filter { matches($0) && !localSet.contains(Self.shortName($0)) }.map(Entry.remote)
    }

    /// First real match that isn't the current branch, so Return switches rather than creates.
    private var defaultHighlight: Int {
        entries.firstIndex { if case .local(let n) = $0 { return n != branches.current }; return $0 != .create } ?? 0
    }

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
                .focused($filterFocused)
                .onSubmit { if !showTags { activate(highlighted) } }
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
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
                Text(showTags ? "Right-click a tag for more" : "Right-click a branch for more").appFont(.caption).foregroundStyle(.secondary)
            }
            .controlSize(.small)
            .padding(8)
        }
        .frame(width: 380, height: 520)
        .task {
            branches = (try? await GitService(repo: repo.url).branches()) ?? BranchList()
            highlighted = defaultHighlight
        }
        .onAppear { filterFocused = true }
        .onChange(of: filter) { highlighted = defaultHighlight }
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
                        .appFont(.callout).foregroundStyle(.secondary).padding()
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
        let entries = self.entries
        let firstLocal = entries.firstIndex { if case .local = $0 { return true }; return false }
        let firstRemote = entries.firstIndex { if case .remote = $0 { return true }; return false }
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element) { index, entry in
                        if index == firstLocal { sectionHeader("Local branches") }
                        if index == firstRemote { sectionHeader("Remote branches") }
                        entryRow(entry, isHighlighted: index == highlighted) { activate(index) }
                            .id(index)
                    }
                }
            }
            .onChange(of: highlighted) { _, new in proxy.scrollTo(new) }
        }
    }

    @ViewBuilder private func entryRow(_ entry: Entry, isHighlighted: Bool, action: @escaping () -> Void) -> some View {
        switch entry {
        case .create:
            row(icon: "plus.circle.fill", title: "Create branch “\(trimmed)”", detail: "from \(current)", isHighlighted: isHighlighted, action: action)
        case .local(let name):
            let isCurrent = name == branches.current
            row(icon: isCurrent ? "checkmark.circle.fill" : "arrow.triangle.branch", title: name,
                detail: isCurrent ? "current" : nil, isHighlighted: isHighlighted, action: action)
                .contextMenu { localMenu(name, isCurrent: isCurrent) }
        case .remote(let name):
            row(icon: "cloud", title: name, detail: nil, isHighlighted: isHighlighted, action: action)
                .contextMenu { remoteMenu(name) }
        }
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard !showTags, !entries.isEmpty else { return .ignored }
        highlighted = min(max(highlighted + delta, 0), entries.count - 1)
        return .handled
    }

    private func activate(_ index: Int) {
        guard entries.indices.contains(index) else { return }
        switch entries[index] {
        case .create: createIfNew()
        case .local(let name): name == branches.current ? (isPresented = false) : switchTo(name)
        case .remote(let name): switchTo(name, isRemote: true)
        }
    }

    @ViewBuilder private func localMenu(_ name: String, isCurrent: Bool) -> some View {
        if !isCurrent {
            Button("Switch to \(name)") { switchTo(name) }
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
        Button("Checkout as Local Branch") { switchTo(name, isRemote: true) }
        Button("Merge into \(current)") { run("merge", "Merged \(name)") { try await $0.merge(name) } }
        Button("Rebase \(current) onto \(name)") { run("rebase", "Rebased onto \(name)") { try await $0.rebase(onto: name) } }
        Button("Copy Name") { copy(name) }
        Divider()
        Button("Delete from Remote…", role: .destructive) { deleting = (name, true) }
    }

    static func shortName(_ remoteBranch: String) -> String { GitService.localName(ofRemote: remoteBranch) }

    private var canCreate: Bool { !trimmed.isEmpty && !trimmed.contains(" ") && !branches.local.contains(trimmed) }

    private func createIfNew() {
        guard canCreate else { return }
        let name = trimmed
        run("create branch", "Created \(name)") { try await $0.createBranch(name) }
    }

    /// Asks about local changes first (dialog lives on the window, the popover closes now).
    private func switchTo(_ name: String, isRemote: Bool = false) {
        isPresented = false
        store.requestSwitch(repo.id, to: name, isRemote: isRemote)
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
            .appFont(size: 11, weight: .semibold).tracking(0.4)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
    }

    private func row(icon: String, title: String, detail: String?, isHighlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 16).foregroundStyle(detail == "current" ? Color.accentColor : .secondary)
                Text(title).lineLimit(1).truncationMode(.middle)
                Spacer()
                if let detail { Text(detail).appFont(.caption).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(isHighlighted ? Color.accentColor.opacity(0.18) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}


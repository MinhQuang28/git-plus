import SwiftUI

/// "Current Branch" dropdown: filter, switch (local or remote-tracking), create new branch.
struct BranchPickerView: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    @Binding var isPresented: Bool

    @State private var branches = BranchList()
    @State private var filter = ""

    private var trimmed: String { filter.trimmingCharacters(in: .whitespaces) }
    private func matches(_ b: String) -> Bool { trimmed.isEmpty || b.localizedCaseInsensitiveContains(trimmed) }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Filter or create branch", text: $filter)
                .textFieldStyle(.roundedBorder)
                .onSubmit(createIfNew)
                .padding(10)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if canCreate {
                        row(icon: "plus", title: "Create new branch “\(trimmed)”", detail: "from \(branches.current ?? "HEAD")", action: createIfNew)
                    }
                    sectionHeader("Local")
                    ForEach(branches.local.filter(matches), id: \.self) { name in
                        row(icon: name == branches.current ? "checkmark" : "arrow.triangle.branch", title: name, detail: nil) {
                            guard name != branches.current else { isPresented = false; return }
                            run("switch branch") { try await $0.switchBranch(name) }
                        }
                    }
                    let localSet = Set(branches.local)
                    let remotes = branches.remote.filter { matches($0) && !localSet.contains(Self.shortName($0)) }
                    if !remotes.isEmpty {
                        sectionHeader("Remote")
                        ForEach(remotes, id: \.self) { name in
                            row(icon: "cloud", title: name, detail: nil) {
                                run("checkout remote branch") { try await $0.switchBranch(name, isRemote: true) }
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 360, height: 460)
        .task { branches = (try? await GitService(repo: repo.url).branches()) ?? BranchList() }
    }

    /// `origin/feature/x` → `feature/x`.
    static func shortName(_ remoteBranch: String) -> String {
        remoteBranch.split(separator: "/", maxSplits: 1).dropFirst().first.map(String.init) ?? remoteBranch
    }

    private var canCreate: Bool {
        !trimmed.isEmpty && !trimmed.contains(" ") && !branches.local.contains(trimmed)
    }

    private func createIfNew() {
        guard canCreate else { return }
        let name = trimmed
        run("create branch") { try await $0.createBranch(name) }
    }

    private func run(_ label: String, _ op: @escaping @Sendable (GitService) async throws -> Void) {
        isPresented = false
        Task { await store.perform(repo.id, label, op) }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.headerBackground)
    }

    private func row(icon: String, title: String, detail: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 16).foregroundStyle(.secondary)
                Text(title).lineLimit(1).truncationMode(.middle)
                Spacer()
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

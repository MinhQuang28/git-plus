import Foundation

/// Group management: create, rename (incl. the virtual "Ungrouped"), delete, move, auto-group.
extension WorkspaceStore {
    @discardableResult
    func createGroup(named name: String) -> RepoGroup {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let existing = workspace.groups.first(where: { $0.name == trimmed }) { return existing }
        let group = RepoGroup(name: trimmed.isEmpty ? "New Group" : trimmed)
        workspace.groups.append(group)
        save()
        return group
    }

    func renameGroup(_ id: UUID, to name: String) {
        guard let i = workspace.groups.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        workspace.groups[i].name = name
        save()
    }

    /// "Ungrouped" is virtual: renaming it turns its repos into a real group with that name.
    @discardableResult
    func renameUngrouped(to name: String) -> UUID? {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let group = createGroup(named: name)
        move(repoIDs: repos(in: nil).map(\.id), to: group.id)
        return group.id
    }

    /// Deletes the group; its repos become ungrouped (never removed).
    func deleteGroup(_ id: UUID) {
        workspace.groups.removeAll { $0.id == id }
        for i in workspace.repos.indices where workspace.repos[i].groupID == id { workspace.repos[i].groupID = nil }
        save()
    }

    func move(repoIDs: [UUID], to groupID: UUID?) {
        for i in workspace.repos.indices where repoIDs.contains(workspace.repos[i].id) { workspace.repos[i].groupID = groupID }
        save()
    }

    /// Groups every ungrouped repo by `host/namespace` of its remote (e.g. `github.com/acme`).
    func autoGroupByRemote() async {
        let ungrouped = repos(in: nil)
        await refreshStatus(ungrouped.map(\.id))
        for repo in ungrouped {
            guard let key = statuses[repo.id]?.remote?.groupKey else { continue }
            move(repoIDs: [repo.id], to: createGroup(named: key).id)
        }
    }
}

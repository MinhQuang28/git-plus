import Foundation

/// A branch switch that has to ask what happens to the local changes first.
struct BranchSwitchRequest: Identifiable, Equatable {
    let id = UUID()
    let repoID: UUID
    let target: String
    let isRemote: Bool
    let current: String
    let changedFiles: Int

    /// Local branch name the switch ends up on (`origin/x` → `x`).
    var targetName: String { isRemote ? GitService.localName(ofRemote: target) : target }
}

extension WorkspaceStore {
    /// Switches right away on a clean tree; with local changes, asks to leave them on the current
    /// branch (stash) or bring them along. Mid-merge/rebase states go straight to git (it explains).
    func requestSwitch(_ repoID: UUID, to target: String, isRemote: Bool = false) {
        let status = statuses[repoID]
        if let status, status.changedFiles > 0, status.operation == nil, status.branch != "?" {
            pendingBranchSwitch = BranchSwitchRequest(repoID: repoID, target: target, isRemote: isRemote,
                                                      current: status.branch, changedFiles: status.changedFiles)
        } else {
            switchBranch(repoID, to: target, isRemote: isRemote, leaveChanges: false)
        }
    }

    func resolve(_ request: BranchSwitchRequest, leaveChanges: Bool) {
        pendingBranchSwitch = nil
        switchBranch(request.repoID, to: request.target, isRemote: request.isRemote,
                     leaveChanges: leaveChanges, current: request.current)
    }

    private func switchBranch(_ repoID: UUID, to target: String, isRemote: Bool, leaveChanges: Bool, current: String? = nil) {
        let name = isRemote ? GitService.localName(ofRemote: target) : target
        let leaveOn = leaveChanges ? current : nil
        let success = leaveOn.map { "Switched to \(name) · changes kept on \($0)" } ?? "Switched to \(name)"
        Task {
            await perform(repoID, isRemote ? "checkout remote branch" : "switch branch", success: success) {
                try await $0.switchBranch(target, isRemote: isRemote, leaveChangesOn: leaveOn)
            }
        }
    }
}

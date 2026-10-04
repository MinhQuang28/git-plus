import SwiftUI

/// "You have changes on dev" — leave them there (stashed, restored on return) or bring them to the target.
struct BranchSwitchDialog: ViewModifier {
    @Environment(WorkspaceStore.self) private var store
    let repoID: UUID

    func body(content: Content) -> some View {
        let request = store.pendingBranchSwitch.flatMap { $0.repoID == repoID ? $0 : nil }
        content.confirmationDialog(
            "Switch to \(request?.targetName ?? "")?",
            isPresented: Binding(get: { request != nil }, set: { if !$0 { store.pendingBranchSwitch = nil } }),
            presenting: request
        ) { request in
            Button("Leave My Changes on \(request.current)") { store.resolve(request, leaveChanges: true) }
            Button("Bring My Changes to \(request.targetName)") { store.resolve(request, leaveChanges: false) }
            Button("Cancel", role: .cancel) { store.pendingBranchSwitch = nil }
        } message: { request in
            let files = request.changedFiles == 1 ? "1 changed file" : "\(request.changedFiles) changed files"
            Text("You have \(files) on \(request.current).\n\nLeft changes are stashed and come back automatically when you switch back to \(request.current).")
        }
    }
}

extension View {
    func branchSwitchDialog(repoID: UUID) -> some View { modifier(BranchSwitchDialog(repoID: repoID)) }
}

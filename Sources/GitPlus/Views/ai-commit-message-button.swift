import SwiftUI

/// ✨ in the commit summary field: writes the message from the changes; while running it becomes Stop.
/// Before AI is set up it opens Settings → AI.
struct AICommitMessageButton: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.openSettings) private var openSettings
    @AppStorage(AISettings.enabledKey) private var enabled = false
    let repoID: UUID
    /// Something to describe and not amending.
    let isAvailable: Bool
    let amend: Bool

    private var isWriting: Bool { store.isWritingMessage(repoID) }

    var body: some View {
        Button(action: activate) {
            if isWriting {
                Label("Stop writing the message", systemImage: "stop.circle").labelStyle(.iconOnly).symbolEffect(.pulse)
            } else {
                Label("Write commit message with AI", systemImage: "sparkles").labelStyle(.iconOnly)
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(enabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .disabled(!isWriting && !isAvailable)
        .help(isWriting ? "Stop writing the message"
              : amend ? "Not available while amending"
              : enabled ? "Write the commit message with AI (⌥⌘G)" : "Set up AI commit messages…")
    }

    private func activate() {
        if isWriting {
            store.cancelCommitMessage(repoID)
        } else if (try? AISettings.current()) == nil {
            UserDefaults.standard.set("ai", forKey: SettingsView.tabKey)
            openSettings()
        } else {
            store.generateCommitMessage(repoID)
        }
    }
}

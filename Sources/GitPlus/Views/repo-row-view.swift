import SwiftUI

/// Compact repo summary: name, branch, ahead/behind, dirty marker.
struct RepoRowView: View {
    let repo: RepoEntry
    let status: RepoStatus?
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 6) {
            ProviderIcon(provider: status?.remote?.provider)
            VStack(alignment: .leading, spacing: 1) {
                Text(repo.name).lineLimit(1)
                if let status {
                    Text(status.branch).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if isBusy {
                ProgressView().controlSize(.small)
            } else if let status {
                SyncBadge(status: status)
            }
        }
    }
}

struct SyncBadge: View {
    let status: RepoStatus

    var body: some View {
        HStack(spacing: 4) {
            if status.behind > 0 { Text("↓\(status.behind)").foregroundStyle(.orange) }
            if status.ahead > 0 { Text("↑\(status.ahead)").foregroundStyle(.blue) }
            if status.changedFiles > 0 {
                Circle().fill(.yellow).frame(width: 7, height: 7).help("\(status.changedFiles) uncommitted change(s)")
            }
        }
        .font(.caption.monospacedDigit())
    }
}

struct ProviderIcon: View {
    let provider: GitProvider?

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .frame(width: 16)
            .help(provider?.rawValue ?? "no remote")
    }

    private var symbol: String {
        switch provider {
        case .github: "chevron.left.forwardslash.chevron.right"
        case .gitlab: "flame"
        case .other: "server.rack"
        case nil: "externaldrive"
        }
    }

    private var color: Color {
        switch provider {
        case .github: .primary
        case .gitlab: .orange
        default: .secondary
        }
    }
}

struct RepoContextMenu: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    @Binding var selection: SidebarSelection?

    var body: some View {
        Button("Fetch") { Task { await store.fetch([repo.id]) } }
        Button("Pull (fast-forward)") { Task { await store.pull([repo.id]) } }
        Divider()
        Menu("Move to Group") {
            ForEach(store.groups) { g in Button(g.name) { store.move(repoIDs: [repo.id], to: g.id) } }
            Divider()
            Button("Ungrouped") { store.move(repoIDs: [repo.id], to: nil) }
        }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([repo.url]) }
        Button("Open in Terminal") {
            NSWorkspace.shared.open([repo.url], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: .init())
        }
        if let web = store.statuses[repo.id]?.remote?.webURL {
            Button("Open on Web") { NSWorkspace.shared.open(web) }
        }
        Divider()
        Button("Remove from Git Plus", role: .destructive) {
            if selection == .repo(repo.id) { selection = nil }
            store.remove(repoIDs: [repo.id])
        }
    }
}

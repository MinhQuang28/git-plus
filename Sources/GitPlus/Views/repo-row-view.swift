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
                    Text(status.branch).appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
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
            if status.operation != nil || status.conflicts > 0 {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.conflict)
                    .help(status.operation.map { "\($0.title) in progress" } ?? "Conflicts")
            }
            if status.behind > 0 { Text("↓\(status.behind)").foregroundStyle(Theme.behind) }
            if status.ahead > 0 { Text("↑\(status.ahead)").foregroundStyle(Theme.ahead) }
            if status.changedFiles > 0 {
                Circle().fill(Theme.modified).frame(width: 7, height: 7).help("\(status.changedFiles) uncommitted change(s)")
            }
        }
        .appFont(.caption, monospacedDigit: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
    }

    private var spokenSummary: String {
        var parts: [String] = []
        if let op = status.operation { parts.append("\(op.title) in progress") } else if status.conflicts > 0 { parts.append("conflicts") }
        if status.ahead > 0 { parts.append("\(status.ahead) ahead") }
        if status.behind > 0 { parts.append("\(status.behind) behind") }
        if status.changedFiles > 0 { parts.append("\(status.changedFiles) changed") }
        return parts.joined(separator: ", ")
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
        Button("Pull") { Task { await store.pull([repo.id]) } }
        Divider()
        Button(repo.isPinned == true ? "Unpin" : "Pin to Top") { store.togglePin(repo.id) }
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

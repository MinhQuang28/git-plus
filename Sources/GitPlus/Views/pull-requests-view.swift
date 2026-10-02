import AppKit
import SwiftUI

/// Lists GitHub PRs (via `gh`) or GitLab MRs (via `glab`) for a repository.
struct PullRequestsView: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let provider: GitProvider
    var dismiss: () -> Void = {}

    @State private var state = "open"
    @State private var items: [PullRequestItem] = []
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("State", selection: $state) {
                    Text("Open").tag("open")
                    Text("Merged").tag("merged")
                    Text("Closed").tag("closed")
                    Text("All").tag("all")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                Spacer()
                if let cli = provider.cliName { Text("via `\(cli)`").font(.caption).foregroundStyle(.secondary) }
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Reload")
                Button {
                    Task {
                        do { try await service.createForCurrentBranch() } catch { self.error = error.localizedDescription }
                    }
                } label: {
                    Label(provider == .gitlab ? "New Merge Request" : "New Pull Request", systemImage: "plus")
                }
                .buttonStyle(.glassProminent)
                .help("Opens the \(provider == .gitlab ? "merge" : "pull") request form in your browser for the current branch (push it first)")
            }
            .padding(8)
            Divider()
            content
        }
        .task(id: state) { await load() }
    }

    @ViewBuilder private var content: some View {
        if let error {
            ContentUnavailableView("Unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if isLoading && items.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty {
            ContentUnavailableView("No \(provider.reviewNoun)", systemImage: "arrow.triangle.pull")
        } else {
            Table(items) {
                TableColumn("#") { Text("\(provider == .gitlab ? "!" : "#")\($0.number)").monospacedDigit() }.width(60)
                TableColumn("Title") { item in
                    HStack {
                        if item.isDraft { Text("Draft").font(.caption2).foregroundStyle(.secondary) }
                        Text(item.title)
                    }
                }
                TableColumn("Branch") { Text($0.sourceBranch).font(.callout.monospaced()) }
                TableColumn("Author") { Text($0.author) }.width(120)
                TableColumn("State") { Text($0.state) }.width(70)
                TableColumn("Updated") { item in
                    if let d = item.updatedAt { Text(d, style: .relative) }
                }
                .width(110)
                TableColumn("") { item in
                    HStack(spacing: Spacing.xs) {
                        Button("Checkout") { checkout(item) }
                            .help("Check out \(item.sourceBranch) locally")
                        if let url = item.url { Button("Open") { NSWorkspace.shared.open(url) } }
                    }
                }
                .width(140)
            }
        }
    }

    private var service: ProviderCLIService { ProviderCLIService(repo: repo.url, provider: provider) }

    private func checkout(_ item: PullRequestItem) {
        let service = service
        dismiss()
        Task {
            await store.perform(repo.id, "checkout \(provider == .gitlab ? "!" : "#")\(item.number)", success: "Checked out \(item.sourceBranch)") { _ in
                try await service.checkout(item.number)
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await service.pullRequests(state: state)
            error = nil
        } catch {
            items = []
            self.error = error.localizedDescription
        }
    }
}

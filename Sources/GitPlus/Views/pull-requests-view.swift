import AppKit
import SwiftUI

/// Compact popover listing GitHub PRs (via `gh`) or GitLab MRs (via `glab`).
struct PullRequestsView: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let provider: GitProvider
    var dismiss: () -> Void = {}

    @State private var state = "open"
    @State private var items: [PullRequestItem] = []
    @State private var error: String?
    @State private var isLoading = false

    private var prefix: String { provider == .gitlab ? "!" : "#" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 520, height: 440)
        .task(id: state) { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(provider.reviewNoun).font(.system(size: 15, weight: .semibold))
                if !items.isEmpty {
                    Text("\(items.count)").font(.system(size: 11, weight: .bold).monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(.secondary.opacity(0.18)))
                }
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                IconButton(symbol: "arrow.clockwise", help: "Refresh (via \(provider.cliName ?? "CLI"))") { Task { await load() } }
                Button {
                    Task {
                        do { try await service.createForCurrentBranch() } catch { self.error = error.localizedDescription }
                    }
                } label: {
                    Label("New", systemImage: "plus")
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .help("Open the new \(provider == .gitlab ? "merge" : "pull") request form for the current branch in your browser (push it first)")
            }
            Picker("", selection: $state) {
                Text("Open").tag("open")
                Text("Merged").tag("merged")
                Text("Closed").tag("closed")
                Text("All").tag("all")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .focusEffectDisabled()
        }
        .padding(14)
    }

    @ViewBuilder private var content: some View {
        if let error {
            ContentUnavailableView {
                Label("Couldn’t load \(provider.reviewNoun.lowercased())", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error).font(.callout)
            }
        } else if isLoading && items.isEmpty {
            ProgressView()
        } else if items.isEmpty {
            ContentUnavailableView("No \(state == "all" ? "" : state + " ")\(provider.reviewNoun.lowercased())",
                                   systemImage: "arrow.triangle.pull")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        row(item)
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
    }

    private func row(_ item: PullRequestItem) -> some View {
        Button {
            if let url = item.url { NSWorkspace.shared.open(url) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon(item))
                    .font(.system(size: 15))
                    .foregroundStyle(color(item))
                    .frame(width: 20)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                        if item.isDraft {
                            Text("Draft").font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .overlay(Capsule().stroke(.secondary.opacity(0.5)))
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 4) {
                        Text("\(prefix)\(item.number)").monospacedDigit()
                        Text("·")
                        Label(item.sourceBranch, systemImage: "arrow.triangle.branch").labelStyle(.titleAndIcon).lineLimit(1)
                        Text("·")
                        Text(item.author)
                        if let date = item.updatedAt {
                            Text("·")
                            Text(RelativeTime.string(date))
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary).padding(.top, 2)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .help("Open \(prefix)\(item.number) in the browser")
        .contextMenu {
            Button("Check Out \(item.sourceBranch)") { checkout(item) }
            if let url = item.url {
                Button("Open in Browser") { NSWorkspace.shared.open(url) }
                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            }
        }
    }

    private func icon(_ item: PullRequestItem) -> String {
        switch item.state {
        case "merged": "arrow.triangle.merge"
        case "closed": "xmark.circle"
        default: item.isDraft ? "circle.dashed" : "arrow.triangle.pull"
        }
    }

    private func color(_ item: PullRequestItem) -> Color {
        switch item.state {
        case "merged": .purple
        case "closed": Theme.deleted
        default: item.isDraft ? .secondary : Theme.added
        }
    }

    private var service: ProviderCLIService { ProviderCLIService(repo: repo.url, provider: provider) }

    private func checkout(_ item: PullRequestItem) {
        let service = self.service, label = "checkout \(prefix)\(item.number)"
        dismiss()
        Task {
            await store.perform(repo.id, label, success: "Checked out \(item.sourceBranch)") { _ in try await service.checkout(item.number) }
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

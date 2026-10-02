import SwiftUI

/// Lists GitHub PRs (via `gh`) or GitLab MRs (via `glab`) for a repository.
struct PullRequestsView: View {
    let repoURL: URL
    let provider: GitProvider

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
                    if let url = item.url { Button("Open") { NSWorkspace.shared.open(url) } }
                }
                .width(60)
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await ProviderCLIService(repo: repoURL, provider: provider).pullRequests(state: state)
            error = nil
        } catch {
            items = []
            self.error = error.localizedDescription
        }
    }
}

/// Settings → shows `gh auth status` / `glab auth status`.
struct ProviderSettingsView: View {
    @State private var results: [String: (ok: Bool, message: String)] = [:]

    var body: some View {
        Form {
            ForEach(["gh", "glab"], id: \.self) { cli in
                Section(cli == "gh" ? "GitHub (gh)" : "GitLab (glab)") {
                    if let r = results[cli] {
                        Label(r.ok ? "Authenticated" : "Not ready", systemImage: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(r.ok ? .green : .red)
                        Text(r.message).font(.caption.monospaced()).textSelection(.enabled)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text("Run `\(cli) auth login` in Terminal to sign in.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 460)
        .task {
            for cli in ["gh", "glab"] { results[cli] = await ProviderCLIService.authStatus(cli) }
        }
    }
}

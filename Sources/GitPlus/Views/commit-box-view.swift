import SwiftUI

/// Summary / description / amend + commit button (⌘↩).
struct CommitBoxView: View {
    @Environment(WorkspaceStore.self) private var store
    let repo: RepoEntry
    let stagedCount: Int
    let hasChanges: Bool

    @State private var summary = ""
    @State private var details = ""
    @State private var amend = false

    private var status: RepoStatus? { store.statuses[repo.id] }
    private var branch: String { status?.branch ?? "HEAD" }
    /// Nothing staged → the button stages everything first.
    private var stagesAll: Bool { stagedCount == 0 && !amend }
    private var canCommit: Bool {
        !summary.trimmingCharacters(in: .whitespaces).isEmpty && (amend || hasChanges) && !store.busy.contains(repo.id)
            && (status?.conflicts ?? 0) == 0
    }
    /// Amending a commit that is already on the remote needs a force push afterwards.
    private var lastCommitPushed: Bool { amend && status?.upstream != nil && (status?.ahead ?? 0) == 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Summary (required)", text: $summary)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .padding(8)
                .background(field)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $details)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(4)
                if details.isEmpty {
                    Text("Description").foregroundStyle(.tertiary).padding(.horizontal, 9).padding(.vertical, 4).allowsHitTesting(false)
                }
            }
            .frame(height: 64)
            .background(field)
            HStack {
                Toggle("Amend last commit", isOn: $amend).toggleStyle(.checkbox).font(.system(size: 12))
                Spacer()
                if summary.count > 72 {
                    Text("\(summary.count)/72").font(.caption.monospacedDigit()).foregroundStyle(Theme.modified)
                        .help("Keep the summary under 72 characters")
                }
            }
            if lastCommitPushed {
                Label("The last commit is already pushed — amending requires a force push.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Theme.modified)
            }
            Button(action: commit) {
                Text(buttonTitle).font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!canCommit)
            .keyboardShortcut(.return, modifiers: .command)
            .help("⌘↩")
        }
        .padding(12)
        .onChange(of: amend) { _, on in
            guard on, summary.isEmpty else { return }
            Task {
                let last = await GitService(repo: repo.url).lastCommitMessage()
                summary = last.summary
                details = last.description
            }
        }
    }

    private var field: some View {
        RoundedRectangle(cornerRadius: 6).fill(Theme.contextLine)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.separator))
    }

    private var buttonTitle: AttributedString {
        let text = amend ? "Amend last commit on **\(branch)**"
            : stagesAll ? "Stage all & commit to **\(branch)**"
            : "Commit \(stagedCount) file\(stagedCount == 1 ? "" : "s") to **\(branch)**"
        return (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    private func commit() {
        let s = summary.trimmingCharacters(in: .whitespaces), d = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let stageFirst = stagesAll, isAmend = amend
        Task {
            let ok = await store.perform(repo.id, "commit", success: isAmend ? "Amended last commit" : "Committed to \(branch)") {
                if stageFirst { try await $0.stageAll() }
                try await $0.commit(summary: s, description: d, amend: isAmend)
            }
            if ok { summary = ""; details = ""; amend = false }
        }
    }
}

/// "Stash changes" sheet.
struct StashSheet: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let repo: RepoEntry
    @State private var message = ""
    @State private var includeUntracked = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stash Changes").font(.headline)
            TextField("Message (optional)", text: $message).textFieldStyle(.roundedBorder)
            Toggle("Include untracked files", isOn: $includeUntracked)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Stash") {
                    let m = message, u = includeUntracked
                    dismiss()
                    Task { await store.perform(repo.id, "stash", success: "Changes stashed") { try await $0.stash(message: m, includeUntracked: u) } }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

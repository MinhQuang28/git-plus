import AppKit
import SwiftUI

/// Main area for a selected commit (or range): header, file list column, diff.
struct CommitDetailView: View {
    let repoURL: URL
    let target: DiffTarget
    var commit: Commit? = nil
    var remote: RemoteInfo? = nil

    @State private var files: [ChangedFile] = []
    @State private var selectedFile: ChangedFile.ID?
    @State private var body_ = ""
    @State private var error: String?
    @State private var showFullMessage = false

    private var git: GitService { GitService(repo: repoURL) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.separator).frame(height: 1)
            HStack(spacing: 0) {
                ResizableColumn("width.fileList", initial: 300, range: 200...520) {
                    ChangedFileList(files: files, selection: $selectedFile)
                }
                Group {
                    if let file = files.first(where: { $0.id == selectedFile }) {
                        FileDiffView(source: .revision(git, target), file: file).id(target.head + file.id)
                    } else if let error {
                        Text(error).foregroundStyle(.red).padding()
                    } else {
                        ContentUnavailableView("Select a file", systemImage: "doc.text")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: target) { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(commit?.subject ?? target.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                if !body_.isEmpty {
                    Button { showFullMessage.toggle() } label: {
                        Image(systemName: showFullMessage ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Show commit description")
                }
                Spacer()
            }
            HStack(spacing: 12) {
                if let commit {
                    HStack(spacing: 5) {
                        AvatarView(name: commit.author, email: commit.email, size: 18)
                        Text(commit.author)
                    }
                    .help(commit.email)
                    HStack(spacing: 4) {
                        Image(systemName: "smallcircle.filled.circle")
                        Text(commit.shortHash).font(.system(size: 12, design: .monospaced))
                        Button { copy(commit.hash) } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.plain).help("Copy SHA")
                    }
                    Text(commit.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                } else {
                    Text(target.title).foregroundStyle(.secondary)
                }
                Spacer()
                let add = files.reduce(0) { $0 + $1.additions }, del = files.reduce(0) { $0 + $1.deletions }
                Text("+\(add)").foregroundStyle(Theme.added).monospacedDigit()
                Text("−\(del)").foregroundStyle(Theme.deleted).monospacedDigit()
                if let url = remote?.commitURL(target.head), commit != nil {
                    Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "safari") }
                        .buttonStyle(.plain).help("View on \(remote?.host ?? "web")")
                }
            }
            .font(.system(size: 12))
            if showFullMessage {
                ScrollView {
                    Text(body_).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.paneBackground)
    }

    private func load() async {
        do {
            let loaded = try await git.changedFiles(target)
            files = loaded
            if !loaded.contains(where: { $0.id == selectedFile }) { selectedFile = loaded.first?.id }
            error = nil
            if !target.isRange {
                let message = (try? await git.commitMessage(target.head)) ?? ""
                body_ = message.split(separator: "\n", maxSplits: 1).dropFirst().joined().trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                body_ = ""
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

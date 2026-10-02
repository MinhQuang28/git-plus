import AppKit
import SwiftUI

/// Changed files for a revision range + the diff of the selected file.
struct CommitDiffView: View {
    let repoURL: URL
    let target: DiffTarget
    var remote: RemoteInfo? = nil

    @State private var files: [ChangedFile] = []
    @State private var selectedFile: ChangedFile.ID?
    @State private var message = ""
    @State private var error: String?

    private var git: GitService { GitService(repo: repoURL) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            HSplitView {
                List(files, selection: $selectedFile) { FileRowView(file: $0) }
                    .frame(minWidth: 200, idealWidth: 260, maxWidth: 420)
                Group {
                    if let file = files.first(where: { $0.id == selectedFile }) {
                        FileDiffView(git: git, target: target, file: file).id(file.id)
                    } else if let error {
                        Text(error).foregroundStyle(.red).padding()
                    } else {
                        ContentUnavailableView("Select a file", systemImage: "doc.text")
                    }
                }
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(target.title).font(.headline).lineLimit(1)
                Spacer()
                Button("Copy SHA") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(target.head, forType: .string)
                }
                if let url = remote?.commitURL(target.head) {
                    Button("Open on Web") { NSWorkspace.shared.open(url) }
                }
            }
            if !message.isEmpty {
                Text(message).font(.callout).foregroundStyle(.secondary).lineLimit(4).textSelection(.enabled)
            }
            let add = files.reduce(0) { $0 + $1.additions }, del = files.reduce(0) { $0 + $1.deletions }
            Text("\(files.count) files  ").font(.caption) + Text("+\(add) ").font(.caption).foregroundColor(.green) + Text("−\(del)").font(.caption).foregroundColor(.red)
        }
        .padding(10)
    }

    private func load() async {
        do {
            files = try await git.changedFiles(target)
            selectedFile = files.first?.id
            if !target.isRange {
                let body = (try? await git.commitMessage(target.head)) ?? ""
                // Drop the subject line (already in the title).
                message = body.split(separator: "\n", maxSplits: 1).dropFirst().joined().trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct FileRowView: View {
    let file: ChangedFile

    var body: some View {
        HStack(spacing: 6) {
            Text(file.status)
                .font(.caption.monospaced().bold())
                .foregroundStyle(color)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text((file.path as NSString).lastPathComponent).lineLimit(1)
                Text(file.oldPath.map { "\($0) →" } ?? (file.path as NSString).deletingLastPathComponent)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer()
            Text("+\(file.additions)").font(.caption2.monospacedDigit()).foregroundStyle(.green)
            Text("−\(file.deletions)").font(.caption2.monospacedDigit()).foregroundStyle(.red)
        }
        .help(file.path)
    }

    private var color: Color {
        switch file.status {
        case "A": .green
        case "D": .red
        case "R", "C": .purple
        default: .orange
        }
    }
}

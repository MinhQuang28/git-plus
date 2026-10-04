import AppKit
import SwiftUI

/// File history (commits touching the file, following renames, with its diff) and blame.
struct FileInspectorView: View {
    let repo: RepoEntry
    let path: String
    @State var mode: FileInspection.Mode
    var remote: RemoteInfo? = nil
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s) {
                Image(systemName: mode == .history ? "clock.arrow.circlepath" : "person.text.rectangle").foregroundStyle(.secondary)
                Text(path).appFont(.body, weight: .medium).lineLimit(1).truncationMode(.head)
                Spacer()
                Picker("", selection: $mode) {
                    Text("History").tag(FileInspection.Mode.history)
                    Text("Blame").tag(FileInspection.Mode.blame)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Button("Done", action: dismiss).keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: 48)
            .background(Theme.headerBackground)
            Divider()
            switch mode {
            case .history: FileHistoryPane(repo: repo, path: path, remote: remote)
            case .blame: BlamePane(repo: repo, path: path)
            }
        }
        .frame(minWidth: 960, idealWidth: 1100, minHeight: 600, idealHeight: 720)
    }
}

struct FileHistoryPane: View {
    let repo: RepoEntry
    let path: String
    var remote: RemoteInfo?

    @State private var revisions: [FileRevision] = []
    @State private var selection: FileRevision.ID?
    @State private var error: String?
    @State private var isLoading = true

    private var git: GitService { GitService(repo: repo.url) }

    var body: some View {
        HStack(spacing: 0) {
            ResizableColumn("width.fileHistory", initial: 320, range: 240...480) {
                List(revisions, selection: $selection) { rev in
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        CommitListRow(commit: rev.commit)
                        if let old = rev.file.oldPath {
                            Label("renamed from \(old)", systemImage: "arrow.right.square").appFont(.caption).foregroundStyle(Theme.renamed)
                        } else if rev.file.path != path {
                            Text(rev.file.path).appFont(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                        }
                    }
                    .listRowSeparator(.visible)
                }
                .listStyle(.plain)
                .overlay {
                    if isLoading { ProgressView() } else if revisions.isEmpty { Text(error ?? "No history").foregroundStyle(.secondary).padding() }
                }
            }
            Group {
                if let rev = revisions.first(where: { $0.id == selection }) {
                    FileDiffView(source: .revision(git, .commit(rev.commit)), file: rev.file).id(rev.id)
                } else {
                    ContentUnavailableView("Select a Commit", systemImage: "clock.arrow.circlepath")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            do {
                revisions = try await git.fileHistory(path)
                selection = revisions.first?.id
            } catch {
                if error is CancellationError { return }
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }
}

/// `git blame` with one gutter block per run of lines from the same commit.
struct BlamePane: View {
    @Environment(\.diffFontSize) private var fontSize
    let repo: RepoEntry
    let path: String

    @State private var lines: [BlameLine] = []
    /// Block number per line (alternating background per commit run).
    @State private var blocks: [Int] = []
    @State private var error: String?
    @State private var isLoading = true
    @State private var focusedHash: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                Text(error).foregroundStyle(.red).padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            row(line, startsBlock: index == 0 || lines[index - 1].hash != line.hash, block: index < blocks.count ? blocks[index] : 0)
                        }
                    }
                    .textSelection(.enabled)
                }
                .neutralScrollIndicator()
            }
        }
        .background(Theme.contextLine)
        .task {
            do {
                let loaded = try await GitService(repo: repo.url).blame(path)
                var block = 0
                blocks = loaded.indices.map { i in
                    if i > 0, loaded[i].hash != loaded[i - 1].hash { block += 1 }
                    return block
                }
                lines = loaded
            } catch {
                if error is CancellationError { return }
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func row(_ line: BlameLine, startsBlock: Bool, block: Int) -> some View {
        let isFocused = focusedHash == line.hash
        return HStack(alignment: .top, spacing: 0) {
            HStack(spacing: Spacing.xs) {
                if startsBlock {
                    if line.isUncommitted {
                        Text("Not committed yet").foregroundStyle(Theme.modified)
                    } else {
                        Text(line.shortHash).foregroundStyle(Color.accentColor)
                        Text(line.author).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(RelativeTime.string(line.date)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .appFont(.caption)
            .frame(width: 260, alignment: .leading)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, 1.5)
            .contentShape(Rectangle())
            .onTapGesture { focusedHash = isFocused ? nil : line.hash }
            .help(line.isUncommitted ? "" : "\(line.shortHash) \(line.summary)\n\(line.author) · \(line.date.formatted(date: .abbreviated, time: .shortened))")
            .contextMenu {
                if !line.isUncommitted {
                    Button("Copy SHA") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(line.hash, forType: .string)
                    }
                }
            }
            Text("\(line.number)")
                .foregroundStyle(Theme.gutterText)
                .frame(width: 46, alignment: .trailing)
                .padding(.trailing, Spacing.s)
            Text(line.text.isEmpty ? " " : line.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1.5)
        }
        .font(.system(size: fontSize, design: .monospaced))
        .background(isFocused ? Color.accentColor.opacity(0.14) : block % 2 == 0 ? Theme.contextLine : Theme.gutter)
        .overlay(alignment: .top) { if startsBlock { Rectangle().fill(Theme.separator).frame(height: 0.5) } }
    }
}

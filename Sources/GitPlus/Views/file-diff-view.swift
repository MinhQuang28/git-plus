import SwiftUI

enum DiffDisplayMode: String, CaseIterable { case unified = "Unified", split = "Split" }

/// Where a file diff comes from: a commit/range, or the working tree.
enum DiffSource {
    case revision(GitService, DiffTarget)
    case workingTree(GitService)

    func load(_ file: ChangedFile, context: Int) async throws -> String {
        switch self {
        case .revision(let git, let target): try await git.diff(target, file: file, context: context)
        case .workingTree(let git): try await git.workingDiff(file, context: context)
        }
    }
}

/// Diff of one file, GitHub Desktop style: path header with a settings menu, colored rows.
struct FileDiffView: View {
    let source: DiffSource
    let file: ChangedFile
    /// Changes when the underlying content may have changed (forces reload).
    var reloadKey = 0

    @AppStorage("diffMode") private var mode = DiffDisplayMode.unified
    @AppStorage("syntaxHighlight") private var syntaxHighlight = true
    @AppStorage("diffFullFile") private var fullContext = false

    @State private var lines: [DiffLine] = []
    @State private var rows: [SplitDiffRow] = []
    @State private var styles: [Int: AttributedString] = [:]
    @State private var truncated = false
    @State private var error: String?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.separator).frame(height: 1)
            body(for: mode)
        }
        .background(Theme.contextLine)
        .task(id: "\(fullContext)|\(syntaxHighlight)|\(reloadKey)") { await load() }
    }

    private var header: some View {
        HStack(spacing: 0) {
            let dir = (file.path as NSString).deletingLastPathComponent
            if !dir.isEmpty { Text(dir + "/").foregroundStyle(.secondary) }
            Text((file.path as NSString).lastPathComponent)
            if let old = file.oldPath { Text("  ← \(old)").foregroundStyle(.secondary) }
            Spacer()
            Menu {
                Picker("Layout", selection: $mode) {
                    ForEach(DiffDisplayMode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.inline)
                Divider()
                Toggle("Syntax Highlighting", isOn: $syntaxHighlight)
                Toggle("Show Whole File", isOn: $fullContext)
            } label: { Image(systemName: "gearshape") }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .font(.system(size: 13))
        .lineLimit(1)
        .truncationMode(.head)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Theme.headerBackground)
    }

    @ViewBuilder private func body(for mode: DiffDisplayMode) -> some View {
        if let error {
            Text(error).foregroundStyle(.red).padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if isLoading && lines.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if lines.isEmpty {
            ContentUnavailableView("No textual changes", systemImage: "equal.square", description: Text("Binary file or mode change only."))
        } else {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if mode == .split {
                        ForEach(rows) { SplitDiffRowView(row: $0, styles: styles) }
                    } else {
                        ForEach(lines) { DiffLineView(line: $0, styled: styles[$0.id]) }
                    }
                    if truncated {
                        Text("Diff truncated — too many lines.").foregroundStyle(.secondary).padding()
                    }
                }
                .textSelection(.enabled)
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let raw = try await source.load(file, context: fullContext ? 100_000 : 3)
            let path = file.path, syntax = syntaxHighlight
            let prepared = await Task.detached {
                let parsed = DiffParser.parse(raw)
                let rows = SplitDiffBuilder.rows(parsed.lines)
                return (parsed, rows, DiffRenderer.render(parsed.lines, rows: rows, path: path, syntax: syntax))
            }.value
            lines = prepared.0.lines
            truncated = prepared.0.truncated
            rows = prepared.1
            styles = prepared.2
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

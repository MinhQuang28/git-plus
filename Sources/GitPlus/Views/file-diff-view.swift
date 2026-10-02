import AppKit
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

/// Diff of one file: header with display settings, colored rows, hunk / line staging in the Changes tab.
struct FileDiffView: View {
    @Environment(WorkspaceStore.self) private var store
    let source: DiffSource
    let file: ChangedFile
    /// Set for working-tree diffs so staging actions can run through the store.
    var repoID: UUID? = nil
    /// Changes when the underlying content may have changed (forces reload).
    var reloadKey = 0

    @AppStorage("diffMode") private var mode = DiffDisplayMode.unified
    @AppStorage("syntaxHighlight") private var syntaxHighlight = true
    @AppStorage("diffFullFile") private var fullContext = false
    @AppStorage("diffFontSize") private var fontSize = 12.5

    @State private var raw = ""
    @State private var lines: [DiffLine] = []
    @State private var rows: [SplitDiffRow] = []
    @State private var styles: [Int: AttributedString] = [:]
    @State private var truncated = false
    @State private var error: String?
    @State private var isLoading = true
    @State private var selected = Set<Int>()
    @State private var anchor: Int?

    /// Hunk / line staging is available for modified files in the Changes tab.
    var canStage: Bool { repoID != nil && file.supportsPartialStaging }

    var body: some View {
        VStack(spacing: 0) {
            DiffHeaderView(file: file, mode: $mode, syntaxHighlight: $syntaxHighlight, fullContext: $fullContext, fontSize: $fontSize)
            Rectangle().fill(Theme.separator).frame(height: 1)
            content
        }
        .background(Theme.contextLine)
        .environment(\.diffFontSize, fontSize)
        .overlay(alignment: .bottom) {
            if canStage && !selected.isEmpty {
                LineSelectionBar(count: selected.count, area: file.area,
                                 apply: { action in perform(action, ids: selected) }, clear: { selected = [] })
            }
        }
        .task(id: "\(fullContext)|\(syntaxHighlight)|\(reloadKey)") { await load() }
    }

    @ViewBuilder private var content: some View {
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
                        ForEach(rows) { row in
                            if let hunk = row.full, hunk.kind == .hunk {
                                HunkRow(line: hunk, gutters: 1) { hunkActions(hunk.id) }
                            } else {
                                SplitDiffRowView(row: row, styles: styles)
                            }
                        }
                    } else {
                        ForEach(lines) { line in
                            if line.kind == .hunk || line.kind == .meta {
                                HunkRow(line: line, gutters: 2) { if line.kind == .hunk { hunkActions(line.id) } }
                            } else {
                                DiffLineView(line: line, styled: styles[line.id], isSelected: selected.contains(line.id),
                                             onSelect: canStage && line.kind != .context ? { select(line.id) } : nil)
                            }
                        }
                    }
                    if truncated {
                        Text("Diff truncated — too many lines.").foregroundStyle(.secondary).padding()
                    }
                }
                .textSelection(.enabled)
                .padding(.bottom, selected.isEmpty ? 0 : 60)
            }
        }
    }

    @ViewBuilder private func hunkActions(_ hunkID: Int) -> some View {
        if canStage {
            let ids = PatchBuilder.changeLines(inHunk: hunkID, raw: raw)
            if file.area == .unstaged {
                HunkActionButton(title: "Discard", symbol: "arrow.uturn.backward", destructive: true) { perform(.discard, ids: ids) }
                HunkActionButton(title: "Stage Hunk", symbol: "plus") { perform(.stage, ids: ids) }
            } else {
                HunkActionButton(title: "Unstage Hunk", symbol: "minus") { perform(.unstage, ids: ids) }
            }
        }
    }

    /// Click toggles a line; ⇧-click selects every change line between the anchor and this one.
    private func select(_ id: Int) {
        if NSEvent.modifierFlags.contains(.shift), let anchor {
            let range = min(anchor, id)...max(anchor, id)
            selected.formUnion(lines.filter { range.contains($0.id) && ($0.kind == .added || $0.kind == .removed) }.map(\.id))
        } else if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
        anchor = id
    }

    private func perform(_ action: LineAction, ids: Set<Int>) {
        guard let repoID else { return }
        DiffStagingActions.run(action, ids: ids, raw: raw, store: store, repoID: repoID)
        selected = []
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let text = try await source.load(file, context: fullContext ? 100_000 : 3)
            let path = file.path, syntax = syntaxHighlight
            let prepared = await Task.detached {
                let parsed = DiffParser.parse(text)
                let rows = SplitDiffBuilder.rows(parsed.lines)
                return (parsed, rows, DiffRenderer.render(parsed.lines, rows: rows, path: path, syntax: syntax))
            }.value
            raw = text
            lines = prepared.0.lines
            truncated = prepared.0.truncated
            rows = prepared.1
            styles = prepared.2
            selected = selected.filter { id in lines.contains { $0.id == id && $0.kind != .context } }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

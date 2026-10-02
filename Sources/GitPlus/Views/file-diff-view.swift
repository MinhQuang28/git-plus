import SwiftUI

enum DiffDisplayMode: String, CaseIterable { case unified = "Unified", split = "Split" }

/// Loads and renders a diff for one file, unified or side-by-side, with syntax highlighting.
struct FileDiffView: View {
    let git: GitService
    let target: DiffTarget
    let file: ChangedFile

    @AppStorage("diffMode") private var mode = DiffDisplayMode.unified
    @AppStorage("syntaxHighlight") private var syntaxHighlight = true

    @State private var lines: [DiffLine] = []
    @State private var rows: [SplitDiffRow] = []
    @State private var highlights: [Int: AttributedString] = [:]
    @State private var truncated = false
    @State private var error: String?
    @State private var fullContext = false
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(file.path).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer()
                Toggle("Syntax", isOn: $syntaxHighlight).toggleStyle(.checkbox)
                Toggle("Full file", isOn: $fullContext).toggleStyle(.checkbox)
                Picker("Mode", selection: $mode) {
                    ForEach(DiffDisplayMode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            Divider()
            content
        }
        .task(id: fullContext) { await load() }
    }

    private var activeHighlights: [Int: AttributedString] { syntaxHighlight ? highlights : [:] }

    @ViewBuilder private var content: some View {
        if let error {
            Text(error).foregroundStyle(.red).padding()
        } else if isLoading && lines.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if lines.isEmpty {
            ContentUnavailableView("No textual changes", systemImage: "equal.square")
        } else if mode == .split {
            // Split mode wraps long lines so both columns stay aligned.
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { SplitDiffRowView(row: $0, highlights: activeHighlights) }
                    truncationNotice
                }
                .textSelection(.enabled)
            }
        } else {
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { DiffLineView(line: $0, highlighted: activeHighlights[$0.id]) }
                    truncationNotice
                }
                .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder private var truncationNotice: some View {
        if truncated {
            Text("Diff truncated — too many lines.").foregroundStyle(.secondary).padding()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let raw = try await git.diff(target, file: file, context: fullContext ? 100_000 : 3)
            let path = file.path
            let prepared = await Task.detached {
                let parsed = DiffParser.parse(raw)
                return (parsed, SplitDiffBuilder.rows(parsed.lines), DiffHighlighter.highlight(parsed.lines, path: path))
            }.value
            lines = prepared.0.lines
            truncated = prepared.0.truncated
            rows = prepared.1
            highlights = prepared.2
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

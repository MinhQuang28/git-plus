import SwiftUI

/// Loads and renders a unified diff for one file with line numbers.
struct FileDiffView: View {
    let git: GitService
    let target: DiffTarget
    let file: ChangedFile

    @State private var lines: [DiffLine] = []
    @State private var truncated = false
    @State private var error: String?
    @State private var fullContext = false
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(file.path).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer()
                Toggle("Full file", isOn: $fullContext).toggleStyle(.checkbox)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            Divider()
            content
        }
        .task(id: fullContext) { await load() }
    }

    @ViewBuilder private var content: some View {
        if let error {
            Text(error).foregroundStyle(.red).padding()
        } else if isLoading && lines.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if lines.isEmpty {
            ContentUnavailableView("No textual changes", systemImage: "equal.square")
        } else {
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines) { DiffLineView(line: $0) }
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
            let raw = try await git.diff(target, file: file, context: fullContext ? 100_000 : 3)
            let parsed = await Task.detached { DiffParser.parse(raw) }.value
            lines = parsed.lines
            truncated = parsed.truncated
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct DiffLineView: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            gutter(line.oldNumber)
            gutter(line.newNumber)
            Text(marker).frame(width: 16).foregroundStyle(foreground)
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(foreground)
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.vertical, line.kind == .hunk ? 3 : 0)
        .background(background)
    }

    private func gutter(_ n: Int?) -> some View {
        Text(n.map(String.init) ?? "")
            .frame(width: 48, alignment: .trailing)
            .padding(.trailing, 6)
            .foregroundStyle(.tertiary)
            .background(Color.secondary.opacity(0.06))
    }

    private var marker: String {
        switch line.kind {
        case .added: "+"
        case .removed: "−"
        default: ""
        }
    }

    private var foreground: Color {
        switch line.kind {
        case .hunk, .meta: .secondary
        default: .primary
        }
    }

    private var background: Color {
        switch line.kind {
        case .added: .green.opacity(0.15)
        case .removed: .red.opacity(0.15)
        case .hunk: .blue.opacity(0.08)
        default: .clear
        }
    }
}

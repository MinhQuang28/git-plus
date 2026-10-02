import SwiftUI

private let diffFont = Font.system(size: 12, design: .monospaced)

private func lineBackground(_ kind: DiffLineKind?) -> Color {
    switch kind {
    case .added: .green.opacity(0.15)
    case .removed: .red.opacity(0.15)
    case .hunk: .blue.opacity(0.08)
    case nil: .secondary.opacity(0.05)   // empty side of a split row
    default: .clear
    }
}

private func gutter(_ n: Int?) -> some View {
    Text(n.map(String.init) ?? "")
        .frame(width: 48, alignment: .trailing)
        .padding(.trailing, 6)
        .foregroundStyle(.tertiary)
        .background(Color.secondary.opacity(0.06))
}

/// Line content: highlighted when available, dimmed for hunk/meta lines.
private func lineText(_ line: DiffLine, _ highlighted: AttributedString?) -> Text {
    if let highlighted { return Text(highlighted) }
    let text = Text(line.text.isEmpty ? " " : line.text)
    return line.kind == .hunk || line.kind == .meta ? text.foregroundColor(.secondary) : text
}

/// Unified diff row: old no. | new no. | marker | text (no wrapping, scrolls horizontally).
struct DiffLineView: View {
    let line: DiffLine
    let highlighted: AttributedString?

    var body: some View {
        HStack(spacing: 0) {
            gutter(line.oldNumber)
            gutter(line.newNumber)
            Text(marker(line.kind)).frame(width: 16).foregroundStyle(.secondary)
            lineText(line, highlighted).fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
        .font(diffFont)
        .padding(.vertical, line.kind == .hunk ? 3 : 0)
        .background(lineBackground(line.kind))
    }
}

/// Side-by-side row: old version left, new version right; long lines wrap.
struct SplitDiffRowView: View {
    let row: SplitDiffRow
    let highlights: [Int: AttributedString]

    var body: some View {
        if let full = row.full {
            HStack(spacing: 0) {
                lineText(full, nil).padding(.leading, 60)
                Spacer(minLength: 0)
            }
            .font(diffFont)
            .padding(.vertical, 3)
            .background(lineBackground(full.kind))
        } else {
            HStack(alignment: .top, spacing: 0) {
                side(row.left, number: row.left?.oldNumber)
                Divider()
                side(row.right, number: row.right?.newNumber)
            }
            .font(diffFont)
        }
    }

    private func side(_ line: DiffLine?, number: Int?) -> some View {
        HStack(alignment: .top, spacing: 0) {
            gutter(number).frame(maxHeight: .infinity, alignment: .top)
            Text(line.map { marker($0.kind) } ?? "").frame(width: 16).foregroundStyle(.secondary)
            Group {
                if let line { lineText(line, highlights[line.id]) } else { Text(" ") }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(lineBackground(line?.kind))
    }
}

private func marker(_ kind: DiffLineKind) -> String {
    switch kind {
    case .added: "+"
    case .removed: "−"
    default: ""
    }
}

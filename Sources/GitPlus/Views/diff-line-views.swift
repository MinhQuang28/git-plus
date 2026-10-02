import SwiftUI

private let diffFont = Font.system(size: 12.5, design: .monospaced)
private let gutterWidth: CGFloat = 46

private func lineColor(_ kind: DiffLineKind?) -> Color {
    switch kind {
    case .added: Theme.addedLine
    case .removed: Theme.removedLine
    case .hunk: Theme.hunkLine
    case nil: Theme.emptySide          // empty side of a split row
    default: Theme.contextLine
    }
}

private func gutterColor(_ kind: DiffLineKind?) -> Color {
    switch kind {
    case .added: Theme.addedGutter
    case .removed: Theme.removedGutter
    case .hunk: Theme.hunkLine
    case nil: Theme.emptySide
    default: Theme.gutter
    }
}

private func marker(_ kind: DiffLineKind) -> String {
    switch kind {
    case .added: "+"
    case .removed: "−"
    default: " "
    }
}

/// Line number cell; fills the row height so wrapped lines keep a continuous gutter.
private func gutter(_ n: Int?, _ kind: DiffLineKind?) -> some View {
    Text(n.map(String.init) ?? "")
        .foregroundStyle(Theme.gutterText)
        .frame(width: gutterWidth, alignment: .trailing)
        .padding(.trailing, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(gutterColor(kind))
}

/// Wrapped line content with syntax + changed-word styling.
private func content(_ line: DiffLine, _ styled: AttributedString?) -> some View {
    let text: Text = if let styled, !styled.characters.isEmpty { Text(styled) } else { Text(line.text.isEmpty ? " " : line.text) }
    return text
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 1.5)
}

/// Hunk header (`@@ -1,3 +1,3 @@`) spanning the full width.
private struct HunkRow: View {
    let line: DiffLine
    let gutters: Int

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: CGFloat(gutters) * (gutterWidth + 8) + 20)
            Text(line.text).foregroundStyle(Theme.gutterText).lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(diffFont)
        .padding(.vertical, 5)
        .background(Theme.hunkLine)
    }
}

/// Unified row: old no. | new no. | marker | text — the GitHub Desktop layout.
struct DiffLineView: View {
    let line: DiffLine
    let styled: AttributedString?

    var body: some View {
        if line.kind == .hunk || line.kind == .meta {
            HunkRow(line: line, gutters: 2)
        } else {
            HStack(alignment: .top, spacing: 0) {
                gutter(line.oldNumber, line.kind)
                gutter(line.newNumber, line.kind)
                Text(marker(line.kind)).frame(width: 20).padding(.vertical, 1.5)
                content(line, styled)
            }
            .font(diffFont)
            .background(lineColor(line.kind))
        }
    }
}

/// Side-by-side row: old version left, new version right.
struct SplitDiffRowView: View {
    let row: SplitDiffRow
    let styles: [Int: AttributedString]

    var body: some View {
        if let full = row.full {
            HunkRow(line: full, gutters: 1)
        } else {
            HStack(alignment: .top, spacing: 0) {
                side(row.left, number: row.left?.oldNumber)
                Rectangle().fill(Theme.separator).frame(width: 1)
                side(row.right, number: row.right?.newNumber)
            }
            .font(diffFont)
        }
    }

    private func side(_ line: DiffLine?, number: Int?) -> some View {
        HStack(alignment: .top, spacing: 0) {
            gutter(number, line?.kind)
            Text(line.map { marker($0.kind) } ?? " ").frame(width: 20).padding(.vertical, 1.5)
            if let line { content(line, styles[line.id]) } else { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(lineColor(line?.kind))
    }
}

import AppKit
import SwiftUI

/// Lines picked by dragging across the diff (or ⇧-clicking), copied with ⌘C or right-click → Copy.
/// SwiftUI's own text selection stops at each line's `Text`, so a multi-line selection is drawn by the diff.
struct DiffCopySelection: Equatable {
    /// Split view: which column the drag started in (only that version is copied).
    enum Side { case left, right }

    var anchor: Int
    var head: Int
    var side: Side = .right

    /// Line / row ids are increasing positions in the diff, so a range of ids is a range of rows.
    var range: ClosedRange<Int> { min(anchor, head)...max(anchor, head) }

    /// Unified diff: the code of the selected lines, without +/− markers or hunk headers.
    static func text(_ lines: [DiffLine], in range: ClosedRange<Int>) -> String {
        lines.filter { range.contains($0.id) && $0.kind != .hunk && $0.kind != .meta }.map(\.text).joined(separator: "\n")
    }

    /// Split diff: one column's version of the selected rows (empty sides are skipped).
    static func text(_ rows: [SplitDiffRow], in range: ClosedRange<Int>, side: Side) -> String {
        rows.filter { range.contains($0.id) && $0.full == nil }
            .compactMap { side == .left ? $0.left?.text : $0.right?.text }
            .joined(separator: "\n")
    }
}

/// Where each row sits in the diff's content, recorded as rows appear. A plain reference type on purpose:
/// writes during layout must not re-render the diff.
final class DiffRowFrames {
    fileprivate var frames: [Int: ClosedRange<CGFloat>] = [:]
    fileprivate var width: CGFloat = 0

    func reset() { frames = [:] }

    /// The row under `y`, or the nearest laid-out row (dragging past the first / last visible row).
    fileprivate func id(at y: CGFloat) -> Int? {
        if let hit = frames.first(where: { $0.value.contains(y) }) { return hit.key }
        return frames.min { distance($0.value, y) < distance($1.value, y) }?.key
    }

    private func distance(_ r: ClosedRange<CGFloat>, _ y: CGFloat) -> CGFloat { y < r.lowerBound ? r.lowerBound - y : y - r.upperBound }
}

private let diffContentSpace = "diffContent"

private struct DiffTextSelectionModifier: ViewModifier {
    @Binding var selection: DiffCopySelection?
    let frames: DiffRowFrames
    let isSplit: Bool
    let allIDs: ClosedRange<Int>?
    let copyText: (DiffCopySelection) -> String
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .coordinateSpace(.named(diffContentSpace))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { frames.width = $0 }
            // One gesture for both: a drag selects rows, a click clears (⇧-click extends instead).
            // Buttons and the line-staging gutter inside rows keep their own clicks.
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged(dragChanged)
                .onEnded(dragEnded))
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onCopyCommand { selection.map { [NSItemProvider(object: copyText($0) as NSString)] } ?? [] }
            .onCommand(#selector(NSResponder.selectAll(_:))) { selectAll() }
            .onExitCommand { selection = nil }
            .contextMenu {
                Button("Copy") { copy() }.disabled(selection == nil)
                Button("Select All") { selectAll() }.disabled(allIDs == nil)
            }
    }

    private func dragChanged(_ drag: DragGesture.Value) {
        guard hypot(drag.translation.width, drag.translation.height) >= 3,
              let head = frames.id(at: drag.location.y) else { return }
        if var current = selection, current.anchor == frames.id(at: drag.startLocation.y) {
            current.head = head
            selection = current
        } else if let anchor = frames.id(at: drag.startLocation.y) {
            let side: DiffCopySelection.Side = isSplit && drag.startLocation.x < frames.width / 2 ? .left : .right
            selection = DiffCopySelection(anchor: anchor, head: head, side: side)
        }
    }

    private func dragEnded(_ drag: DragGesture.Value) {
        focused = true
        guard hypot(drag.translation.width, drag.translation.height) < 3 else { return }
        if NSEvent.modifierFlags.contains(.shift), var current = selection, let head = frames.id(at: drag.location.y) {
            current.head = head
            selection = current
        } else if NSEvent.modifierFlags.contains(.shift), let id = frames.id(at: drag.location.y) {
            let side: DiffCopySelection.Side = isSplit && drag.location.x < frames.width / 2 ? .left : .right
            selection = DiffCopySelection(anchor: id, head: id, side: side)
        } else {
            selection = nil
        }
    }

    private func selectAll() {
        guard let allIDs else { return }
        selection = DiffCopySelection(anchor: allIDs.lowerBound, head: allIDs.upperBound, side: selection?.side ?? .right)
        focused = true
    }

    private func copy() {
        guard let selection else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyText(selection), forType: .string)
    }
}

extension View {
    /// On the diff's row stack: drag / ⇧-click to select rows, ⌘C or the context menu to copy, ⌘A for all.
    func diffTextSelection(_ selection: Binding<DiffCopySelection?>, frames: DiffRowFrames, isSplit: Bool,
                           allIDs: ClosedRange<Int>?, copyText: @escaping (DiffCopySelection) -> String) -> some View {
        modifier(DiffTextSelectionModifier(selection: selection, frames: frames, isSplit: isSplit, allIDs: allIDs, copyText: copyText))
    }

    /// On each row inside `diffTextSelection`: reports where the row is so drags can find it.
    func diffSelectableRow(_ id: Int, frames: DiffRowFrames) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named(diffContentSpace)) } action: { rect in
            frames.frames[id] = rect.minY...rect.maxY
        }
    }
}

/// Text-selection tint over selected rows (or one side of a split row).
struct DiffCopyHighlight: View {
    var body: some View {
        Color(nsColor: .selectedTextBackgroundColor).opacity(0.6).allowsHitTesting(false)
    }
}

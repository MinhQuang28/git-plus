import AppKit
import SwiftUI

enum DiffDisplayMode: String, CaseIterable { case unified = "Unified", split = "Split" }

/// Where a file diff comes from: a commit/range, or the working tree.
enum DiffSource {
    case revision(GitService, DiffTarget)
    case workingTree(GitService)

    func load(_ file: ChangedFile, context: Int, ignoreWhitespace: Bool = false) async throws -> String {
        switch self {
        case .revision(let git, let target): try await git.diff(target, file: file, context: context, ignoreWhitespace: ignoreWhitespace)
        case .workingTree(let git): try await git.workingDiff(file, context: context, ignoreWhitespace: ignoreWhitespace)
        }
    }

    var git: GitService {
        switch self {
        case .revision(let git, _), .workingTree(let git): git
        }
    }

    /// Git object specs for the old and new version of a file (nil = doesn't exist / read from disk).
    func blobSpecs(_ file: ChangedFile) -> (old: String?, new: String?, newOnDisk: Bool) {
        let oldPath = file.oldPath ?? file.path
        switch self {
        case .revision(_, let target):
            return (file.status == "A" ? nil : "\(target.base):\(oldPath)", file.status == "D" ? nil : "\(target.head):\(file.path)", false)
        case .workingTree:
            switch file.area {
            case .staged: return (file.status == "A" ? nil : "HEAD:\(oldPath)", file.status == "D" ? nil : ":\(file.path)", false)
            default: return (file.status == "?" ? nil : ":\(oldPath)", nil, file.status != "D")
            }
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
    @AppStorage("diffIgnoreWhitespace") private var ignoreWhitespace = false

    @State private var raw = ""
    /// Syntax setting the current `styles` were rendered with (nil = nothing rendered yet).
    @State private var renderedSyntax: Bool?
    @State private var lines: [DiffLine] = []
    @State private var rows: [SplitDiffRow] = []
    @State private var styles: [Int: AttributedString] = [:]
    @State private var truncated = false
    @State private var error: String?
    @State private var isLoading = true
    @State private var selected = Set<Int>()
    @State private var anchor: Int?

    /// Hunk / line staging is available for modified files in the Changes tab
    /// (not while whitespace is ignored: the shown diff would not apply).
    var canStage: Bool { repoID != nil && file.supportsPartialStaging && !ignoreWhitespace }

    /// Computed once per load (not per render): hunk line ids and the change map.
    @State private var hunkIDs: [Int] = []
    @State private var marks: [ChangeMark] = []
    @State private var currentHunk = 0
    @State private var scrollTarget: Int?

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp", "ico", "icns", "pdf", "svg"]
    private var isImage: Bool { Self.imageExtensions.contains((file.path as NSString).pathExtension.lowercased()) }

    var body: some View {
        VStack(spacing: 0) {
            DiffHeaderView(file: file, mode: $mode, syntaxHighlight: $syntaxHighlight, fullContext: $fullContext, fontSize: $fontSize,
                           ignoreWhitespace: $ignoreWhitespace, hunkCount: hunkIDs.count, currentHunk: currentHunk,
                           jump: jump)
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
        .task(id: "\(fullContext)|\(syntaxHighlight)|\(ignoreWhitespace)|\(reloadKey)") { await load() }
    }

    @ViewBuilder private var content: some View {
        if let error {
            Text(error).foregroundStyle(.red).padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if isLoading && lines.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isImage && !lines.contains(where: { $0.kind != .meta }) {
            ImageDiffView(source: source, file: file)
        } else if lines.isEmpty {
            ContentUnavailableView(ignoreWhitespace ? "Only whitespace changed" : "No textual changes", systemImage: "equal.square",
                                   description: Text(ignoreWhitespace ? "Turn off “Ignore Whitespace” to see the changes." : "Binary file or mode change only."))
        } else {
            ScrollViewReader { proxy in
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
                .overlay(alignment: .trailing) {
                    ChangeMarkerStrip(marks: marks) { id in proxy.scrollTo(id, anchor: .top) }
                }
                .onChange(of: scrollTarget) { _, id in
                    if let id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .top) } }
                }
            }
        }
    }

    /// ±1 → previous / next hunk.
    private func jump(_ delta: Int) {
        let ids = hunkIDs
        guard !ids.isEmpty else { return }
        currentHunk = min(max(currentHunk + delta, 0), ids.count - 1)
        scrollTarget = nil
        scrollTarget = ids[currentHunk]
    }

    @ViewBuilder private func hunkActions(_ hunkID: Int) -> some View {
        if canStage {
            // Line ids are resolved on click, not on every render (splitting `raw` is O(diff size)).
            let ids = { PatchBuilder.changeLines(inHunk: hunkID, raw: raw) }
            if file.area == .unstaged {
                HunkActionButton(title: "Discard", symbol: "arrow.uturn.backward", destructive: true) { perform(.discard, ids: ids()) }
                HunkActionButton(title: "Stage Hunk", symbol: "plus") { perform(.stage, ids: ids()) }
            } else {
                HunkActionButton(title: "Unstage Hunk", symbol: "minus") { perform(.unstage, ids: ids()) }
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
            let text = try await source.load(file, context: fullContext ? 100_000 : 3, ignoreWhitespace: ignoreWhitespace)
            let syntax = syntaxHighlight
            // Reloads (activation, unrelated revisions) often return the same text: skip re-highlighting.
            if text == raw, renderedSyntax == syntax, error == nil { return }
            let prepared = try await Self.prepare(text, path: file.path, syntax: syntax)
            raw = text
            renderedSyntax = syntax
            lines = prepared.0.lines
            truncated = prepared.0.truncated
            rows = prepared.1
            styles = prepared.2
            let changeIDs = Set(lines.lazy.filter { $0.kind == .added || $0.kind == .removed }.map(\.id))
            selected = selected.filter { changeIDs.contains($0) }
            hunkIDs = lines.filter { $0.kind == .hunk }.map(\.id)
            marks = ChangeMark.build(lines)
            currentHunk = 0
            error = nil
        } catch {
            if error is CancellationError { return }   // superseded by a newer load
            self.error = error.localizedDescription
        }
    }

    /// Parse → split rows → highlight, off the main actor. Runs as a child of the view's task,
    /// so switching files cancels it between stages instead of finishing a stale highlight.
    nonisolated private static func prepare(_ text: String, path: String, syntax: Bool) async throws
        -> ((lines: [DiffLine], truncated: Bool), [SplitDiffRow], [Int: AttributedString]) {
        let parsed = DiffParser.parse(text)
        try Task.checkCancellation()
        let rows = SplitDiffBuilder.rows(parsed.lines)
        try Task.checkCancellation()
        return (parsed, rows, DiffRenderer.render(parsed.lines, rows: rows, path: path, syntax: syntax))
    }
}

/// A stretch of the change map: where in the diff (as fractions) and what kind of change.
struct ChangeMark: Hashable {
    enum Kind: UInt8 { case added = 1, removed = 2, mixed = 3 }
    let start: Double
    let end: Double
    let kind: Kind
    /// First changed line in the stretch (scroll target).
    let lineID: Int

    /// Buckets the diff into at most `buckets` slots so even 20 000-line diffs draw a few hundred rects.
    static func build(_ lines: [DiffLine], buckets: Int = 300) -> [ChangeMark] {
        let n = lines.count
        guard n > 0 else { return [] }
        let count = min(buckets, n)
        var kinds = [UInt8](repeating: 0, count: count)
        var firstLine = [Int](repeating: -1, count: count)
        for (i, line) in lines.enumerated() where line.kind == .added || line.kind == .removed {
            let b = i * count / n
            kinds[b] |= line.kind == .added ? 1 : 2
            if firstLine[b] < 0 { firstLine[b] = line.id }
        }
        var marks: [ChangeMark] = []
        var b = 0
        while b < count {
            guard let kind = Kind(rawValue: kinds[b]) else { b += 1; continue }
            var e = b + 1
            while e < count, kinds[e] == kinds[b] { e += 1 }   // merge equal neighbours
            marks.append(ChangeMark(start: Double(b) / Double(count), end: Double(e) / Double(count), kind: kind, lineID: firstLine[b]))
            b = e
        }
        return marks
    }
}

/// Thin strip on the right edge of a diff marking where additions / removals are; click to jump.
struct ChangeMarkerStrip: View {
    let marks: [ChangeMark]
    let jump: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                for mark in marks {
                    let rect = CGRect(x: 2, y: mark.start * size.height, width: size.width - 4,
                                      height: max((mark.end - mark.start) * size.height, 1.5))
                    let color = switch mark.kind {
                    case .added: Theme.added
                    case .removed: Theme.deleted
                    case .mixed: Theme.modified
                    }
                    context.fill(Path(rect), with: .color(color))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                // Jump to the first change at or after the tapped position.
                let fraction = location.y / max(geo.size.height, 1)
                if let target = marks.first(where: { $0.end >= fraction }) ?? marks.last { jump(target.lineID) }
            }
        }
        .frame(width: 10)
        .background(Theme.gutter)
        .help("Changes in this file — click to jump")
        .accessibilityHidden(true)
    }
}

/// Before / after preview for image files.
struct ImageDiffView: View {
    let source: DiffSource
    let file: ChangedFile
    @State private var old: NSImage?
    @State private var new: NSImage?
    @State private var loaded = false

    var body: some View {
        HStack(spacing: Spacing.l) {
            pane("Before", old, tint: Theme.deleted)
            pane("After", new, tint: Theme.added)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: file.id) { await load() }
    }

    private func pane(_ title: String, _ image: NSImage?, tint: Color) -> some View {
        VStack(spacing: Spacing.s) {
            HStack(spacing: Spacing.xs) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(title).font(.headline)
                if let image { Text("\(Int(image.size.width))×\(Int(image.size.height))").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            }
            ZStack {
                RoundedRectangle(cornerRadius: Radius.m).fill(Theme.gutter)
                if let image {
                    Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit).padding(Spacing.m)
                } else if loaded {
                    Text("No image").foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .overlay(RoundedRectangle(cornerRadius: Radius.m).stroke(tint.opacity(0.5)))
        }
    }

    private func load() async {
        let git = source.git
        let specs = source.blobSpecs(file)
        if let spec = specs.old, let data = await git.blob(spec) { old = NSImage(data: data) }
        if specs.newOnDisk {
            new = NSImage(contentsOf: git.repo.appendingPathComponent(file.path))
        } else if let spec = specs.new, let data = await git.blob(spec) {
            new = NSImage(data: data)
        }
        loaded = true
    }
}

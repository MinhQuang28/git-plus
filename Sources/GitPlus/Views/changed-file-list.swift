import SwiftUI

/// "N changed files" list: file-type icon, name + dimmed folder, status letter on the right.
struct ChangedFileList: View {
    let files: [ChangedFile]
    @Binding var selection: ChangedFile.ID?
    var contextMenu: ((ChangedFile) -> AnyView)? = nil

    var body: some View {
        let shared = FileNameLabel.sharedFolder(files)
        VStack(spacing: 0) {
            header(shared)
            Rectangle().fill(Theme.separator).frame(height: 1)
            List(files, selection: $selection) { file in
                row(file, showsFolder: shared == nil)
                    .listRowSeparator(.visible)
                    .contextMenu { contextMenu?(file) }
            }
            .listStyle(.plain)
        }
    }

    private func header(_ shared: String?) -> some View {
        HStack(spacing: Spacing.xs) {
            Spacer()
            Text("\(files.count) changed file\(files.count == 1 ? "" : "s")").appFont(.callout)
            if let shared {
                Text("in \(shared)").appFont(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 36)
        .background(Theme.headerBackground)
    }

    private func row(_ file: ChangedFile, showsFolder: Bool) -> some View {
        HStack(spacing: 6) {
            FileNameLabel(file: file, showsFolder: showsFolder)
            Spacer(minLength: 4)
            if file.additions + file.deletions > 0 {
                Text("+\(file.additions) −\(file.deletions)").appFont(.caption, monospacedDigit: true).foregroundStyle(.secondary)
            }
            FileStatusLetter(status: file.status)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .help(file.oldPath.map { "\($0) → \(file.path)" } ?? file.path)
    }
}

/// File-type icon beside the file name, with its dimmed folder on the line below; deleted files are struck through.
/// Names truncate in the middle so the distinguishing tail (dates, extension) stays visible.
struct FileNameLabel: View {
    let file: ChangedFile
    /// Off when every file in the list shares one folder (it is shown once above the list instead).
    var showsFolder = true

    /// The folder all `files` live in, when there is exactly one (and it isn't the repository root).
    static func sharedFolder(_ files: [ChangedFile]) -> String? {
        guard let first = files.first else { return nil }
        let dir = (first.path as NSString).deletingLastPathComponent
        guard !dir.isEmpty, files.allSatisfy({ ($0.path as NSString).deletingLastPathComponent == dir }) else { return nil }
        return dir
    }

    var body: some View {
        let dir = (file.path as NSString).deletingLastPathComponent
        HStack(spacing: 6) {
            FileTypeIcon(path: file.path)
            VStack(alignment: .leading, spacing: 0) {
                Text((file.path as NSString).lastPathComponent)
                    .strikethrough(file.status == "D")
                    .foregroundStyle(file.status == "D" ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if showsFolder, !dir.isEmpty {
                    Text(dir).appFont(size: 11).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
            }
        }
    }
}

/// Single colored status letter, like VS Code's source-control list (M, A, U, D, R, C, T, !).
struct FileStatusLetter: View {
    let status: String
    /// `.increased` inside a selected List row: yellow/green would vanish on the accent highlight.
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Text(letter)
            .appFont(size: 12, weight: .semibold, design: .monospaced)
            .foregroundStyle(prominence == .increased ? .white : color)
            .frame(width: 14)
            .help(label)
            .accessibilityLabel(label)
    }

    private var letter: String {
        switch status {
        case "?": "U"
        case "U": "!"
        default: status
        }
    }

    private var color: Color {
        switch status {
        case "A", "?": Theme.added
        case "D", "U": Theme.deleted
        case "R", "C": Theme.renamed
        default: Theme.modified
        }
    }

    private var label: String {
        switch status {
        case "A": "Added"
        case "?": "Untracked"
        case "D": "Deleted"
        case "R": "Renamed"
        case "C": "Copied"
        case "T": "Type changed"
        case "U": "Conflict"
        default: "Modified"
        }
    }
}

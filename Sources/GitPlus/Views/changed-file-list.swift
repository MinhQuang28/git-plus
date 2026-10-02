import SwiftUI

/// "N changed files" list: dimmed directory + bright file name, status square on the right.
struct ChangedFileList: View {
    let files: [ChangedFile]
    @Binding var selection: ChangedFile.ID?
    /// When set, rows show a checkbox (Changes tab).
    var checked: Binding<Set<String>>? = nil
    var contextMenu: ((ChangedFile) -> AnyView)? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.separator).frame(height: 1)
            List(files, selection: $selection) { file in
                row(file)
                    .listRowSeparator(.visible)
                    .contextMenu { contextMenu?(file) }
            }
            .listStyle(.plain)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let checked {
                Toggle("", isOn: Binding(
                    get: { !files.isEmpty && checked.wrappedValue.count == files.count },
                    set: { checked.wrappedValue = $0 ? Set(files.map(\.id)) : [] }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
            }
            Spacer()
            Text("\(files.count) changed file\(files.count == 1 ? "" : "s")").font(.system(size: 13))
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(Theme.headerBackground)
    }

    private func row(_ file: ChangedFile) -> some View {
        HStack(spacing: 6) {
            if let checked {
                Toggle("", isOn: Binding(
                    get: { checked.wrappedValue.contains(file.id) },
                    set: { if $0 { checked.wrappedValue.insert(file.id) } else { checked.wrappedValue.remove(file.id) } }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
            }
            let dir = (file.path as NSString).deletingLastPathComponent
            (Text(dir.isEmpty ? "" : dir + "/").foregroundColor(.secondary) + Text((file.path as NSString).lastPathComponent))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            FileStatusIcon(status: file.status)
        }
        .padding(.vertical, 3)
        .help(file.oldPath.map { "\($0) → \(file.path)" } ?? file.path)
    }
}

struct FileStatusIcon: View {
    let status: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14))
            .foregroundStyle(color)
            .help(label)
    }

    private var symbol: String {
        switch status {
        case "A", "?": "plus.square"
        case "D": "minus.square"
        case "R", "C": "arrow.right.square"
        default: "dot.square"
        }
    }

    private var color: Color {
        switch status {
        case "A", "?": Theme.added
        case "D": Theme.deleted
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
        default: "Modified"
        }
    }
}

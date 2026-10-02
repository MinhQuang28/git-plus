import SwiftUI

struct CommitRowView: View {
    let commit: Commit
    /// Shown as a badge in group timelines.
    let repoName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if let repoName {
                    Text(repoName)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                }
                Text(commit.subject).lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(commit.shortHash).font(.caption.monospaced()).foregroundStyle(.secondary)
                Text(commit.author).font(.caption).foregroundStyle(.secondary)
                Text(commit.date, style: .relative).font(.caption).foregroundStyle(.tertiary)
                if commit.parents.count > 1 { Text("merge").font(.caption2).foregroundStyle(.purple) }
                ForEach(commit.refs.prefix(3), id: \.self) { ref in
                    Text(ref)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .background(ref.hasPrefix("tag:") ? Color.yellow.opacity(0.25) : Color.green.opacity(0.2), in: Capsule())
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

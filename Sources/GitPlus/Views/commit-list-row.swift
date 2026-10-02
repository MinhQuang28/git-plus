import SwiftUI

/// GitHub Desktop–style commit row: bold subject, avatar · author · relative time.
struct CommitListRow: View {
    let commit: Commit
    /// Shown as a badge in group activity timelines.
    var repoName: String? = nil
    /// Show branch badges (useful when listing all branches).
    var showsRefs = false
    /// The checked-out commit (shown with a HEAD marker).
    var isHead = false

    private var badges: [String] {
        commit.refs.filter { $0.hasPrefix("tag: ") || (showsRefs && !$0.hasSuffix("/HEAD") && $0 != "HEAD") }.prefix(3).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(commit.subject).font(.rowTitle).lineLimit(1)
                Spacer(minLength: 0)
                ForEach(badges, id: \.self) { ref in
                    let isTag = ref.hasPrefix("tag: ")
                    Label(isTag ? String(ref.dropFirst(5)) : ref, systemImage: isTag ? "tag" : "arrow.triangle.branch")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(isTag ? Theme.modified.opacity(0.18) : Color.accentColor.opacity(0.16)))
                        .foregroundStyle(isTag ? Theme.modified : Color.accentColor)
                        .lineLimit(1)
                }
            }
            HStack(spacing: 5) {
                if let repoName {
                    Text(repoName)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.tint.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
                }
                AvatarView(name: commit.author, email: commit.email, size: 16)
                Text("\(commit.author) • \(RelativeTime.string(commit.date))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if isHead {
                    Text("HEAD").font(.caption2.weight(.bold)).foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .overlay(Capsule().stroke(Color.accentColor.opacity(0.6)))
                }
            }
        }
        .padding(.vertical, 5)
        .help("\(commit.shortHash) — \(commit.subject)\n\(commit.author) <\(commit.email)>\n\(commit.date.formatted(date: .abbreviated, time: .shortened))")
    }
}

/// Local initials avatar (no network lookups, so commit emails never leave the machine).
struct AvatarView: View {
    let name: String
    let email: String
    var size: CGFloat = 18

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Text(initials).font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(.white)
            }
    }

    private var initials: String {
        let parts = name.split(whereSeparator: { $0 == " " || $0 == "\\" || $0 == "." }).prefix(2)
        let letters = parts.compactMap(\.first).map { String($0).uppercased() }.joined()
        return letters.isEmpty ? "?" : letters
    }

    private var color: Color {
        // Stable per-email hue.
        let hash = email.lowercased().unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.5, brightness: 0.75)
    }
}

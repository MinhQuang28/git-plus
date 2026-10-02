import SwiftUI
import Observation

/// Whether the "Current Repository" list is dropped down over the left column (⌘T toggles it).
@MainActor @Observable
final class SwitcherState {
    var isExpanded = false
}

/// Left column wrapper: the "Current Repository" header on top, then either the repository
/// list (expanded) or the column's own content — GitHub Desktop's layout, no permanent sidebar.
struct SwitcherColumn<Content: View>: View {
    @Environment(SwitcherState.self) private var switcher
    /// Keep the list open (e.g. nothing selected yet).
    var forceExpanded = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            RepositorySwitcherHeader(forceExpanded: forceExpanded)
            Divider()
            // Quick cross-fade between the column content and the list (no sliding).
            ZStack {
                if switcher.isExpanded || forceExpanded {
                    RepositoryListPanel().transition(.opacity)
                } else {
                    content.transition(.opacity)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .animation(.easeOut(duration: 0.15), value: switcher.isExpanded)
    }
}

struct RepositorySwitcherHeader: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(SwitcherState.self) private var switcher
    @AppStorage("selection") private var storedSelection = ""
    var forceExpanded = false
    @State private var hovering = false

    private var selection: SidebarSelection? { SidebarSelection(rawValue: storedSelection) }
    private var isOpen: Bool { switcher.isExpanded || forceExpanded }

    var body: some View {
        Button {
            guard !forceExpanded else { return }
            switcher.isExpanded.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .animation(.easeOut(duration: 0.15), value: isOpen)
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(hovering || isOpen ? Theme.barHover : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .help("Repositories and groups (⌘T)")
        .onReceive(NotificationCenter.default.publisher(for: .showRepositoryPicker)) { _ in switcher.isExpanded.toggle() }
    }

    private var caption: String {
        switch selection {
        case .repo: "Current Repository"
        case .group, .ungrouped: "Current Group"
        case nil: "Repositories"
        }
    }

    private var title: String {
        switch selection {
        case .repo(let id): store.repo(id)?.name ?? "Select a repository"
        case .group(let id): store.group(id)?.name ?? "Select a repository"
        case .ungrouped: "Ungrouped"
        case nil: "Select a repository"
        }
    }

    private var icon: String {
        switch selection {
        case .repo: "book.closed.fill"
        case .group: "folder.fill"
        case .ungrouped: "tray.fill"
        case nil: "square.stack.3d.up.fill"
        }
    }
}

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
            // Quick cross-fade between the column content and the list (no sliding). The content stays
            // mounted under the list, so its search, scroll position and selection survive opening the list.
            let isOpen = switcher.isExpanded || forceExpanded
            ZStack {
                content
                    .opacity(isOpen ? 0 : 1)
                    .disabled(isOpen)               // no clicks or keyboard focus while hidden
                    .accessibilityHidden(isOpen)
                if isOpen { RepositoryListPanel().transition(.opacity) }
            }
            .frame(maxHeight: .infinity)
        }
        .animation(.easeOut(duration: 0.15), value: switcher.isExpanded)
    }
}

/// A page selector binding that also closes the repository list — clicking a page (even the current
/// one) while the list is open shows that page's own list instead of leaving the repository list up.
@MainActor
func closingSwitcher<Value>(_ binding: Binding<Value>) -> Binding<Value> {
    Binding(get: { binding.wrappedValue }, set: {
        binding.wrappedValue = $0
        RepoActions.post(.hideRepositoryPicker)
    })
}

extension View {
    /// Main area beside a `SwitcherColumn`: dimmed while the repository list is open; a click closes the list.
    func dismissesSwitcher() -> some View { modifier(SwitcherDismissLayer()) }
}

private struct SwitcherDismissLayer: ViewModifier {
    @Environment(SwitcherState.self) private var switcher

    func body(content: Content) -> some View {
        content
            .overlay {
                if switcher.isExpanded {
                    Color.black.opacity(0.12)
                        .contentShape(Rectangle())
                        .onTapGesture { switcher.isExpanded = false }
                        .transition(.opacity)
                        .accessibilityLabel("Close repository list")
                        .accessibilityAddTraits(.isButton)
                }
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
                    .appFont(size: 17)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(caption).appFont(size: 11).foregroundStyle(.secondary)
                    Text(title).appFont(size: 14, weight: .semibold).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .appFont(size: 11, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .animation(Motion.safe(.easeOut(duration: 0.15)), value: isOpen)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 54)
            .background(hovering || isOpen ? Theme.barHover : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Repositories and groups (⌘T)")
        .onReceive(NotificationCenter.default.publisher(for: .showRepositoryPicker)) { _ in switcher.isExpanded.toggle() }
        .onReceive(NotificationCenter.default.publisher(for: .hideRepositoryPicker)) { _ in switcher.isExpanded = false }
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

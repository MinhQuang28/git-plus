import AppKit
import SwiftUI

/// A fixed-width column with a drag handle. The width is persisted per `storageKey`,
/// clamped to `range`, and never changes when the column's content changes.
struct ResizableColumn<Content: View>: View {
    @AppStorage private var width: Double
    let range: ClosedRange<Double>
    @ViewBuilder let content: Content
    @State private var dragStart: Double?

    init(_ storageKey: String, initial: Double, range: ClosedRange<Double>, @ViewBuilder content: () -> Content) {
        _width = AppStorage(wrappedValue: initial, storageKey)
        self.range = range
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            content.frame(width: min(max(width, range.lowerBound), range.upperBound))
            Rectangle()
                .fill(Theme.separator)
                .frame(width: 1)
                .overlay {
                    Color.clear
                        .frame(width: 8)
                        .contentShape(Rectangle())
                        .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                        .gesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                .onChanged { value in
                                    let start = dragStart ?? width
                                    dragStart = start
                                    width = min(max(start + value.translation.width, range.lowerBound), range.upperBound)
                                }
                                .onEnded { _ in dragStart = nil }
                        )
                }
        }
    }
}

/// Subtle background on hover — makes dense lists easier to scan.
struct HoverHighlight: ViewModifier {
    @State private var hovering = false
    var color = Theme.rowHover

    func body(content: Content) -> some View {
        content
            .background(hovering ? color : .clear)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverHighlight(_ color: Color = Theme.rowHover) -> some View { modifier(HoverHighlight(color: color)) }
}

/// Small borderless icon button with tooltip and hover state.
struct IconButton: View {
    let symbol: String
    let help: String
    var role: ButtonRole? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(hovering ? Theme.barHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? Theme.deleted : .secondary)
        .help(help)
        .onHover { hovering = $0 }
    }
}

/// Uppercase section title with count and trailing actions.
struct SectionHeader<Actions: View>: View {
    let title: String
    let count: Int
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.4)
            Text("\(count)")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(.secondary.opacity(0.18)))
            Spacer()
            actions
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 2)
    }
}

/// Transient confirmation shown at the bottom of the window.
struct ToastView: View {
    let toast: WorkspaceStore.Toast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? Theme.deleted : Theme.added)
            Text(toast.message).font(.system(size: 13, weight: .medium)).lineLimit(2)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Toggle rendered as a small pill (history view options).
struct OptionChip: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(isOn ? Color.accentColor.opacity(0.2) : Theme.headerBackground))
                .overlay(Capsule().stroke(isOn ? Color.accentColor.opacity(0.6) : Theme.separator))
                .foregroundStyle(isOn ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }
}

/// "Open in…" split button: click opens the preferred editor, the menu lists every installed app.
struct OpenInMenu: View {
    let repo: RepoEntry
    @AppStorage("preferredEditor") private var preferredEditor = ""
    @AppStorage("preferredTerminal") private var preferredTerminal = ""

    var body: some View {
        let editor = ExternalAppLauncher.preferredEditor(preferredEditor)
        Menu {
            if !ExternalAppLauncher.editors.isEmpty {
                Section("Editors") {
                    ForEach(ExternalAppLauncher.editors) { app in
                        Button { app.open(repo.url); preferredEditor = app.bundleID } label: { appLabel(app) }
                    }
                }
            }
            Section("Terminals") {
                ForEach(ExternalAppLauncher.terminals) { app in
                    Button { app.open(repo.url); preferredTerminal = app.bundleID } label: { appLabel(app) }
                }
            }
            Divider()
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([repo.url]) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(repo.path, forType: .string)
            }
        } label: {
            Label(editor.map { "Open in \($0.name)" } ?? "Open in…", systemImage: "arrow.up.forward.app")
        } primaryAction: {
            if let editor { editor.open(repo.url) } else { NSWorkspace.shared.activateFileViewerSelecting([repo.url]) }
        }
        .menuStyle(.button)
        .fixedSize()
        .help("Open the repository (⌘⇧E editor · ⌃` terminal · ⌘⇧R Finder)")
    }

    private func appLabel(_ app: ExternalApp) -> some View {
        Label {
            Text(app.name)
        } icon: {
            if let icon = app.icon { Image(nsImage: icon) } else { Image(systemName: "app") }
        }
    }
}

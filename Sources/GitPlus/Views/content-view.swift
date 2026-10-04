import SwiftUI

/// Window root: repository or group workspace. The repository list drops down from the
/// "Current Repository" header of the left column (no permanent sidebar).
/// Errors show as a non-blocking banner; ⌘K opens the command palette.
struct ContentView: View {
    @Environment(WorkspaceStore.self) private var store
    @AppStorage("selection") private var storedSelection = ""
    @State private var switcher = SwitcherState()
    @State private var showPalette = false
    @State private var showClone = false
    @State private var showActivity = false

    private var selection: Binding<SidebarSelection?> {
        Binding(get: { SidebarSelection(rawValue: storedSelection) }, set: { storedSelection = $0?.rawValue ?? "" })
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(switcher)
            .overlay(alignment: .bottom) {
                VStack(spacing: Spacing.s) {
                    if let failure = store.failure { FailureBanner(failure: failure).id(failure.id) }
                    if let toast = store.toast { ToastView(toast: toast).id(toast.id) }
                }
            }
            .overlay {
                if showPalette {
                    ZStack(alignment: .top) {
                        Color.black.opacity(0.12).ignoresSafeArea().onTapGesture { showPalette = false }
                        CommandPaletteView { showPalette = false }.padding(.top, 80)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.spring(duration: 0.3), value: store.toast)
            .animation(.spring(duration: 0.3), value: store.failure)
            .animation(.easeOut(duration: 0.12), value: showPalette)
            .task { await store.refreshStatus() }
            .onReceive(NotificationCenter.default.publisher(for: .showCommandPalette)) { _ in showPalette.toggle() }
            .onReceive(NotificationCenter.default.publisher(for: .showClone)) { _ in showClone = true }
            .onReceive(NotificationCenter.default.publisher(for: .showActivity)) { _ in showActivity = true }
            .sheet(isPresented: $showClone) { CloneSheet { showClone = false } }
            .sheet(isPresented: $showActivity) { ActivityView { showActivity = false } }
    }

    @ViewBuilder private var content: some View {
        switch selection.wrappedValue {
        case .repo(let id):
            if let repo = store.repo(id) { RepoWorkspaceView(repo: repo).id(repo.id) } else { placeholder }
        case .group(let id):
            if let group = store.group(id) { GroupWorkspaceView(groupID: id, selection: selection, title: group.name).id(id) } else { placeholder }
        case .ungrouped:
            GroupWorkspaceView(groupID: nil, selection: selection, title: "Ungrouped").id("ungrouped")
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        HStack(spacing: 0) {
            ResizableColumn("width.leftPane", initial: 320, range: 260...520) {
                SwitcherColumn(forceExpanded: true) { EmptyView() }
            }
            WelcomeView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// First-run / nothing-selected screen: the three ways to get a repository, plus a tool check.
struct WelcomeView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var tools: [String: Bool] = [:]

    var body: some View {
        VStack(spacing: Spacing.xl) {
            VStack(spacing: Spacing.s) {
                Image(systemName: "square.stack.3d.up.fill").appFont(size: 44).foregroundStyle(.tint).symbolRenderingMode(.hierarchical)
                Text(store.workspace.repos.isEmpty ? "Welcome to Git Plus" : "Pick a Repository").appFont(.largeTitle, weight: .semibold)
                Text(store.workspace.repos.isEmpty ? "Add the repositories you work on — or a whole folder of them."
                     : "Choose a repository or group from the list on the left, or press ⌘K.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: Spacing.m) {
                card("Add Existing", detail: "A repository or a parent folder to scan", symbol: "plus.rectangle.on.folder", keys: "⌘O") {
                    RepoActions.addRepositories(store)
                }
                card("Clone", detail: "From GitHub, GitLab or any URL", symbol: "square.and.arrow.down", keys: "⇧⌘O") {
                    RepoActions.post(.showClone)
                }
                card("New", detail: "Create an empty repository", symbol: "plus.square", keys: "⌘N") {
                    RepoActions.newRepository(store)
                }
            }
            HStack(spacing: Spacing.l) {
                ForEach(["git", "gh", "glab"], id: \.self) { tool in
                    HStack(spacing: Spacing.xs) {
                        if let ok = tools[tool] {
                            Image(systemName: ok ? "checkmark.circle.fill" : (tool == "git" ? "xmark.octagon.fill" : "minus.circle"))
                                .foregroundStyle(ok ? Theme.added : tool == "git" ? Theme.deleted : Color.secondary)
                        } else {
                            ProgressView().controlSize(.mini)
                        }
                        Text(tool).appFont(.callout, design: .monospaced)
                    }
                    .help(help(tool))
                }
            }
            .appFont(.callout)
        }
        .padding(Spacing.xl)
        .task {
            for tool in ["git", "gh", "glab"] { tools[tool] = await ProcessRunner.isAvailable(tool) }
        }
    }

    private func help(_ tool: String) -> String {
        switch tool {
        case "git": tools["git"] == false ? "git was not found — install the Xcode Command Line Tools (xcode-select --install)" : "git is installed"
        case "gh": tools["gh"] == true ? "GitHub CLI found (pull requests)" : "Optional: brew install gh — enables pull requests"
        default: tools["glab"] == true ? "GitLab CLI found (merge requests)" : "Optional: brew install glab — enables merge requests"
        }
    }

    private func card(_ title: String, detail: String, symbol: String, keys: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Image(systemName: symbol).appFont(.title2).foregroundStyle(.tint)
                Text(title).appFont(.headline)
                Text(detail).appFont(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                KeyboardHint(keys: keys)
            }
            .frame(width: 170, height: 150, alignment: .topLeading)
            .padding(Spacing.l)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Radius.l))
    }
}

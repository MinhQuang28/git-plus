# Git Plus

A native macOS 26+ Git client for people who juggle **many repositories at once**. Group your
projects, see every repo's state at a glance, and read diffs comfortably — with a Liquid Glass
interface that looks and behaves like the rest of macOS.

Everything runs through the command-line tools you already use — `git`, `gh` and `glab` — so your
git config, hooks, SSH keys and credential helpers behave exactly like in Terminal. Git Plus stores
no tokens and talks to no server of its own.

## Features

### Repository groups

- **Repository switcher** — click *Current Repository* (⌘T) and the repository list drops down over
  the left column: filter, **Recent**, one section per group, *Ungrouped*. Drag repositories between
  groups, double-click a group to rename it (including *Ungrouped*), click a group to open its overview.
- **Auto-Group by Remote** — one click groups repositories by `host/namespace`
  (`github.com/acme`, `gitlab.com/team/backend`, …).
- **Add a parent folder** — Git Plus scans it (three levels deep) and adds every repository it finds.
- **Group view** — branch, ahead/behind, uncommitted changes and last fetch for every repository;
  *Fetch All* and *Pull All* (fast-forward only) run in parallel.
- **Group activity** — recent commits of every repository in the group merged into one timeline.

### Changes

- **Conflicts / Staged / Changes** sections with stage, unstage and discard per file
  (hover button, double-click, or right-click).
- **Hunk and line staging** — stage, unstage or discard a whole hunk, or click the line-number
  gutter to pick individual lines (⇧-click selects a range).
- **Commit box** — summary + description, *Amend last commit* (warns when it is already pushed),
  stages everything automatically when nothing is staged.
- **Stashes** — stash with or without untracked files; apply, pop, drop, view the stashed diff.

### History

- Filter commits by message, author or SHA; show one branch or all branches.
- **Compare with a branch** — see what is *behind* and *ahead*.
- Select several commits (⌘/⇧-click) to see their **combined diff**.
- **Commit menu** — reset (soft / mixed / hard), checkout, revert, create branch, create tag,
  cherry-pick onto another branch, copy SHA / tag, view on GitHub or GitLab.

### Diff

- GitHub-style colors with **word-level highlighting** for small edits.
- Syntax highlighting for ~20 languages, unified or split layout, whole-file context,
  adjustable text size.

### Branches & sync

- Switch, create, merge, rebase, rename and delete branches (local and remote) from the branch list.
- One sync button that becomes **Fetch**, **Pull**, **Push** or **Publish** depending on state;
  optional auto-fetch every 10 minutes.
- A banner for interrupted **merge / rebase / cherry-pick / revert** with Continue, Skip and Abort;
  resolve conflicts with *Use Ours* / *Use Theirs* / *Mark as Resolved*.

### GitHub & GitLab

- Pull requests via `gh pr list`, merge requests via `glab mr list` — detected from the remote URL,
  including self-hosted GitLab. Settings → Accounts shows `gh auth status` / `glab auth status`.

## Requirements

- macOS 26 or later.
- `git` (Xcode Command Line Tools or Homebrew).
- Optional: `brew install gh glab`, then `gh auth login` / `glab auth login` for PR / MR lists.

## Install

> **Note for testers:** Git Plus is signed with a **local (non-notarized) certificate** — there
> is no Apple Developer ID behind it yet — so macOS blocks the app on first launch. That warning
> is expected; the steps below get past it. If you would rather not trust a pre-built binary,
> build from source instead.

### Option 1 — Download the pre-built app

**Step 1 — Install.** Download `GitPlus.zip` from the
[latest release](https://github.com/MinhQuang28/git-plus/releases), unzip it, and drag
`Git Plus.app` into your **Applications** folder.

**Step 2 — Unblock.** Clear the Gatekeeper quarantine flag (one-time):

```sh
xattr -dr com.apple.quarantine "/Applications/Git Plus.app"
```

Not comfortable with Terminal? Double-click the app once (macOS blocks it), then System Settings →
Privacy & Security → scroll down → **Open Anyway** → open the app again.

**Step 3 — Add repositories.** Press **⌘O** and pick repositories or a parent folder to scan.
When your repositories live in Desktop / Documents / Downloads, macOS asks once for access to that
folder — allow it.

### Option 2 — Build from source

Requires the Xcode 26 (or newer) Swift toolchain.

```sh
# One-time per machine: a stable signing identity so folder-access grants survive every
# rebuild (otherwise macOS may re-ask after each build).
tools/setup-signing-cert.sh

# Build the app into build/Git Plus.app (add --install to copy it to /Applications)
./build-app.sh

# Run it
open "build/Git Plus.app"
```

> **Check the signature:** `build-app.sh` looks for the **"Git Plus Local Signing"** identity in the
> login keychain and prints `==> signing with stable identity (…)` when it uses it. If it prints
> `==> ad-hoc signing` instead, run `tools/setup-signing-cert.sh` once and rebuild. Verify an
> installed build with `codesign -dvv "/Applications/Git Plus.app" 2>&1 | grep Authority`.

## Usage

Click **Current Repository** at the top of the left column (or press ⌘T) and pick a repository or
group. A repository has three views in the toolbar —
**Changes**, **History** and **Stashes** — next to the branch button, the sync button, the
pull/merge-request list and **Open in** (your editor, terminal or Finder).

Open repositories from the terminal:

```sh
open -a "Git Plus" ~/code/my-repo        # or a parent folder to scan
ln -s "$PWD/tools/gitplus" /usr/local/bin/gitplus && gitplus .
```

### Keyboard shortcuts

| Shortcut      | Action                              |
| ------------- | ----------------------------------- |
| ⌘O            | Add repositories / scan a folder    |
| ⌘1 / ⌘2 / ⌘3  | Changes / History / Stashes         |
| ⌘T / ⌘B       | Repository list / branch list       |
| ⌘⇧F / ⌘⇧L / ⌘⇧P | Fetch / Pull / Push               |
| ⌘↩            | Commit                              |
| ⌘⇧E / ⌃\`     | Open in editor / terminal           |
| ⌘⇧R           | Reveal in Finder                    |
| ⌘= / ⌘− / ⌘0  | Diff text size                      |
| ⌘R            | Refresh status of all repositories  |
| ⌘,            | Settings                            |

## Development

```sh
# Run the test suite (parsers, diff/patch building, real git integration tests in temp repos)
swift test

# Run from source without bundling
swift run GitPlus

# Regenerate the app icon (Resources/AppIcon.icns)
swift tools/make-icon.swift

# Package a release: test + build + zip + sha256 (local only)
tools/package-release.sh

# Same, and publish the GitHub release + upload the zip
tools/package-release.sh --publish
```

The version lives in one place: `VERSION=` in `build-app.sh`.

### Project layout

| Path                          | Purpose                                                              |
| ----------------------------- | -------------------------------------------------------------------- |
| `Sources/GitPlus/App/`        | App entry, menu commands and keyboard shortcuts                      |
| `Sources/GitPlus/Models/`     | Workspace (groups, repos), git models, remote URL parsing            |
| `Sources/GitPlus/Services/`   | git / gh / glab CLI wrappers, parsers, patch builder, syntax highlighter |
| `Sources/GitPlus/Stores/`     | `WorkspaceStore` — state, persistence, git operations across repos   |
| `Sources/GitPlus/Views/`      | Repository switcher, toolbar, changes / history / stash panes, diffs |
| `Tests/GitPlusTests/`         | Unit and integration tests                                           |
| `build-app.sh`                | Assemble & sign the `.app` bundle                                    |
| `tools/setup-signing-cert.sh` | Create the stable local signing certificate                          |
| `tools/package-release.sh`    | Test, build, zip, hash and (optionally) publish a release            |
| `tools/make-icon.swift`       | Generate the app icon                                                |
| `tools/gitplus`               | Shell helper to open folders in Git Plus                             |

The workspace (groups and repositories) is stored in
`~/Library/Application Support/GitPlus/workspace.json`.

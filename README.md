# Git Plus

Native macOS (SwiftUI) Git client for working with **many repositories grouped together**.
Everything runs through the CLIs you already use — `git`, `gh`, `glab` — so your git config,
hooks, SSH keys and credential helpers behave exactly like in Terminal. No tokens are stored by the app.

## Features
- **Native macOS 26+ design** – Liquid Glass sidebar and toolbar, system colors, light/dark.
- **Groups** – sidebar groups (drag & drop, double-click to rename, incl. "Ungrouped"), *Auto-Group by Remote*,
  folder scan. Group view: status table, *Fetch All* / *Pull All*, merged activity timeline.
- **Changes** – Conflicts / Staged / Changes sections; stage, unstage, discard per file, per hunk or per line
  (click the gutter, ⇧-click for ranges); commit with amend; stash with untracked files.
- **History** – filter by message/author/SHA, all branches, compare with another branch (behind/ahead),
  multi-commit range diff, commit menu: reset soft/mixed/hard, checkout, revert, branch, tag, cherry-pick, copy, view on web.
- **Diff** – GitHub-style colors, word-level highlight, syntax highlighting, unified/split, whole file, adjustable text size.
- **Branches** – switch, create, merge, rebase, rename, delete (local & remote); merge/rebase/cherry-pick banner with continue/skip/abort.
- **Sync** – Fetch / Pull / Push / Publish in one button, auto-fetch every 10 min.
- **GitHub / GitLab** – PRs via `gh`, MRs via `glab`.
- **Shortcuts** – ⌘1/2/3 tabs, ⌘T repos, ⌘B branches, ⌘⇧F/L/P fetch/pull/push, ⌘⇧E editor, ⌃` terminal, ⌘= / ⌘− text size.

## Requirements
macOS 26+, Swift 6.2+ toolchain (Xcode 26+). Optional: `brew install gh glab` and `gh auth login` / `glab auth login`.

## Build & run
```bash
swift run GitPlus                 # dev run
swift test                        # unit + integration tests (uses real git in a temp dir)
scripts/build-app.sh [--install]  # build/Git Plus.app (optionally copy to /Applications)
```

## Open from the terminal
```bash
open -a "Git Plus" ~/code/my-repo     # or a parent folder to scan
ln -s "$PWD/scripts/gitplus" /usr/local/bin/gitplus && gitplus .
```

## Layout
```
Sources/GitPlus/
  App/       app entry, menu commands, open-folder handling
  Models/    workspace (groups/repos), git models, remote URL parsing
  Services/  process runner (login-shell PATH), git CLI, parsers, gh/glab CLI, repo scanner
  Stores/    WorkspaceStore – persisted at ~/Library/Application Support/GitPlus/workspace.json
  Views/     sidebar, group dashboard/activity, history, commit & file diff, PR/MR list
```

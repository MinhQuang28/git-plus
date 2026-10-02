# Git Plus

Native macOS (SwiftUI) Git client for working with **many repositories grouped together**.
Everything runs through the CLIs you already use — `git`, `gh`, `glab` — so your git config,
hooks, SSH keys and credential helpers behave exactly like in Terminal. No tokens are stored by the app.

## Features
- **Groups** – organise repos into groups (drag & drop, context menu), or *Auto-Group by Remote*
  (`github.com/acme`, `gitlab.com/team/backend`…). Adding a parent folder scans it for repos (depth 3).
- **Group dashboard** – branch, ahead/behind, uncommitted changes for every repo; *Fetch All* / *Pull All* (ff-only) in parallel.
- **Group activity** – recent commits of all repos in a group merged into one timeline.
- **Commit diff** – history per repo (HEAD / all branches / any branch, message search), changed files with +/− stats,
  unified diff with line numbers, "full file" context. Select several commits (⌘/⇧-click) to diff the whole range.
- **Pull / Merge Requests** – `gh pr list` for GitHub, `glab mr list` for GitLab (detected from the remote URL).
  Settings (⌘,) shows `gh auth status` / `glab auth status`.

## Requirements
macOS 14+, Swift 6 toolchain (Xcode 16+). Optional: `brew install gh glab` and `gh auth login` / `glab auth login`.

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

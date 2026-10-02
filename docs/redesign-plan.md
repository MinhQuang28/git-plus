# Git Plus — UI/UX redesign & feature gap plan

Status of each item on branch `claude/redesign-ui-ux-oiva88` (✅ done · ⏳ not yet).

## Principles

- Native first: Liquid Glass, standard toolbar, repository switcher in the left column (from `main`).
- Every state comes with its next action (status card, error banner fixes, diverged prompt).
- Everything reachable from the keyboard (shortcuts, ⌘K command palette).
- Destructive actions are confirmed and, where possible, undoable (commit, Discard All).

## P0 — daily git flow gaps

| Item | Status |
| --- | --- |
| Force push with lease (menu, sync button, after amend) | ✅ |
| Pull with rebase / merge; diverged branches ask how to combine | ✅ |
| Push tags (single / all), delete tags locally and remotely | ✅ |
| Multi-select in Changes, bulk stage / unstage / stash / discard, Discard All (undoable) | ✅ |
| Undo last commit (menu, commit menu, toast) | ✅ |

## P1 — UX foundations

| Item | Status |
| --- | --- |
| Design tokens (`Spacing`, `Radius`, semantic fonts, status / lane colors) | ✅ |
| Error banner with explanation + one-click fixes instead of modal alerts | ✅ |
| Activity log (⌥⌘A) with duration and full stderr | ✅ |
| Status card with diverged / unpublished callouts | ✅ |
| Changes tab by default; stage button always visible (not hover-only) | ✅ |
| Accessibility labels on icon buttons, combined row elements | ✅ |

## P2 — modern features

| Item | Status |
| --- | --- |
| Command palette ⌘K (repos, groups, branches, commands; fuzzy) | ✅ |
| Commit graph (lanes, merges) | ✅ |
| Paged history + git-side search (`author:`, `path:`, SHA) | ✅ |
| Diff: jump between changes, change map, ignore whitespace, image preview | ✅ |
| Commit box: Commit & Push, Conventional Commit prefixes, co-authors | ✅ |

## Conflict resolution (GitHub Desktop style)

1. **Merge dialog** (⇧⌘M or the branch list): choose the branch to merge into the current one; a
   `git merge-tree` preview says whether it is clean or lists the files that will conflict; choose
   merge commit / squash / rebase.
2. **Resolve conflicts dialog** opens automatically when conflicts appear (also from the banner and
   the Changes tab). Each file offers *Use modified file from `<current branch>`* /
   *Use modified file from `<incoming branch>`* with real branch names, resolved from `MERGE_MSG`,
   `MERGE_HEAD`, `rebase-merge/head-name` + `onto`, `CHERRY_PICK_HEAD`. During a rebase git's
   ours / theirs are swapped; the names shown account for that.
3. **Delete / modify conflicts** (`DU`, `UD`, `AU`, `UA`, `DD`) offer *keep modified file* or
   *delete file* (`git rm`).
4. **Block by block**: each conflict block shows both sides; use one, the other, or both in either
   order; save writes the file and stages it.
5. **Continue / Abort / Skip** finish the operation; a rebase that stops again keeps the dialog open.

## P3 — performance

| Item | Status |
| --- | --- |
| FSEvents watcher on the open repository (debounced) | ✅ |
| Status refresh limited to 8 repositories in flight | ✅ |
| Status in 3 parallel processes instead of 5–6 sequential ones | ✅ |
| History paging (200 per page) | ✅ |

## P4 — advanced

| Item | Status |
| --- | --- |
| Clone, New repository, welcome screen with tool check | ✅ |
| File history (follows renames) and blame | ✅ |
| Interactive rebase (reorder, pick / reword / squash / fixup / drop), edit any commit message | ✅ |
| Create pull / merge request for the branch, check out a PR / MR | ✅ |
| Remotes management | ✅ |
| Group overview as cards with filters and activity sparkline (table still available) | ✅ |
| Pinned repositories | ✅ |
| Cancel a running git operation | ⏳ |
| Tree (folder) view of changed files | ⏳ |
| Submodules, worktrees, Git LFS awareness | ⏳ |
| Color-blind diff palette, density setting | ⏳ |
| Commit signing status (GPG / SSH) | ⏳ |

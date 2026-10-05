# Plan — AI commit messages (bring your own provider)

Status: phases 1–3 implemented (2026-10-05) · live provider check pending

## Goal

One click (or ⌥⌘G) in the commit box writes a commit summary + description from the changes
being committed, in the repository's own style (Conventional Commits, language, scopes). The
user edits it before committing; the feature never commits by itself.

Customers choose the **provider, model, and API key in Settings**. Git Plus ships no key and
runs no server.

## Providers

There is one client for the **OpenAI-compatible Chat Completions** format
(`POST {baseURL}/chat/completions`, `Authorization: Bearer <key>`), which covers:

| Preset | Base URL | Model |
|---|---|---|
| DeepSeek | `https://api.deepseek.com` | `deepseek-chat` by default (fast and cheap). `deepseek-reasoner` also works: only `content` is read, `reasoning_content` is ignored |
| OpenAI (GPT / Codex) | `https://api.openai.com/v1` | entered by the user or loaded from the list |
| Custom (OpenAI-compatible) | entered by the user | OpenRouter, Groq, local Ollama/LM Studio (`http://localhost:11434/v1`)… |

- **Model** is a text field plus a "Load models" button (`GET {baseURL}/models`) that fills a
  picker. Model names are not hard-coded, so new models work without a Git Plus release.
- **Request** is minimal so it works with every compatible endpoint. It sends only `model` and
  `messages` (system + user). It omits `temperature`/`max_tokens`, because some reasoning models
  reject them or use other names.
- **Output** is plain text in git's own format: line 1 is the summary, then a blank line, then
  the body. The parser removes code fences, quotes, and a leading "Commit message:". It
  validates that the summary is not empty and cuts it to ≤ 72 characters at a word boundary.
  JSON mode is not used, because providers support it differently.
- **Codex models that only accept the Responses API (`/v1/responses`).** v1 shows a clear error
  ("This model needs the Responses API — choose another model"). Responses API support is added
  in a later phase only if it is actually needed.

## UX

- A ✨ button inside the Summary field (left of the `tag` prefix menu). "Generate Commit Message"
  also goes in the Changes menu (⌥⌘G) and the command palette. When AI is not configured, the
  button opens Settings → AI.
- **Source** is the same as for the commit button: staged files, or everything when nothing is staged.
- **While generating:** the placeholder reads "Writing message…", the ✨ button shows a spinner
  and becomes "Stop" (cancels the request), and other git operations stay usable.
- **Result** fills the per-repo `CommitDraft`. If the user had already typed something, a toast
  offers **Undo** to restore the previous draft. A typed summary is sent as a hint ("intent: …").
- **Errors** use the existing failure banner:
  - 401/403 → "API key rejected — check Settings → AI"
  - 404 → "Model not found"
  - 402 → "Out of credit"
  - 429 → "Rate limited, try again in Ns"
  - 5xx/timeout → retry hint
  - offline → network message
- Request timeout is 60 s.

## Settings → new "AI" tab

- **Enable AI commit messages** is off by default. A one-line notice explains that the diff of
  the files being committed is sent to the provider you choose.
- Provider picker (DeepSeek / OpenAI / Custom) and Base URL (prefilled, editable for Custom).
- **Base URL validation:** must be `https://`. `http://` is allowed only for `localhost`/`127.0.0.1`.
- **API key:** `SecureField`, stored in the **macOS Keychain** with one item per provider
  (service `co.egohub.gitplus.ai`, account = provider id). It is never written to
  UserDefaults, plist, or logs, never shown again after saving, and has a "Remove key" button.
- Model: text field plus "Load models".
- A **Test** button sends a tiny prompt and shows "✓ Connected — <model>" or the error.
- Message language: Match repository history (default) / English / Vietnamese.
- Include description body: on/off.
- **Per-repository opt-out:** repo context menu → "Disable AI for this repository", for
  client/company code that must not leave the machine.

## What goes into the prompt

1. `git diff --cached --stat` (always complete).
2. `git diff --cached -M --no-color -U3` for text files, **excluding**:
   - lockfiles (`*.lock`, `package-lock.json`, `pnpm-lock.yaml`…)
   - minified/generated files (`*.min.*`, `dist/`, `build/`)
   - binaries (numstat `-`)
   - likely secrets (`.env*`, `*.pem`, `*.key`, `id_rsa*`, `*.p12`)

   Excluded files still appear by name in the stat.
3. Branch name (ticket ids like `feature/ABC-123`), the last 20 commit subjects (style,
   language, scopes), and the user's typed summary as intent.
4. **No silent truncation.** If the diff is over a budget (~200 KB of text, adjustable), ask:
   "Diff is very large — write the message from file names and stats only?" Do not cut it.

The system prompt asks for:
- Conventional Commits when the history uses them
- an imperative summary of ≤ 72 characters
- a body that explains *why*, wrapped at 72
- no invented details
- output of only the message

## Code layout (kebab-case files, each < 200 lines)

| File | Responsibility |
|---|---|
| `Models/ai-provider-settings.swift` | provider presets, base URL validation, `@AppStorage` keys |
| `Services/keychain-store.swift` | get / set / delete the API key (SecItem) |
| `Services/chat-completion-client.swift` | URLSession POST `/chat/completions`, GET `/models`, error mapping (status + provider error JSON), timeout, cancellation |
| `Services/commit-message-prompt.swift` | pure: file filtering, budget check, prompt assembly, output parsing |
| `Services/commit-message-generator.swift` | gathers diff/stat/log/branch via `GitService`, calls the client |
| `Stores/workspace-store-ai-commit.swift` | `generateCommitMessage(repoID)`, `generatingMessage: Set<UUID>`, cancel, undo of the previous draft |
| `Views/ai-settings-view.swift` | Settings → AI tab |
| edits | `commit-box-view.swift` (✨ button), `changes-commands.swift` (⌥⌘G), `command-palette-view.swift`, `settings-view.swift` (tab), repo context menu (opt-out) |

## Phases

1. **Plumbing** (~0.5 day): Keychain store, provider settings, client, AI settings tab with
   Test and Load models.
2. **Prompt + generator** (~0.5 day): filters, budget check, prompt, output parser.
3. **UI** (~0.5 day): ✨ button, menu/palette command, generating/stop state, undo toast, errors.
4. **Verify** (~0.5 day):
   - Unit tests on the pure parts: filters, prompt assembly, output parser (fences, quotes,
     long summary), URL validation, and error mapping from real recorded provider error bodies.
   - An opt-in live test that runs only when `GITPLUS_AI_KEY`/`GITPLUS_AI_BASE_URL` are set.
   - Manual runs on 3 real repos (small fix, big feature, lockfile-only change) with DeepSeek
     and OpenAI.
   - Release 0.6.0.

## Decisions (2026-10-05)

1. Default provider: DeepSeek (`deepseek-chat`).
2. Default message language: English.
3. AI pull-request descriptions: yes, as a follow-up on the same client and settings.

## Implementation notes

- **Long summaries are not cut.** The commit box's 72-character counter warns about them instead.
- **Inline credentials are masked.** Well-known token formats are replaced with `[REDACTED]` before sending (sk-…, AKIA…, ghp_…, glpat-…, xox…, shpat_…, private key blocks).
- **"Nothing staged" uses a temporary index.** The app copies the index and runs `git add -A` against the copy (`GIT_INDEX_FILE`); the real index is never touched.
- **The ✨ button is disabled while amending.**

import Foundation

/// "Write commit message with AI" (✨ in the commit box, ⌥⌘G). Fills the draft; never commits.
extension WorkspaceStore {
    func isWritingMessage(_ id: UUID) -> Bool { messageTasks[id] != nil }

    func cancelCommitMessage(_ id: UUID) {
        messageTasks[id]?.cancel()
        messageTasks[id] = nil
    }

    func generateCommitMessage(_ id: UUID, statsOnly: Bool = false) {
        guard messageTasks[id] == nil, let repo = repo(id) else { return }
        if AISettings.isDisabled(repoPath: repo.path) {
            showToast("AI is turned off for \(repo.name)", isError: true)
            return
        }
        let config: AIConfig
        do { config = try AISettings.current() } catch {
            failure = Failure(title: "AI commit messages aren't set up", detail: error.localizedDescription, repoID: id)
            return
        }
        let before = draft(for: id)
        let defaultSummary = UserDefaults.standard.string(forKey: CommitDefaults.summaryKey) ?? ""
        let intent = before.summary == defaultSummary ? "" : before.summary
        let generator = CommitMessageGenerator(repo: repo.url, config: config,
                                               language: AISettings.language, includeBody: AISettings.includeBody)
        let includeAll = trees[id]?.staged.isEmpty ?? true

        messageTasks[id] = Task {
            // A cancelled task's slot was already cleared (and may hold a newer request).
            defer { if !Task.isCancelled { messageTasks[id] = nil } }
            do {
                let message = try await generator.generate(intent: intent, includeAll: includeAll, statsOnly: statsOnly)
                try Task.checkCancellation()
                var draft = draft(for: id)
                draft.summary = message.summary
                draft.details = CommitMessagePrompt.details(body: message.body, keepingTrailersFrom: draft.details)
                commitDrafts[id] = draft
                let typed = !before.summary.isEmpty && before.summary != defaultSummary || !before.details.isEmpty
                if typed {
                    showToast("Commit message written — review it before committing", actionTitle: "Undo") {
                        self.commitDrafts[id] = before
                    }
                } else {
                    showToast("Commit message written — review it before committing")
                }
            } catch let error as AIError {
                if case .diffTooLarge = error {
                    showToast("\(error.localizedDescription) Write it from file names only?", actionTitle: "Use File Names") {
                        self.generateCommitMessage(id, statsOnly: true)
                    }
                } else {
                    failure = Failure(title: "Couldn't write the commit message", detail: error.localizedDescription, repoID: id)
                }
            } catch {
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { return }
                failure = Failure(title: "Couldn't write the commit message", detail: error.localizedDescription, repoID: id)
            }
        }
    }
}

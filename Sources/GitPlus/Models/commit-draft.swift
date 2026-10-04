import Foundation

/// The commit box contents for one repository, kept until the commit succeeds.
struct CommitDraft: Codable, Equatable {
    var summary = ""
    var details = ""
    var amend = false

    private static let key = "commitDrafts"

    static func load() -> [UUID: CommitDraft] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let drafts = try? JSONDecoder().decode([UUID: CommitDraft].self, from: data) else { return [:] }
        return drafts
    }

    static func save(_ drafts: [UUID: CommitDraft]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(drafts), forKey: key)
    }
}

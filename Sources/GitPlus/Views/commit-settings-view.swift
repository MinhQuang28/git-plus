import SwiftUI

/// UserDefaults keys for the default commit message.
enum CommitDefaults {
    static let summaryKey = "commit.defaultSummary"
    static let descriptionKey = "commit.defaultDescription"
}

/// Settings → Commit: text prefilled into the commit box on open and after every commit.
struct CommitSettingsView: View {
    @AppStorage(CommitDefaults.summaryKey) private var summary = ""
    @AppStorage(CommitDefaults.descriptionKey) private var details = ""

    var body: some View {
        Form {
            Section {
                TextField("Summary", text: $summary, prompt: Text("e.g. feat: "))
                LabeledContent("Description") {
                    TextEditor(text: $details)
                        .appFont(.callout)
                        .frame(minHeight: 110)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                }
            } header: {
                Text("Default commit message")
            } footer: {
                Text("Prefilled into the commit box when it opens and after each commit. Leave empty for a blank box.")
                    .appFont(.caption).foregroundStyle(.secondary)
            }
            if !summary.isEmpty || !details.isEmpty {
                Button("Clear Default Message", role: .destructive) { summary = ""; details = "" }
            }
        }
        .formStyle(.grouped)
    }
}

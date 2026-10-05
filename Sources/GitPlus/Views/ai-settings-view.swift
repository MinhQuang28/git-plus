import SwiftUI

/// Settings → AI: provider, base URL, API key (Keychain), model, message style.
struct AISettingsView: View {
    @AppStorage(AISettings.enabledKey) private var enabled = false
    @AppStorage(AISettings.providerKey) private var providerRaw = AIProvider.deepseek.rawValue
    @AppStorage(AISettings.baseURLKey) private var customBaseURL = ""
    @AppStorage(AISettings.modelKey) private var model = AIProvider.deepseek.defaultModel
    @AppStorage(AISettings.languageKey) private var language = AIMessageLanguage.english.rawValue
    @AppStorage(AISettings.includeBodyKey) private var includeBody = true

    @State private var keyInput = ""
    @State private var hasKey = false
    @State private var models: [String] = []
    @State private var result: (ok: Bool, message: String)?
    @State private var working = false

    private var provider: AIProvider { AIProvider(rawValue: providerRaw) ?? .deepseek }
    private var baseURLText: String { provider == .custom ? customBaseURL : provider.defaultBaseURL }
    private var baseURL: URL? { AISettings.validatedBaseURL(baseURLText) }

    var body: some View {
        Form {
            Section {
                Toggle("Write commit messages with AI", isOn: $enabled)
                Text("When you press ✨ (⌥⌘G), the changes being committed are sent to the provider below. Lockfiles, binaries and secret files (.env, *.pem, *.key…) are listed by name only, and known token formats are masked.")
                    .appFont(.caption).foregroundStyle(.secondary)
            }
            Section("Provider") {
                Picker("Provider", selection: $providerRaw) {
                    ForEach(AIProvider.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if provider == .custom {
                    TextField("Base URL", text: $customBaseURL, prompt: Text("https://openrouter.ai/api/v1"))
                    if !customBaseURL.isEmpty && baseURL == nil {
                        Text("Use https:// (http:// only for localhost), without user, password or query.")
                            .appFont(.caption).foregroundStyle(Theme.deleted)
                    }
                } else {
                    LabeledContent("Base URL") { Text(provider.defaultBaseURL).foregroundStyle(.secondary).textSelection(.enabled) }
                }
                LabeledContent("API key") { keyField }
                LabeledContent("Model") { modelField }
                HStack {
                    Button("Test Connection", action: test).disabled(working || !hasKey || baseURL == nil || model.isEmpty)
                    if working { ProgressView().controlSize(.small) }
                    if let result {
                        Label(result.message, systemImage: result.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.ok ? Theme.added : Theme.deleted)
                            .appFont(.caption).lineLimit(3).textSelection(.enabled)
                    }
                }
            }
            Section("Message") {
                Picker("Language", selection: $language) {
                    ForEach(AIMessageLanguage.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("Add a description body", isOn: $includeBody)
                Text("To keep a repository's code on this Mac, right-click it in the sidebar and turn off “Allow AI Commit Messages”.")
                    .appFont(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reloadKey)
        .onChange(of: providerRaw) {
            model = provider.defaultModel
            models = []
            result = nil
            reloadKey()
        }
    }

    @ViewBuilder private var keyField: some View {
        HStack {
            if hasKey && keyInput.isEmpty {
                Label("Saved in Keychain", systemImage: "lock.fill").foregroundStyle(.secondary)
                Spacer()
                Button("Remove", role: .destructive) { save("") }
            } else {
                SecureField("", text: $keyInput, prompt: Text("Paste your \(provider.title) API key"))
                    .onSubmit { save(keyInput) }
                Button("Save") { save(keyInput) }.disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let page = provider.keysPage {
                Link(destination: page) { Image(systemName: "arrow.up.right.square") }
                    .help("Create an API key on \(page.host() ?? "the provider's site")")
                    .accessibilityLabel("Get an API key")
            }
        }
    }

    @ViewBuilder private var modelField: some View {
        HStack {
            TextField("", text: $model, prompt: Text(provider.defaultModel.isEmpty ? "model id" : provider.defaultModel))
            Menu {
                if models.isEmpty { Text("Press “Load Models” first") }
                ForEach(models, id: \.self) { m in Button(m) { model = m } }
                Divider()
                Button("Load Models", action: loadModels).disabled(working || !hasKey || baseURL == nil)
            } label: {
                Label("Choose a model", systemImage: "list.bullet").labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Pick from the models your key can use")
        }
    }

    private func reloadKey() { hasKey = KeychainStore.hasKey(for: provider) }

    private func save(_ key: String) {
        do {
            try KeychainStore.setAPIKey(key, for: provider)
            keyInput = ""
            result = nil
        } catch {
            result = (false, error.localizedDescription)
        }
        reloadKey()
    }

    private func client() -> ChatCompletionClient? {
        guard let baseURL, let key = KeychainStore.apiKey(for: provider) else { return nil }
        return ChatCompletionClient(config: AIConfig(baseURL: baseURL, model: model.trimmingCharacters(in: .whitespaces), apiKey: key))
    }

    private func test() {
        guard let client = client() else { return }
        run {
            _ = try await client.complete(system: "Reply with the single word OK.", user: "ping")
            return "Connected — \(client.config.model)"
        }
    }

    private func loadModels() {
        guard let client = client() else { return }
        run {
            models = try await client.models()
            return "\(models.count) models available"
        }
    }

    private func run(_ work: @escaping @MainActor () async throws -> String) {
        working = true
        result = nil
        Task {
            do { result = (true, try await work()) } catch { result = (false, error.localizedDescription) }
            working = false
        }
    }
}

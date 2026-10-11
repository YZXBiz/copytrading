import DesktopCore
import Foundation

/// A setup read from a file the owner chose: each value under a label line ("Discord token:" and
/// the token on the next line), or after the label on the same line. It only fills the setup's
/// fields; Connect and Start Copying check them before anything is saved. Accounts always come
/// in as paper, so a file can never make an account trade real money.
struct SetupImport: Equatable {
    var channels: String?
    var authors: String?
    var discordToken: String?
    var provider: TradingProviderName?
    var modelName: String?
    var providerKeys: [TradingProviderName: String] = [:]
    var alpacaKey: String?
    var alpacaSecret: String?
    var guruName: String?

    /// The most a setup file can be; a larger file is not one.
    static let maximumBytes = 64 * 1024

    /// The words a label uses for each model service, after "Claude" or "Kimi" in plain speech.
    private static let providerWords: [(String, TradingProviderName)] = [
        ("openrouter", .openrouter), ("anthropic", .anthropic), ("claude", .anthropic),
        ("openai", .openai), ("chatgpt", .openai), ("gemini", .google), ("google", .google),
        ("deepseek", .deepseek), ("groq", .groq), ("xai", .xai), ("grok", .xai),
        ("mistral", .mistral), ("together", .together), ("fireworks", .fireworks),
        ("cerebras", .cerebras), ("moonshot", .moonshotai), ("kimi", .moonshotai),
    ]

    init(text: String) {
        for (label, value) in Self.pairs(in: text) {
            read(label: label, value: value)
        }
        if provider == nil, providerKeys.count == 1 {
            provider = providerKeys.keys.first
        }
    }

    /// Nothing the setup asks for was in the file.
    var isEmpty: Bool {
        channels == nil && discordToken == nil && provider == nil && providerKeys.isEmpty && alpacaKey == nil
            && alpacaSecret == nil && guruName == nil
    }

    /// "Label:" lines with their value on the next line, and "Label: value" lines.
    private static func pairs(in text: String) -> [(String, String)] {
        var pairs: [(String, String)] = []
        var label: String?
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let pending = label {
                pairs.append((pending, line))
                label = nil
            } else if line.hasSuffix(":") {
                label = key(String(line.dropLast()))
            } else if let colon = line.firstIndex(of: ":"), line.distance(from: line.startIndex, to: colon) <= 40 {
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if !value.isEmpty, !value.hasPrefix("//") { pairs.append((key(String(line[..<colon])), value)) }
            }
        }
        return pairs
    }

    /// A label's letters, lowercased: "Alpaca PAPER API key" reads as "alpacapaperapikey".
    private static func key(_ label: String) -> String {
        String(label.lowercased().unicodeScalars.filter(CharacterSet.lowercaseLetters.contains).map(Character.init))
    }

    private mutating func read(label: String, value: String) {
        let named = Self.providerWords.first { label.contains($0.0) }?.1
        if label.contains("alpaca") {
            if label.contains("secret") {
                alpacaSecret = value
            } else if label.contains("key") || label.contains("id") {
                alpacaKey = value
            }
        } else if label.contains("discord") && label.contains("token") {
            discordToken = value
        } else if label.contains("channel") {
            channels = value
        } else if label.contains("author") {
            authors = value
        } else if label.contains("guru") {
            guruName = value
        } else if label.contains("service") || label.contains("provider") {
            // "Model service: DeepSeek, model deepseek-flash"
            let words = value.lowercased()
            provider = Self.providerWords.first { words.contains($0.0) }?.1 ?? provider
            if let range = value.range(of: "model ", options: .caseInsensitive) {
                let name = value[range.upperBound...].split(separator: " ").first.map(String.init)
                modelName = name?.trimmingCharacters(in: .punctuationCharacters) ?? modelName
            }
        } else if label == "model" || label == "modelname" {
            modelName = value
        } else if let named, label.contains("key") || label.contains("token") {
            providerKeys[named] = value
        }
    }

    /// Fills the draft. Fields the file doesn't name keep what they had.
    @MainActor
    func apply(to draft: inout ConnectionsDraft) {
        if let channels { draft.channels = channels }
        if let authors { draft.authors = authors }
        if let discordToken { draft.discordToken = discordToken }
        if let provider {
            if draft.provider != provider {
                draft.provider = provider
                draft.modelName = SetupHelp.prefilledModel(for: provider) ?? ""
                // A key typed for the last service never goes to this one.
                draft.providerAPIKey = ""
            }
            if let modelName { draft.modelName = modelName }
            if let key = providerKeys[provider] { draft.providerAPIKey = key }
        }
        if alpacaKey != nil || alpacaSecret != nil {
            let index =
                draft.accounts.firstIndex { $0.environment == .paper }
                ?? {
                    draft.accounts.append(TradingAccountDraft(name: draft.nextAccountName))
                    return draft.accounts.count - 1
                }()
            if let alpacaKey { draft.accounts[index].key = alpacaKey }
            if let alpacaSecret { draft.accounts[index].secret = alpacaSecret }
        }
        if let guruName, let account = draft.accounts.first(where: { $0.environment == .paper }) {
            if let index = draft.routes.firstIndex(where: { $0.displayName.trimmed.isEmpty }) {
                draft.routes[index].displayName = guruName
            } else if !draft.routes.contains(where: { $0.displayName.trimmed == guruName }) {
                draft.routes.append(
                    TradingRouteDraft(
                        channelID: draft.sourceChannelIDs.first ?? "", displayName: guruName,
                        connection: TradingConnectionDraft(accountID: account.name)))
            }
        }
    }

    /// What was filled, in the owner's words, for the summary; never a value.
    @MainActor
    var filled: [String] {
        var lines: [String] = []
        if channels != nil { lines.append(L10n.string("Discord channels")) }
        if discordToken != nil { lines.append(L10n.string("Discord token")) }
        if let provider {
            let key = providerKeys[provider] != nil
            lines.append(
                L10n.string(key ? "%@ key and model" : "%@ model", provider.title))
        }
        if alpacaKey != nil && alpacaSecret != nil {
            lines.append(L10n.string("Alpaca paper key and secret"))
        } else if alpacaKey != nil || alpacaSecret != nil {
            lines.append(L10n.string("Half of the Alpaca keys"))
        }
        if let guruName { lines.append(L10n.string("Guru “%@”", guruName)) }
        return lines
    }

    /// What the setup still needs that the file didn't have.
    @MainActor
    var missing: [String] {
        var lines: [String] = []
        if channels == nil { lines.append(L10n.string("Discord channels")) }
        if discordToken == nil { lines.append(L10n.string("Discord token")) }
        if provider == nil {
            lines.append(
                L10n.string(providerKeys.count > 1 ? "Several model keys: choose a service" : "A model service and its key"))
        }
        if alpacaKey == nil || alpacaSecret == nil { lines.append(L10n.string("Alpaca paper key and secret")) }
        if guruName == nil { lines.append(L10n.string("A guru: add one under Gurus")) }
        return lines
    }
}

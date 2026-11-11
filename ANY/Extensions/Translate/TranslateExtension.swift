import Observation
import SwiftUI

/// Translates text with every available service at once, one card each, from its own page or with
/// a prefix in the main search ("tr hello", "翻译 你好"). Google needs no key; DeepL joins once
/// it has one.
@Observable
final class TranslateExtension: ANYExtension {
    let manifest = ExtensionManifest(
        id: "translate",
        title: "翻译",
        subtitle: "同时使用 DeepL、Google 和 AI 翻译文本",
        icon: .symbol("translate")
    )

    let preferences = TranslatePreferences(storage: ExtensionStorage(extensionID: "translate"))

    static let searchPrefixes = ["tr ", "fy ", "翻译 "]
    /// Typing pauses this long before a request is sent.
    private static let debounce = Duration.milliseconds(350)

    private(set) var history: TranslationHistory?

    @ObservationIgnored private var cache: [String: Translation] = [:]
    @ObservationIgnored private var aiSessions: [String: AITranslationSession] = [:]
    @ObservationIgnored private var aiSessionOrder: [String] = []
    @ObservationIgnored private weak var host: (any ExtensionHost)?

    func activate(context: ExtensionContext) {
        host = context.host
        history = TranslationHistory(fileURL: context.storage.dataDirectory.appending(path: "history.json"))
    }

    func deactivate() {
        cache = [:]
        aiSessions.values.forEach { $0.cancel() }
        aiSessions = [:]
        aiSessionOrder = []
        history = nil
    }

    func results(for query: SearchQuery) async -> [ResultItem] {
        var items = [
            ResultItem(
                id: "open",
                title: "翻译",
                icon: manifest.icon,
                keywords: ["translate", "fanyi", "deepl", "google"],
                actions: [
                    ItemAction("打开翻译", systemImage: "translate") { [weak self] _ in
                        guard let self else { return .keepOpen }
                        return .push(.list(TranslateDataSource(ext: self)))
                    },
                ]
            ),
        ]
        if preferences.usesSearchPrefix, let text = Self.textAfterPrefix(in: query.raw) {
            if let translations = await translationItems(for: text) {
                items += translations
            }
        } else if !query.isEmpty {
            items.append(fallbackItem(for: query.text))
        }
        return items
    }

    func makeSettingsView() -> AnyView? {
        AnyView(TranslateSettingsView(ext: self))
    }

    func selectionTools() -> [SelectionTool] {
        [
            SelectionTool(id: manifest.id, title: "翻译", symbol: "translate") { context in
                TranslationSelectionSession(ext: self, context: context)
            },
        ]
    }

    /// Offered among the "使用 … 进行" options, so anything the search doesn't recognize can be translated.
    private func fallbackItem(for text: String) -> ResultItem {
        ResultItem(
            id: "fallback",
            title: "翻译",
            subtitle: "“\(text)”",
            icon: manifest.icon,
            kind: .fallback,
            actions: [
                ItemAction("翻译", systemImage: "translate") { [weak self] _ in
                    guard let self else { return .keepOpen }
                    return .push(.list(TranslateDataSource(ext: self, initialQuery: text)))
                },
            ]
        )
    }

    private static func textAfterPrefix(in raw: String) -> String? {
        let trimmedLeading = raw.drop { $0.isWhitespace }
        guard let prefix = searchPrefixes.first(where: { trimmedLeading.lowercased().hasPrefix($0) }) else { return nil }
        let text = trimmedLeading.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: - Translating

    /// One card per service, in a fixed order, fetched in parallel. Nil when superseded by newer typing.
    func translationItems(for text: String) async -> [ResultItem]? {
        let source = preferences.sourceLanguage
        let requested = preferences.target(for: text)
        let correcting = preferences.correctsAutomatically

        let services = preferences.availableServices
        if services.contains(where: { cache[cacheKey($0, source, requested, text, correcting: correcting)] == nil }) {
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return nil }
        }

        async let deepL = translate(text, from: source, to: requested, with: .deepL, correctingSameLanguage: correcting)
        async let google = translate(text, from: source, to: requested, with: .google, correctingSameLanguage: correcting)
        let outcomes = await [(TranslationService.deepL, deepL), (.google, google)]
        guard !Task.isCancelled else { return nil }
        var target = requested
        if correcting, let adopted = outcomes.compactMap({ _, outcome -> Translation? in
            if case .success(let translation) = outcome { return translation }
            return nil
        }).first?.target {
            target = adopted
            preferences.resolveTarget(adopted, for: text)
        }

        if preferences.recordsHistory {
            let translations = outcomes.compactMap { _, outcome in try? outcome?.get() }
            history?.record(text, translations: translations)
        }

        var items: [ResultItem] = outcomes.enumerated().compactMap { rank, entry in
            let (service, outcome) = entry
            switch outcome {
            case .success(let translation): return item(for: translation, original: text, source: source, rank: rank)
            case .failure(let error): return errorItem(error, service: service, rank: rank)
            case nil: return nil
            }
        }
        if let configuration = preferences.aiConfiguration {
            let session = aiSession(for: text, from: source, to: target, configuration: configuration)
            items.append(aiItem(for: session, rank: outcomes.count))
        }
        return items
    }

    // MARK: - AI

    /// The model's turn comes a little after the quick services, so a pause while typing doesn't
    /// start a request.
    private static let aiDelay = Duration.milliseconds(400)
    private static let aiSessionLimit = 12

    private func aiSessionKey(_ text: String, _ source: TranslationLanguage?, _ target: TranslationLanguage, _ configuration: LanguageModelConfiguration) -> String {
        "\(configuration.api.rawValue)|\(configuration.model)|\(source?.rawValue ?? "auto")|\(target.rawValue)|\(text)"
    }

    /// Reuses the session for the same request; starting a new one stops any other still running.
    func aiSession(
        for text: String,
        from source: TranslationLanguage?,
        to target: TranslationLanguage,
        configuration: LanguageModelConfiguration,
        restoring translation: Translation? = nil
    ) -> AITranslationSession {
        let key = aiSessionKey(text, source, target, configuration)
        if let session = aiSessions[key] {
            if session.phase == .cancelled { session.start() }
            return session
        }

        aiSessions.values.forEach { $0.cancel() }
        let session = AITranslationSession(text: text, source: source, target: target, configuration: configuration)
        session.onComplete = { [weak self] translation in
            guard let self, preferences.recordsHistory else { return }
            history?.attach(translation, to: text)
        }
        session.document.onCopy = { [weak self] copied in
            Pasteboard.copy(copied)
            self?.host?.showToast(Toast(message: "已复制到剪贴板", style: .success))
        }
        if let translation {
            session.restore(translation)
        } else {
            session.start(after: Self.aiDelay)
        }

        aiSessions[key] = session
        aiSessionOrder.append(key)
        if aiSessionOrder.count > Self.aiSessionLimit {
            aiSessions[aiSessionOrder.removeFirst()] = nil
        }
        return session
    }

    private func aiItem(for session: AITranslationSession, rank: Int) -> ResultItem {
        let copyResult = ItemAction("复制译文", systemImage: "doc.on.doc") { [manifest] context in
            switch session.phase {
            case .done, .fallback:
                guard let text = session.resultText else { return .keepOpen }
                Pasteboard.copy(text)
                context.host.showToast(Toast(message: "已复制到剪贴板", style: .success))
                return .dismiss
            case .failed(_, true):
                context.host.openSettings(extensionID: manifest.id)
                return .keepOpen
            case .failed, .cancelled:
                session.start()
                return .keepOpen
            case .waiting, .generating, .repairing:
                context.host.showToast(Toast(message: "AI 翻译还在生成", style: .info))
                return .keepOpen
            }
        }
        let paste = ItemAction("粘贴到当前应用", systemImage: "doc.on.clipboard") { context in
            guard let text = session.resultText, !session.isRunning else {
                context.host.showToast(Toast(message: "AI 翻译还在生成", style: .info))
                return .keepOpen
            }
            return await ItemAction.paste(text).handler(context)
        }
        let regenerate = ItemAction("重新生成", systemImage: "arrow.clockwise", shortcut: .init(.character("r"), modifiers: [.command])) { _ in
            session.start()
            return .keepOpen
        }
        let openSettings = ItemAction("前往翻译设置", systemImage: "gearshape") { [manifest] context in
            context.host.openSettings(extensionID: manifest.id)
            return .keepOpen
        }
        let copySource = ItemAction("复制 TSX 源码", systemImage: "chevron.left.forwardslash.chevron.right") { context in
            guard let source = session.document.source else { return .keepOpen }
            Pasteboard.copy(source)
            context.host.showToast(Toast(message: "已复制源码", style: .success))
            return .keepOpen
        }
        return ResultItem(
            id: "result.ai",
            title: session.resultText ?? "AI 翻译",
            subtitle: session.text,
            icon: .symbol("sparkles"),
            kind: .instant(score: Self.score(rank: rank)),
            actions: [copyResult, paste, regenerate, copySource, openSettings],
            card: AnyView(AITranslationCard(session: session)),
            isInteractive: true
        )
    }

    /// Nil when the service isn't available or the request was cancelled.
    /// With `correctingSameLanguage`, an automatic request whose text is already in `target`
    /// is sent to the other language of the pair instead.
    func translate(
        _ text: String,
        from source: TranslationLanguage?,
        to target: TranslationLanguage,
        with service: TranslationService,
        correctingSameLanguage: Bool = false
    ) async -> Result<Translation, Error>? {
        guard preferences.availableServices.contains(service) else { return nil }
        let apiKey = preferences.apiKey(for: service)
        let correcting = correctingSameLanguage && preferences.correctsAutomatically && target == preferences.target(for: text)
        let key = cacheKey(service, source, target, text, correcting: correcting)
        if let cached = cache[key] { return .success(cached) }
        do {
            let translation = try await correctedTranslation(
                text, from: source, to: target, service: service, apiKey: apiKey, correcting: correcting
            )
            cache[key] = translation
            return .success(translation)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return nil }
            return .failure(error)
        }
    }

    private func correctedTranslation(
        _ text: String,
        from source: TranslationLanguage?,
        to target: TranslationLanguage,
        service: TranslationService,
        apiKey: String,
        correcting: Bool
    ) async throws -> Translation {
        do {
            let translation = try await TranslationClient.translate(text, from: source, to: target, using: service, apiKey: apiKey)
            guard let alternate = redirectedTarget(from: translation.source, requested: target, correcting: correcting) else {
                return translation
            }
            do {
                return try await TranslationClient.translate(text, from: source, to: alternate, using: service, apiKey: apiKey)
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw error }
                return translation
            }
        } catch {
            guard let alternate = redirectedTarget(after: error, requested: target, correcting: correcting) else { throw error }
            return try await TranslationClient.translate(text, from: source, to: alternate, using: service, apiKey: apiKey)
        }
    }

    /// The other language, when an automatic translation landed on the language the text is already in.
    private func redirectedTarget(from detected: TranslationLanguage?, requested: TranslationLanguage, correcting: Bool) -> TranslationLanguage? {
        guard correcting, let detected, detected == requested else { return nil }
        let alternate = preferences.alternate(to: requested)
        return alternate == requested ? nil : alternate
    }

    private func redirectedTarget(after error: Error, requested: TranslationLanguage, correcting: Bool) -> TranslationLanguage? {
        guard correcting, Self.rejectedAsSameLanguage(error) else { return nil }
        let alternate = preferences.alternate(to: requested)
        return alternate == requested ? nil : alternate
    }

    private static func rejectedAsSameLanguage(_ error: Error) -> Bool {
        guard case .rejected(_, let status, let message, _) = error as? TranslationError, status == 400 else { return false }
        let text = (message ?? "").lowercased()
        return text.contains("equal") || text.contains("same") || text.contains("language pair")
    }

    /// Lets a history entry be shown again without new requests.
    func restore(_ entry: TranslationHistoryEntry) {
        for translation in entry.translations {
            if translation.service == .ai {
                guard let configuration = preferences.aiConfiguration,
                      translation.target == preferences.target(for: entry.text)
                else { continue }
                _ = aiSession(for: entry.text, from: preferences.sourceLanguage, to: translation.target, configuration: configuration, restoring: translation)
            } else {
                cache[cacheKey(translation.service, preferences.sourceLanguage, translation.target, entry.text)] = translation
            }
        }
    }

    private func cacheKey(
        _ service: TranslationService,
        _ source: TranslationLanguage?,
        _ target: TranslationLanguage,
        _ text: String,
        correcting: Bool = false
    ) -> String {
        "\(service.rawValue)|\(source?.rawValue ?? "auto")|\(target.rawValue)|\(correcting)|\(text)"
    }

    func test(_ service: TranslationService) async throws -> Translation {
        guard service == .ai else {
            return try await TranslationClient.translate("Hello, world", to: preferences.primaryLanguage, using: service, apiKey: preferences.apiKey(for: service))
        }
        guard let configuration = preferences.aiConfiguration else { throw LanguageModelError.invalidEndpoint }
        let reply = try await LanguageModelClient.complete(
            configuration,
            system: "Translate the user's text into \(preferences.primaryLanguage.name). Reply with the translation only.",
            messages: [LanguageModelMessage(role: .user, content: "Hello, world")],
            maxTokens: 32
        )
        return Translation(text: reply.trimmingCharacters(in: .whitespacesAndNewlines), source: .english, target: preferences.primaryLanguage, service: .ai)
    }

    /// Cards share the strong instant score, offset slightly so they keep the service order.
    private static func score(rank: Int) -> Double {
        SearchEngine.strongInstantScore + 1 - Double(rank) * 0.01
    }

    private func item(for translation: Translation, original: String, source: TranslationLanguage?, rank: Int) -> ResultItem {
        var actions: [ItemAction] = [
            .copy(translation.text, title: "复制译文", shortcut: nil),
            .paste(translation.text),
            .copy(original, title: "复制原文", shortcut: .init(.character("c"), modifiers: [.command, .option])),
        ]
        if let url = translation.service.webURL(for: original, from: source, to: translation.target) {
            actions.append(.open(url, title: "在 \(translation.service.name) 网页中打开", systemImage: "safari"))
        }
        return ResultItem(
            id: "result.\(translation.service.rawValue)",
            title: translation.text,
            subtitle: original,
            icon: manifest.icon,
            kind: .instant(score: Self.score(rank: rank)),
            actions: actions,
            card: AnyView(TranslationCard(translation: translation, original: original)),
            allowsTextSelection: true
        )
    }

    private func errorItem(_ error: Error, service: TranslationService, rank: Int) -> ResultItem {
        let message = (error as? TranslationError)?.errorDescription ?? error.localizedDescription
        let needsConfiguration = (error as? TranslationError)?.isAPIKeyProblem ?? false
        let openSettings = ItemAction("前往翻译设置", systemImage: "gearshape") { [manifest] context in
            context.host.openSettings(extensionID: manifest.id)
            return .keepOpen
        }
        return ResultItem(
            id: "error.\(service.rawValue)",
            title: message,
            icon: manifest.icon,
            kind: .instant(score: Self.score(rank: rank)),
            actions: needsConfiguration ? [openSettings] : [],
            card: AnyView(TranslationErrorCard(service: service, message: message, needsConfiguration: needsConfiguration))
        )
    }
}

/// The dedicated page: everything typed is translated.
final class TranslateDataSource: ListDataSource {
    let title = "翻译"
    let icon = ItemIcon.symbol("translate")
    let searchPlaceholder = "输入要翻译的文本…"
    let emptyText = "输入文本开始翻译"
    let initialQuery: String

    private let ext: TranslateExtension

    init(ext: TranslateExtension, initialQuery: String = "") {
        self.ext = ext
        self.initialQuery = initialQuery
    }

    func sections(for query: SearchQuery) async -> [ResultSection] {
        guard !query.isEmpty else { return historySections() }
        guard let items = await ext.translationItems(for: query.text) else { return [] }
        return [ResultSection(id: "translation", title: nil, items: items)]
    }

    func toolbar(query: String, reload: @escaping () -> Void) -> AnyView? {
        AnyView(LanguageBar(preferences: ext.preferences, query: query.trimmingCharacters(in: .whitespacesAndNewlines), onChange: reload))
    }

    private let dateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private func historySections() -> [ResultSection] {
        guard let history = ext.history, !history.entries.isEmpty else { return [] }
        return [ResultSection(id: "history", title: "最近翻译", items: history.entries.map { item(for: $0, in: history) })]
    }

    private func item(for entry: TranslationHistoryEntry, in history: TranslationHistory) -> ResultItem {
        ResultItem(
            id: entry.id.uuidString,
            title: Self.singleLine(entry.text),
            subtitle: Self.singleLine(entry.primaryTranslation),
            icon: .symbol("clock.arrow.circlepath"),
            accessory: dateFormatter.localizedString(for: entry.date, relativeTo: .now),
            actions: [
                ItemAction("查看翻译", systemImage: "translate") { [ext] _ in
                    ext.restore(entry)
                    return .setQuery(entry.text)
                },
                .copy(entry.primaryTranslation, title: "复制译文"),
                .copy(entry.text, title: "复制原文", shortcut: .init(.character("c"), modifiers: [.command, .option])),
                ItemAction("删除此记录", systemImage: "trash", shortcut: .init(.character("x"), modifiers: [.control]), style: .destructive) { _ in
                    history.remove(entry.id)
                    return .refresh
                },
                ItemAction(
                    "清空翻译历史",
                    systemImage: "trash.slash",
                    shortcut: .init(.character("x"), modifiers: [.control, .shift]),
                    style: .destructive,
                    confirmation: .init(title: "清空翻译历史？", message: "所有记录将被删除，此操作无法撤销。", confirmTitle: "清空")
                ) { _ in
                    history.removeAll()
                    return .refresh
                },
            ]
        )
    }

    private static func singleLine(_ text: String) -> String {
        String(text.split(whereSeparator: \.isNewline).joined(separator: " ").prefix(120))
    }
}

// MARK: - Language bar

/// "源语言 ⇄ 目标语言" below the translate page's search field, as glass controls.
private struct LanguageBar: View {
    let preferences: TranslatePreferences
    let query: String
    let onChange: () -> Void

    private var targetTitle: String {
        if let target = preferences.targetLanguage { return target.name }
        if let resolved = preferences.resolvedTarget(for: query) { return resolved.name }
        return query.isEmpty ? "自动" : preferences.target(for: query).name
    }

    var body: some View {
        GlassEffectContainer(spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                LanguageMenu(
                    title: preferences.sourceLanguage?.name ?? "自动检测",
                    automaticTitle: "自动检测",
                    selection: preferences.sourceLanguage
                ) { language in
                    preferences.setSource(language)
                    onChange()
                }

                Button {
                    withAnimation(Motion.press) { preferences.swapLanguages(for: query) }
                    onChange()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(Theme.Typography.callout)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .help("交换语言")

                LanguageMenu(
                    title: targetTitle,
                    automaticTitle: "自动（\(preferences.primaryLanguage.name) / \(preferences.secondaryLanguage.name)）",
                    selection: preferences.targetLanguage
                ) { language in
                    preferences.setTarget(language)
                    onChange()
                }
            }
        }
        .controlSize(.large)
    }
}

private struct LanguageMenu: View {
    let title: String
    let automaticTitle: String
    let selection: TranslationLanguage?
    let select: (TranslationLanguage?) -> Void

    var body: some View {
        Menu {
            option(automaticTitle, language: nil)
            Divider()
            ForEach(TranslationLanguage.allCases) { option($0.name, language: $0) }
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Text(title)
                    .contentTransition(.interpolate)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(Theme.Typography.bodyMedium)
            .padding(.horizontal, Theme.Space.xs)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.glass)
        .fixedSize()
    }

    private func option(_ title: String, language: TranslationLanguage?) -> some View {
        Button {
            select(language)
        } label: {
            if language == selection {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

// MARK: - Cards

private struct TranslationCard: View {
    let translation: Translation
    let original: String

    private var direction: String {
        let source = translation.source?.name ?? "自动检测"
        return "\(translation.service.name) · \(source) → \(translation.target.name)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            CardHeader(symbol: "translate", title: direction)
            SelectableText(text: translation.text, font: .systemFont(ofSize: 15), lineLimit: 8)
            SelectableText(text: original, font: .systemFont(ofSize: 11), color: .tertiaryLabelColor, lineLimit: 2)
        }
    }
}

private struct TranslationErrorCard: View {
    let service: TranslationService
    let message: String
    let needsConfiguration: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            CardHeader(symbol: "exclamationmark.triangle", title: "\(service.name) · 翻译失败")
            Text(message)
                .font(Theme.Typography.lead)
            if needsConfiguration {
                Text("按 ↩ 前往设置修改 API Key")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Settings

private struct TranslateSettingsView: View {
    let ext: TranslateExtension

    var body: some View {
        @Bindable var preferences = ext.preferences

        Section {
            SecureField("API Key", text: $preferences.deepLAPIKey, prompt: Text("未设置"))
            ConnectionTestRow(ext: ext, service: .deepL, isAvailable: !preferences.deepLAPIKey.isEmpty, configurationKey: preferences.deepLAPIKey)
        } header: {
            Text("DeepL")
        } footer: {
            footer("DeepL 没有免密钥接口，填写后才会显示 DeepL 结果。免费版每月 50 万字符，密钥以 :fx 结尾。", link: "获取密钥", url: "https://www.deepl.com/your-account/keys")
        }

        Section {
            SecureField("API Key", text: $preferences.googleAPIKey, prompt: Text("可选"))
            ConnectionTestRow(ext: ext, service: .google, isAvailable: true, configurationKey: preferences.googleAPIKey)
        } header: {
            Text("Google 翻译")
        } footer: {
            footer("留空即可使用。填写 Cloud Translation API Key 更稳定。", link: "获取密钥", url: "https://console.cloud.google.com/apis/credentials")
        }

        Section {
            Picker("接口协议", selection: $preferences.aiAPI) {
                ForEach(LanguageModelAPI.allCases) { api in
                    Text("\(api.name)（\(api.vendor)）").tag(api)
                }
            }
            TextField("Base URL", text: $preferences.aiBaseURL, prompt: Text(preferences.aiAPI.defaultBaseURL))
            SecureField("API Key", text: $preferences.aiAPIKey, prompt: Text("未设置"))
            TextField("模型", text: $preferences.aiModel, prompt: Text("模型名称"))
            ConnectionTestRow(
                ext: ext,
                service: .ai,
                isAvailable: preferences.aiConfiguration != nil,
                configurationKey: "\(preferences.aiAPI.rawValue)|\(preferences.aiBaseURL)|\(preferences.aiAPIKey)|\(preferences.aiModel)"
            )
        } header: {
            Text("AI 翻译")
        } footer: {
            Text("填写 API Key 和模型后，AI 会与其它服务同时翻译，并用词条、例句、表格等组件排版结果。Base URL 留空使用官方地址，可以填到 /v1，也可以填完整的接口地址。")
                .foregroundStyle(.secondary)
        }

        Section {
            Picker("目标语言", selection: $preferences.primaryLanguage) {
                ForEach(TranslationLanguage.allCases) { Text($0.name).tag($0) }
            }
            Picker("备选语言", selection: $preferences.secondaryLanguage) {
                ForEach(TranslationLanguage.allCases) { Text($0.name).tag($0) }
            }
        } header: {
            Text("语言")
        } footer: {
            Text("翻译页面中目标语言为「自动」时使用。汉字按中文识别，系统很确定是日语时才按日语；假名、韩文和西里尔字母按各自的文字识别。原文已经是目标语言时，改为翻译成备选语言。")
                .foregroundStyle(.secondary)
        }

        Section {
            Toggle("记录翻译历史", isOn: $preferences.recordsHistory)
            LabeledContent("当前记录", value: "\(ext.history?.entries.count ?? 0) 条")
            HStack {
                Spacer()
                TwoStepButton("清空历史…", confirmTitle: "再次点击以清空") { ext.history?.removeAll() }
                    .disabled(ext.history?.entries.isEmpty ?? true)
            }
        } header: {
            Text("历史")
        } footer: {
            Text("最多保留 \(TranslationHistory.limit) 条，只保存在本机。打开翻译且未输入时显示。")
                .foregroundStyle(.secondary)
        }

        Section {
            Toggle("在主搜索中使用前缀翻译", isOn: $preferences.usesSearchPrefix)
        } footer: {
            Text("所有可用的服务会同时翻译，各自显示一张结果卡片。在搜索框输入「tr 」「fy 」或「翻译 」后接文本即可直接翻译。API Key 保存在钥匙串中。")
                .foregroundStyle(.secondary)
        }
    }

    private func footer(_ text: String, link: String, url: String) -> some View {
        HStack(spacing: Theme.Space.xs) {
            Text(text)
            if let url = URL(string: url) {
                Link(link, destination: url)
            }
        }
        .foregroundStyle(.secondary)
    }
}

/// "测试" button for one service, with the outcome shown inline.
private struct ConnectionTestRow: View {
    let ext: TranslateExtension
    let service: TranslationService
    let isAvailable: Bool
    /// Changing any of the service's settings clears the last result.
    let configurationKey: String

    @State private var state = TestState.idle

    private enum TestState {
        case idle
        case testing
        case succeeded(String)
        case failed(String)
    }

    var body: some View {
        LabeledContent("连接") {
            HStack(spacing: Theme.Space.s) {
                status
                Button("测试", action: test)
                    .disabled(isTesting || !isAvailable)
            }
        }
        .onChange(of: configurationKey) { state = .idle }
    }

    private var isTesting: Bool {
        if case .testing = state { return true }
        return false
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView().controlSize(.small)
        case .succeeded(let text):
            Label(text, systemImage: "checkmark")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func test() {
        state = .testing
        Task {
            do {
                state = .succeeded(try await ext.test(service).text)
            } catch {
                state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }
}

import Observation
import SwiftUI

/// Translation in the selection popup: every service at once, one card each, filling in as each
/// answers rather than all together. Selections can be in any language, so the source is always
/// detected and the target chosen automatically, whatever the translate page is set to; the
/// target can be changed for this selection only.
@Observable
final class TranslationSelectionSession: SelectionSession {
    enum Outcome {
        case loading
        case success(Translation)
        case failure(String, needsConfiguration: Bool)
    }

    struct Entry {
        let service: TranslationService
        var outcome: Outcome
    }

    let text: String
    private(set) var target: TranslationLanguage
    private(set) var entries: [Entry] = []
    private(set) var aiSession: AITranslationSession?
    var selected: TranslationService?
    private(set) var copied: TranslationService?

    @ObservationIgnored private let ext: TranslateExtension
    @ObservationIgnored private let host: any ExtensionHost
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var copiedTask: Task<Void, Never>?
    @ObservationIgnored private var targetOverride: TranslationLanguage?
    @ObservationIgnored private var isHandedOff = false
    /// Set by the first successful result, so a later service can't move the target again.
    @ObservationIgnored private var hasAdoptedDirection = false

    init(ext: TranslateExtension, context: SelectionContext) {
        self.ext = ext
        self.host = context.host
        self.text = context.selection.text
        self.target = ext.preferences.automaticTarget(for: context.selection.text)
        start()
    }

    // MARK: - SelectionSession

    var accessory: AnyView? { AnyView(LanguageDirection(session: self)) }
    var content: AnyView { AnyView(TranslationSelectionContent(session: self)) }
    var copyableText: String? { activeText }

    var actions: [ItemAction] {
        [
            ItemAction("复制", systemImage: "doc.on.doc") { [weak self] context in
                guard let text = self?.activeText else {
                    context.host.showToast("译文还没有准备好", style: .info)
                    return .keepOpen
                }
                Pasteboard.copy(text)
                context.host.showToast("已复制到剪贴板")
                return .dismiss
            },
            ItemAction("替换原文", systemImage: "text.insert") { [weak self] context in
                guard let text = self?.activeText else {
                    context.host.showToast("译文还没有准备好", style: .info)
                    return .keepOpen
                }
                return await ItemAction.paste(text).handler(context)
            },
            ItemAction("在 ANY 中打开", systemImage: "macwindow", shortcut: .init(.character("o"), modifiers: [.command])) { [weak self] context in
                guard let self else { return .keepOpen }
                handOff()
                context.host.open(TranslateDataSource(ext: ext, initialQuery: text))
                return .keepOpen
            },
        ]
    }

    func moveSelection(by delta: Int) -> Bool {
        let rows = rows
        guard !rows.isEmpty else { return false }
        let index = selected.flatMap(rows.firstIndex(of:)) ?? -1
        let next = rows[min(max(index + delta, 0), rows.count - 1)]
        guard next != selected else { return false }
        withAnimation(Motion.selection) { selected = next }
        return true
    }

    func end() {
        guard !isHandedOff else { return }
        task?.cancel()
        aiSession?.cancel()
    }

    /// The translate page picks up where the popup is: same direction, so it reuses the cached
    /// results, and the requests and AI translation still in flight carry on for it.
    private func handOff() {
        ext.preferences.sourceLanguage = nil
        ext.preferences.targetLanguage = targetOverride
        isHandedOff = true
    }

    // MARK: - Results

    /// Cards in display order: the quick services, then AI.
    var rows: [TranslationService] {
        entries.map(\.service) + (aiSession == nil ? [] : [.ai])
    }

    /// The language detected from the first answer, or on device until one arrives.
    var source: TranslationLanguage? {
        for entry in entries {
            if case .success(let translation) = entry.outcome, let source = translation.source { return source }
        }
        return TranslationLanguage.detect(in: text)
    }

    func outcome(for service: TranslationService) -> Outcome? {
        entries.first { $0.service == service }?.outcome
    }

    /// Nil while the card is still loading or when it failed.
    func result(for service: TranslationService) -> String? {
        if service == .ai {
            guard let aiSession, !aiSession.isRunning else { return nil }
            return aiSession.resultText
        }
        guard case .success(let translation) = outcome(for: service) else { return nil }
        return translation.text
    }

    func isLoading(_ service: TranslationService) -> Bool {
        if service == .ai { return aiSession?.isRunning ?? false }
        if case .loading = outcome(for: service) { return true }
        return false
    }

    /// The selected card's text, or the first that's ready.
    var activeText: String? {
        if let selected, let text = result(for: selected) { return text }
        return rows.lazy.compactMap { self.result(for: $0) }.first
    }

    func copy(_ service: TranslationService) {
        guard let text = result(for: service) else { return }
        Pasteboard.copy(text)
        withAnimation(Motion.press) { copied = service }
        copiedTask?.cancel()
        copiedTask = Task {
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.press) { copied = nil }
        }
    }

    func translate(to language: TranslationLanguage) {
        guard language != target else { return }
        targetOverride = language
        start()
    }

    func retry() {
        start()
    }

    func openSettings() {
        host.openSettings(extensionID: ext.manifest.id)
    }

    private func start() {
        task?.cancel()
        let preferences = ext.preferences
        let source: TranslationLanguage? = nil
        let target = targetOverride ?? preferences.automaticTarget(for: text)
        let correcting = targetOverride == nil
        let services = preferences.availableServices
        self.target = target
        hasAdoptedDirection = false
        entries = services.map { Entry(service: $0, outcome: .loading) }
        aiSession = preferences.aiConfiguration.map {
            ext.aiSession(for: text, from: source, to: target, configuration: $0)
        }
        if selected == nil || !rows.contains(selected!) {
            selected = rows.first
        }

        let ext = ext
        let text = text
        task = Task { [weak self] in
            var translations: [Translation] = []
            await withTaskGroup(of: (TranslationService, Result<Translation, any Error>?).self) { group in
                for service in services {
                    group.addTask { (service, await ext.translate(text, from: source, to: target, with: service, correctingSameLanguage: correcting)) }
                }
                for await (service, outcome) in group {
                    guard let outcome else { continue }
                    if case .success(let translation) = outcome { translations.append(translation) }
                    self?.receive(outcome, for: service)
                }
            }
            guard !Task.isCancelled, preferences.recordsHistory else { return }
            let ordered = services.compactMap { service in translations.first { $0.service == service } }
            ext.history?.record(text, translations: ordered)
        }
    }

    private func receive(_ result: Result<Translation, any Error>, for service: TranslationService) {
        guard let index = entries.firstIndex(where: { $0.service == service }) else { return }
        let outcome: Outcome
        switch result {
        case .success(let translation):
            outcome = .success(translation)
        case .failure(let error):
            let translationError = error as? TranslationError
            outcome = .failure(
                translationError?.errorDescription ?? error.localizedDescription,
                needsConfiguration: translationError?.isAPIKeyProblem ?? false
            )
        }
        withAnimation(Motion.overlay) {
            entries[index].outcome = outcome
            if case .success(let translation) = result {
                adoptAutomaticTarget(translation.target)
            }
        }
    }

    /// Keeps the header, and the AI request, on the language a service actually translated into.
    private func adoptAutomaticTarget(_ language: TranslationLanguage) {
        guard !hasAdoptedDirection, targetOverride == nil, ext.preferences.correctsAutomatically else { return }
        hasAdoptedDirection = true
        guard language != target else { return }
        target = language
        guard let configuration = ext.preferences.aiConfiguration else { return }
        aiSession = ext.aiSession(for: text, from: ext.preferences.sourceLanguage, to: language, configuration: configuration)
    }
}

// MARK: - Header

/// "英语 → 简体中文", with the target as a menu.
private struct LanguageDirection: View {
    let session: TranslationSelectionSession

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Text(session.source?.name ?? "自动检测")
                .foregroundStyle(.secondary)
                .contentTransition(.interpolate)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
            Menu {
                ForEach(TranslationLanguage.allCases) { language in
                    Button {
                        session.translate(to: language)
                    } label: {
                        if language == session.target {
                            Label(language.name, systemImage: "checkmark")
                        } else {
                            Text(language.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(session.target.name)
                        .contentTransition(.interpolate)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Theme.Space.s)
                .frame(height: 24)
                .background(.fill.tertiary.opacity(isHovering ? 1 : 0), in: .capsule)
                .contentShape(.capsule)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .onHover { isHovering = $0 }
            .animation(Motion.hoverSelection, value: isHovering)
            .help("目标语言")
        }
        .font(Theme.Typography.bodyMedium)
    }
}

// MARK: - Cards

private struct TranslationSelectionContent: View {
    let session: TranslationSelectionSession

    @Namespace private var selection

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            ForEach(session.rows, id: \.self) { service in
                TranslationResultCard(session: session, service: service, selection: selection)
                    .transition(.opacity)
            }
        }
    }
}

/// Matches the launcher's result cards: same radius, padding and fills, with the selection
/// highlight following the pointer and the arrow keys.
private struct TranslationResultCard: View {
    let session: TranslationSelectionSession
    let service: TranslationService
    let selection: Namespace.ID

    private var isSelected: Bool { session.selected == service }

    private var title: String {
        guard service == .ai, let model = session.aiSession?.configuration.model else { return service.name }
        return "AI · \(model)"
    }

    var body: some View {
        let shape = Theme.itemShape(radius: Theme.Radius.card)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            CardHeader(symbol: service == .ai ? "sparkles" : "translate", title: title) {
                trailing
            }
            content
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            shape.fill(.fill.quaternary)
            if isSelected {
                shape
                    .fill(.fill.tertiary)
                    .matchedGeometryEffect(id: "selection", in: selection)
            }
        }
        .contentShape(shape)
        .onContinuousHover { phase in
            guard case .active = phase, !isSelected else { return }
            withAnimation(Motion.hoverSelection) { session.selected = service }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if session.isLoading(service) {
            ProgressView().controlSize(.mini)
        } else if session.result(for: service) != nil {
            let isCopied = session.copied == service
            CopyButton(isCopied: isCopied) { session.copy(service) }
                .opacity(isSelected || isCopied ? 1 : 0)
        }
    }

    @ViewBuilder
    private var content: some View {
        if service == .ai, let ai = session.aiSession {
            AIResult(session: session, ai: ai)
        } else {
            switch session.outcome(for: service) {
            case .success(let translation):
                ResultText(text: translation.text)
            case .failure(let message, let needsConfiguration):
                Failure(message: message) {
                    if needsConfiguration {
                        InlineButton(title: "前往翻译设置", action: session.openSettings)
                    } else {
                        InlineButton(title: "重试", action: session.retry)
                    }
                }
            case .loading, nil:
                SkeletonLines()
            }
        }
    }
}

private struct AIResult: View {
    let session: TranslationSelectionSession
    let ai: AITranslationSession

    var body: some View {
        switch ai.phase {
        case .failed(let message, let isConfigurationProblem):
            Failure(message: message) {
                if isConfigurationProblem {
                    InlineButton(title: "前往翻译设置", action: session.openSettings)
                } else {
                    InlineButton(title: "重试") { ai.start() }
                }
            }
        case .cancelled:
            Failure(message: "已取消") {
                InlineButton(title: "重新生成") { ai.start() }
            }
        case .done where ai.document.state == .ready:
            TSXDocumentView(document: ai.document)
                .transition(.opacity)
        default:
            if let text = ai.resultText {
                ResultText(text: text)
            } else {
                SkeletonLines()
            }
        }
    }
}

private struct ResultText: View {
    let text: String

    var body: some View {
        SelectableText(text: text, font: .systemFont(ofSize: 15))
            .transition(.opacity)
    }
}

private struct Failure<Action: View>: View {
    let message: String
    @ViewBuilder var action: Action

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(message)
                .font(Theme.Typography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            action
        }
    }
}

private struct InlineButton: View {
    let title: String
    var symbol: String?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.xxs) {
                Text(title)
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .font(Theme.Typography.captionSemibold)
            .foregroundStyle(isHovering ? .primary : .secondary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovering = $0 }
        .animation(Motion.hoverSelection, value: isHovering)
    }
}

private struct CopyButton: View {
    let isCopied: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isCopied || isHovering ? .primary : .secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Theme.IconSize.small, height: Theme.IconSize.small)
                .background(.fill.tertiary.opacity(isHovering ? 1 : 0), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovering = $0 }
        .animation(Motion.hoverSelection, value: isHovering)
        .help(isCopied ? "已复制" : "复制")
    }
}

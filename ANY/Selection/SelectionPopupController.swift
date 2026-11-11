import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

enum SelectionPopupLayout {
    static let width: CGFloat = 420
    /// Transparent margin so the glass edge and its shadow aren't clipped by the window.
    static let margin: CGFloat = Theme.Space.xxl
    /// Between the selection and the glass.
    static let gap: CGFloat = Theme.Space.s
    /// Between the glass and the edge of the screen.
    static let screenInset: CGFloat = Theme.Space.s
    static let maxHeight: CGFloat = 560
    static let minHeight: CGFloat = 180
    /// With less room than this below the selection, the popup goes above it if there's more room there.
    static let preferredHeight: CGFloat = 300
    static let headerHeight: CGFloat = 44
    static let footerHeight: CGFloat = 36
    /// The glass grows out of the selection from this scale.
    static let hiddenScale: CGFloat = 0.9
}

/// What the popup shows: the selection, the tools that can work on it, and the active tool's session.
@Observable
final class SelectionPopupModel {
    enum Placement {
        case below
        case above
    }

    fileprivate(set) var selection: TextSelection?
    fileprivate(set) var tools: [SelectionTool] = []
    fileprivate(set) var toolID: String?
    fileprivate(set) var session: (any SelectionSession)?
    fileprivate(set) var isPresented = false
    fileprivate(set) var placement = Placement.below
    /// Where the glass scales from: the start of the selection.
    fileprivate(set) var growthAnchor = UnitPoint.top
    /// The tallest the glass may be where it's placed.
    fileprivate(set) var maxHeight = SelectionPopupLayout.maxHeight
    var isPinned = false

    @ObservationIgnored fileprivate var onHeightChange: ((CGFloat) -> Void)?
    @ObservationIgnored fileprivate var onSelectTool: ((String) -> Void)?
    @ObservationIgnored fileprivate var onPerform: ((ItemAction) -> Void)?
    @ObservationIgnored fileprivate var onClose: (() -> Void)?

    var tool: SelectionTool? { tools.first { $0.id == toolID } }

    func reportHeight(_ height: CGFloat) { onHeightChange?(height) }
    func selectTool(_ id: String) { onSelectTool?(id) }
    func perform(_ action: ItemAction) { onPerform?(action) }
    func close() { onClose?() }
}

/// A small glass panel beside text selected in another app. It takes keyboard focus without
/// activating ANY, so the app underneath keeps its selection and can be pasted into.
/// Clicking elsewhere closes it unless it's pinned; dragging it pins it.
final class SelectionPopupController: NSObject, NSWindowDelegate {
    private let model = SelectionPopupModel()
    private let panel = SelectionPopupPanel()
    private let hostingView: NSHostingView<SelectionPopupView>
    private lazy var popupHost = SelectionPopupHost(popup: self)

    private var keyMonitor: Any?
    private var isClosing = false
    private var closeTask: Task<Void, Never>?
    private var resizeTask: Task<Void, Never>?
    /// Set while ANY moves or resizes the panel, so only the user's drags count as moving it.
    private var isPositioning = false
    private var lastHeight: CGFloat = 240
    /// The panel's left edge, and its top (below the selection) or bottom (above it).
    private var windowX: CGFloat = 0
    private var edgeY: CGFloat = 0

    weak var host: (any ExtensionHost)?
    /// The tool last used, which the shortcut opens next time.
    private(set) var lastToolID: String?

    override init() {
        hostingView = NSHostingView(rootView: SelectionPopupView(model: model))
        super.init()
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        panel.contentView = hostingView
        panel.delegate = self

        model.onHeightChange = { [weak self] in self?.heightChanged($0) }
        model.onSelectTool = { [weak self] in self?.switchTool(to: $0) }
        model.onPerform = { [weak self] in self?.perform($0) }
        model.onClose = { [weak self] in self?.close() }
    }

    var isVisible: Bool { panel.isVisible && !isClosing }
    var selection: TextSelection? { isVisible ? model.selection : nil }

    // MARK: - Presenting

    func show(_ selection: TextSelection, tools: [SelectionTool], toolID: String?, near anchor: NSRect) {
        guard !tools.isEmpty else { return }
        close(animated: false)
        closeTask?.cancel()
        resizeTask?.cancel()
        isClosing = false

        model.selection = selection
        model.tools = tools
        model.isPinned = false
        startSession(tools.first { $0.id == toolID } ?? tools[0])
        place(near: anchor)

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { model.isPresented = false }

        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
        setFrame(height: lastHeight)
        // SwiftUI doesn't redraw a hidden window, so lay out and draw the collapsed state first.
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()

        Task {
            withAnimation(.spring(duration: 0.34, bounce: 0.2)) { model.isPresented = true }
        }
    }

    func close(animated: Bool = true) {
        guard panel.isVisible, !isClosing else { return }
        removeKeyMonitor()
        model.session?.end()

        guard animated else {
            panel.orderOut(nil)
            model.isPresented = false
            return
        }
        isClosing = true
        panel.ignoresMouseEvents = true
        withAnimation(.easeIn(duration: Motion.dismissDuration)) { model.isPresented = false }
        closeTask = Task {
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.dismissDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }
            guard isClosing else { return }
            isClosing = false
            panel.orderOut(nil)
        }
    }

    private func startSession(_ tool: SelectionTool) {
        guard let selection = model.selection else { return }
        model.session?.end()
        model.toolID = tool.id
        model.session = tool.makeSession(SelectionContext(selection: selection, host: popupHost))
        lastToolID = tool.id
    }

    private func switchTool(to id: String) {
        guard id != model.toolID, let tool = model.tools.first(where: { $0.id == id }) else { return }
        withAnimation(Motion.selection) { startSession(tool) }
    }

    private func perform(_ action: ItemAction) {
        guard let selection = model.selection else { return }
        let context = ActionContext(query: selection.text, host: popupHost)
        Task {
            if case .dismiss = await action.handler(context) {
                close()
            }
        }
    }

    // MARK: - Placement

    /// Below the selection, lined up with where it starts, or above it when there's more room there.
    private func place(near anchor: NSRect) {
        let layout = SelectionPopupLayout.self
        let probe = anchor.insetBy(dx: -1, dy: -1)
        let screen = NSScreen.screens.first { $0.frame.intersects(probe) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let spaceBelow = anchor.minY - layout.gap - visible.minY - layout.screenInset
        let spaceAbove = visible.maxY - anchor.maxY - layout.gap - layout.screenInset
        let placement: SelectionPopupModel.Placement = spaceBelow >= layout.preferredHeight || spaceBelow >= spaceAbove ? .below : .above
        let room = placement == .below ? spaceBelow : spaceAbove

        // The popup's text starts at the content inset, so it lines up with the selected text.
        let glassX = min(
            max(anchor.minX - Theme.Metrics.contentInset, visible.minX + layout.screenInset),
            visible.maxX - layout.screenInset - layout.width
        )
        windowX = glassX - layout.margin
        switch placement {
        case .below: edgeY = anchor.minY - layout.gap + layout.margin
        case .above: edgeY = anchor.maxY + layout.gap - layout.margin
        }

        model.placement = placement
        model.maxHeight = min(layout.maxHeight, max(room, layout.minHeight))
        let anchorX = min(max((anchor.minX + min(anchor.width, 24) / 2 - glassX) / layout.width, 0), 1)
        model.growthAnchor = UnitPoint(x: anchorX, y: placement == .below ? 0 : 1)
    }

    private func setFrame(height: CGFloat) {
        let width = SelectionPopupLayout.width + SelectionPopupLayout.margin * 2
        let y = model.placement == .below ? edgeY - height : edgeY
        isPositioning = true
        panel.setFrame(NSRect(x: windowX, y: y, width: width, height: height), display: true)
        isPositioning = false
    }

    /// Grows at once; shrinks a moment later, once the content has finished animating out.
    private func heightChanged(_ height: CGFloat) {
        guard height > 0, abs(height - panel.frame.height) > 0.5 else { return }
        lastHeight = height
        resizeTask?.cancel()
        guard panel.isVisible, height < panel.frame.height else {
            setFrame(height: height)
            return
        }
        resizeTask = Task {
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            setFrame(height: lastHeight)
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard !isPositioning, panel.isVisible else { return }
        windowX = panel.frame.minX
        edgeY = model.placement == .below ? panel.frame.maxY : panel.frame.minY
        if !model.isPinned {
            withAnimation(Motion.overlay) { model.isPinned = true }
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isClosing, !model.isPinned else { return }
        close()
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    /// Returns true when the event was consumed by the popup.
    private func handle(_ event: NSEvent) -> Bool {
        let editor = panel.firstResponder as? NSTextView
        if let editor, editor.hasMarkedText() || (editor.isEditable && event.keyCode != UInt16(kVK_Escape)) {
            return false
        }

        let keyCode = Int(event.keyCode)
        let modifiers = event.modifierFlags.intersection(KeyShortcut.relevantModifiers)
        let isReturn = keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter
        let actions = model.session?.actions ?? []

        if isReturn && (modifiers.isEmpty || modifiers == .command) {
            let index = modifiers.isEmpty ? 0 : 1
            if actions.indices.contains(index) { perform(actions[index]) }
            return true
        }
        if modifiers == .command, let digit = Int(event.charactersIgnoringModifiers ?? ""), (1...9).contains(digit) {
            if model.tools.indices.contains(digit - 1) { switchTool(to: model.tools[digit - 1].id) }
            return true
        }

        switch keyCode {
        case kVK_Escape:
            close()
        case kVK_ANSI_C where modifiers == .command:
            copy(from: editor)
        case kVK_ANSI_W where modifiers == .command:
            close()
        case kVK_UpArrow where modifiers.isEmpty:
            _ = model.session?.moveSelection(by: -1)
        case kVK_DownArrow where modifiers.isEmpty:
            _ = model.session?.moveSelection(by: 1)
        default:
            if let action = actions.dropFirst(2).first(where: { $0.shortcut?.matches(event) == true }) {
                perform(action)
                return true
            }
            // Typing doesn't belong in the popup; swallow it rather than beep.
            return !modifiers.contains(.command)
        }
        return true
    }

    /// The popup has no Edit menu to route ⌘C, so copy here: selected text first, then the tool's result.
    private func copy(from editor: NSTextView?) {
        if let editor, editor.selectedRange().length > 0 {
            editor.copy(nil)
        } else if let text = model.session?.copyableText {
            Pasteboard.copy(text)
            host?.showToast("已复制到剪贴板")
        }
    }
}

/// Forwards to the app, except that the launcher's "hide" closes the popup: tools reuse
/// launcher actions, and those hide the launcher before pasting or when they're done.
private final class SelectionPopupHost: ExtensionHost {
    private weak var popup: SelectionPopupController?

    init(popup: SelectionPopupController) {
        self.popup = popup
    }

    private var base: (any ExtensionHost)? { popup?.host }

    func showLauncher() {
        popup?.close()
        base?.showLauncher()
    }

    func hideLauncher() {
        popup?.close()
    }

    func open(_ source: any ListDataSource) {
        popup?.close()
        base?.open(source)
    }

    func openSettings(extensionID: String?) {
        popup?.close()
        base?.openSettings(extensionID: extensionID)
    }

    func showToast(_ toast: Toast) {
        base?.showToast(toast)
    }
}

final class SelectionPopupPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

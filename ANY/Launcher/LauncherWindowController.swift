import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

/// Pin state shared by the panel and its corner button.
@Observable
final class LauncherChrome {
    var isPinned = false {
        didSet {
            guard isPinned != oldValue else { return }
            onPinChanged?(isPinned)
        }
    }

    @ObservationIgnored var onPinChanged: ((Bool) -> Void)?

    func togglePin() {
        isPinned.toggle()
    }
}

final class LauncherWindowController: NSObject, NSWindowDelegate {
    let model: LauncherViewModel

    private let panel: LauncherPanel
    private let hostingView: NSHostingView<LauncherView>
    private let registry: ExtensionRegistry
    private let chrome: LauncherChrome
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var isHiding = false

    var onOpenSettings: (() -> Void)?

    init(model: LauncherViewModel, registry: ExtensionRegistry) {
        self.model = model
        self.registry = registry
        let chrome = LauncherChrome()
        let panel = LauncherPanel(contentRect: NSRect(origin: .zero, size: LauncherLayout.windowSize))
        self.chrome = chrome
        self.panel = panel
        self.hostingView = NSHostingView(rootView: LauncherView(model: model, chrome: chrome))
        super.init()

        chrome.onPinChanged = { [weak self] pinned in
            guard let self else { return }
            self.panel.isPinned = pinned
            if !pinned {
                self.restoreDefaultSize()
            }
        }
        // The panel fills whatever size the window currently is. Don't let the hosting view's
        // fitting size pull the window along with it.
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: LauncherLayout.windowSize)
        hostingView.wantsLayer = true
        panel.contentView = hostingView
        panel.delegate = self
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.keepPinnedInFront()
            }
        }
    }

    var isVisible: Bool { panel.isVisible && !isHiding }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        guard !isVisible else { return }
        if !isHiding {
            prepare()
        }
        present()
    }

    /// Shows the launcher already on `source`, or slides to it if the launcher is open.
    func open(_ source: any ListDataSource, selecting itemID: String? = nil) {
        Task {
            if isVisible {
                await model.open(source, selecting: itemID, animated: true)
            } else {
                if !isHiding { prepare() }
                await model.open(source, selecting: itemID, animated: false)
                present()
            }
        }
    }

    private func prepare() {
        registry.enabledExtensions.forEach { $0.launcherWillAppear() }
        model.prepareForPresentation()
        placeForPresentation()
    }

    /// The resized frame only lasts while pinned. Keep the top-left where the user left it.
    private func restoreDefaultSize() {
        guard panel.isVisible else { return }
        let size = LauncherLayout.windowSize
        var frame = panel.frame
        let top = frame.maxY
        frame.size = size
        frame.origin.y = top - size.height
        if let visible = NSScreen.screens.max(by: { lhs, rhs in
            area(lhs.visibleFrame.intersection(panel.frame)) < area(rhs.visibleFrame.intersection(panel.frame))
        })?.visibleFrame {
            if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width }
            if frame.minX < visible.minX { frame.origin.x = visible.minX }
            if frame.minY < visible.minY { frame.origin.y = visible.minY }
            if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
        }
        panel.setFrame(frame, display: true)
    }

    private func area(_ rect: NSRect) -> CGFloat {
        guard !rect.isNull, !rect.isEmpty else { return 0 }
        return rect.width * rect.height
    }

    /// A pinned panel comes back where the user left it. Anywhere else, recenter on the active screen.
    private func placeForPresentation() {
        if panel.isPinned, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            return
        }
        positionOnActiveScreen()
    }

    /// Clicking another app resigns key without ordering a floating panel behind that app's windows,
    /// but deactivation can still drop it. Pull it back while the user wants it pinned.
    private func keepPinnedInFront() {
        guard panel.isPinned, panel.isVisible, !isHiding else { return }
        panel.orderFrontRegardless()
    }

    private func present() {
        guard !isVisible else { return }
        let wasHiding = isHiding
        isHiding = false
        panel.ignoresMouseEvents = false

        // Glass can't sample the backdrop while the window is translucent and falls back to an
        // opaque fill, so the window appears fully opaque and only the scale animates in.
        // SwiftUI doesn't redraw a hidden window, so flush the reset content before showing it.
        panel.alphaValue = 1
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()

        animateScale(from: wasHiding ? Motion.dismissScale : Motion.presentScale, to: 1, spring: true)
    }

    func hide() {
        guard isVisible else { return }
        isHiding = true
        removeKeyMonitor()
        panel.ignoresMouseEvents = true
        animateScale(from: 1, to: Motion.dismissScale, spring: false)
        Task {
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.dismissDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }
            guard isHiding else { return }
            isHiding = false
            panel.orderOut(nil)
            ScaleAnimation.reset(hostingView)
        }
    }

    private func animateScale(from: CGFloat, to: CGFloat, spring: Bool) {
        let curve: ScaleAnimation.Curve = spring
            ? .spring(duration: 0.32, bounce: 0.22)
            : .easeIn(duration: Motion.dismissDuration)
        ScaleAnimation.animate(hostingView, from: from, to: to, curve: curve)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isHiding, !panel.isPinned else { return }
        hide()
    }

    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = LauncherLayout.windowSize
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + (visible.height - size.height) * 0.68
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    private func showActionMenu() {
        let actions = model.currentActions
        guard !actions.isEmpty, let contentView = panel.contentView else { return }

        let menu = ActionMenu(title: model.selectedItem?.title, actions: actions) { [weak self] index in
            self?.model.performAction(at: index)
        }

        // The hosting view is flipped, matching SwiftUI's global coordinates.
        let anchor: NSPoint
        if let row = model.selectedRowFrame {
            anchor = NSPoint(x: row.maxX - 260, y: row.maxY + 4)
        } else {
            let bounds = contentView.bounds
            anchor = NSPoint(x: bounds.midX, y: bounds.midY)
        }
        menu.popUp(at: anchor, in: contentView)
    }

    // MARK: - Keyboard routing

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

    /// Returns true when the event was consumed by the launcher.
    private func handle(_ event: NSEvent) -> Bool {
        // Let the input method handle keys while composing (e.g. Pinyin candidates).
        if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() {
            return false
        }

        let keyCode = Int(event.keyCode)
        let modifiers = event.modifierFlags.intersection(KeyShortcut.relevantModifiers)

        // Selecting card text took focus from the search field. Anything but copying it gives
        // focus back first, so the keystroke still lands in the search.
        if panel.firstResponder is SelectableTextView, !(keyCode == kVK_ANSI_C && modifiers == .command) {
            focusSearchFieldNow()
        }

        // Typing in a page's own field (e.g. an API key in settings): keys belong to that field.
        // Esc hands focus back to the search field.
        if let editor = panel.firstResponder as? NSTextView, editor.isFieldEditor,
           !((editor.delegate as AnyObject?) is LauncherSearchNSTextField) {
            guard keyCode == kVK_Escape else { return false }
            panel.makeFirstResponder(nil)
            model.focusSearchField()
            return true
        }
        let isReturn = keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter

        if model.pendingConfirmation != nil {
            if isReturn {
                model.confirmPending()
            } else if keyCode == kVK_Escape {
                model.cancelPending()
            }
            return true
        }

        if keyCode == kVK_ANSI_C && modifiers == .command && copySelectedText() {
            return true
        }

        if isReturn && modifiers.isEmpty {
            model.performPrimary()
            return true
        }
        if isReturn && modifiers == .command {
            model.performSecondary()
            return true
        }

        switch keyCode {
        case kVK_UpArrow where modifiers.isEmpty,
             kVK_ANSI_P where modifiers == .control:
            model.moveSelection(by: -1)
            return true
        case kVK_DownArrow where modifiers.isEmpty,
             kVK_ANSI_N where modifiers == .control:
            model.moveSelection(by: 1)
            return true
        case kVK_ANSI_K where modifiers == .command:
            showActionMenu()
            return true
        case kVK_Escape:
            if !model.handleEscape() { hide() }
            return true
        case kVK_Delete where modifiers.isEmpty && model.query.isEmpty && model.canGoBack:
            model.pop()
            return true
        case kVK_ANSI_Comma where modifiers == .command:
            onOpenSettings?()
            return true
        default:
            return model.performShortcut(matching: event)
        }
    }

    private func focusSearchFieldNow() {
        guard let field = hostingView.firstSubview(of: LauncherSearchNSTextField.self) else {
            model.focusSearchField()
            return
        }
        panel.makeFirstResponder(field)
        let end = field.stringValue.utf16.count
        field.currentEditor()?.selectedRange = NSRange(location: end, length: 0)
    }

    /// ⌘C copies whatever text is selected: in the search field, in a card's selectable text, or in
    /// a rendered document. The panel has no Edit menu to route it.
    private func copySelectedText() -> Bool {
        let responder = panel.firstResponder
        if let editor = responder as? NSTextView, editor.selectedRange().length > 0 {
            editor.copy(nil)
            return true
        }
        if let text = TSXDocument.selectedText {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return true
        }
        return false
    }
}

private extension NSView {
    func firstSubview<T: NSView>(of type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T ?? subview.firstSubview(of: type) { return match }
        }
        return nil
    }
}

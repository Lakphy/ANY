import AppKit
import OSLog

/// Decides what the launcher's hotkey opens: the selection popup beside text selected in the
/// frontmost app, or the launcher when nothing is selected. Its tools come from the enabled extensions.
final class SelectionController {
    private let settings: AppSettings
    private let registry: ExtensionRegistry
    private let popup = SelectionPopupController()
    private var readTask: Task<Void, Never>?
    /// The system's permission prompt is shown once per launch, the first time it's needed.
    private var hasPromptedForAccess = false

    private static let maxLength = 5000
    private static let log = Logger(subsystem: "com.lakphy.any", category: "selection")

    init(settings: AppSettings, registry: ExtensionRegistry, host: any ExtensionHost) {
        self.settings = settings
        self.registry = registry
        popup.host = host
    }

    func stop() {
        readTask?.cancel()
        popup.close(animated: false)
    }

    private var tools: [SelectionTool] {
        registry.enabledExtensions.flatMap { $0.selectionTools() }
    }

    /// Shows the popup when text is selected in the frontmost app, and calls `otherwise` (opening
    /// the launcher) when nothing is, or the check isn't possible.
    func handleHotKey(otherwise: @escaping () -> Void) {
        let tools = tools
        let wantsSelection = settings.hotKeyUsesSelection && !tools.isEmpty
        let hasAccess = SelectionReader.hasAccess(prompt: wantsSelection && !hasPromptedForAccess)
        if wantsSelection && !hasAccess { hasPromptedForAccess = true }
        guard wantsSelection, hasAccess else {
            Self.log.info("launcher: enabled=\(self.settings.hotKeyUsesSelection) tools=\(tools.count) accessibility=\(hasAccess)")
            popup.close()
            otherwise()
            return
        }

        let shown = popup.selection
        readTask?.cancel()
        let result = SelectionReader.accessibilitySelection()
        Self.log.info("frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-", privacy: .public) result=\(String(describing: result), privacy: .public)")
        switch result {
        case .selection(let selection):
            // The hotkey on text that's already showing closes it.
            if truncated(selection) == shown {
                popup.close()
            } else {
                present(selection, tools: tools)
            }
        case .empty:
            popup.close()
            otherwise()
        case .unsupported:
            // A synthesized ⌘C has to reach the app, not the popup.
            popup.close(animated: false)
            readTask = Task {
                guard let text = await SelectionReader.copySelection() else {
                    Self.log.info("copy fallback: nothing copied")
                    otherwise()
                    return
                }
                let selection = TextSelection(text: text, bounds: nil)
                guard truncated(selection) != shown else { return }
                present(selection, tools: tools)
            }
        }
    }

    private func present(_ selection: TextSelection, tools: [SelectionTool]) {
        let selection = truncated(selection)
        let anchor = Self.anchor(for: selection.bounds, pointer: NSEvent.mouseLocation)
        popup.show(selection, tools: tools, toolID: popup.lastToolID, near: anchor)
    }

    private func truncated(_ selection: TextSelection) -> TextSelection {
        TextSelection(text: String(selection.text.prefix(Self.maxLength)), bounds: selection.bounds)
    }

    /// The selection itself when the app says where it is and it's a sensible size; otherwise the pointer.
    private static func anchor(for bounds: NSRect?, pointer: NSPoint) -> NSRect {
        if let bounds, bounds.height <= 240 { return bounds }
        return NSRect(x: pointer.x, y: pointer.y - 10, width: 0, height: 20)
    }
}

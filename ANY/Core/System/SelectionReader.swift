import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Text the user has selected in another app.
struct TextSelection: Equatable {
    let text: String
    /// Where the selection is on screen, in AppKit coordinates. Nil when the app doesn't say.
    let bounds: NSRect?
}

/// Reads the selection in the frontmost app. Accessibility answers for native text views and
/// also tells where the selection is; apps that don't expose it (Chrome, many Electron apps) are
/// asked to copy it with a synthesized ⌘C, and the pasteboard is put back afterwards.
/// Both need Accessibility permission.
enum SelectionReader {
    enum AccessibilityResult {
        case selection(TextSelection)
        /// The focused element reports its selection, and nothing is selected.
        case empty
        /// The app doesn't report a selection through Accessibility.
        case unsupported
    }

    /// Long enough for a busy app, short enough not to stall the main thread on a hung one.
    private static let messagingTimeout: Float = 0.25
    /// Processes already asked to build their accessibility tree.
    private static var preparedProcesses: Set<pid_t> = []

    static func hasAccess(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Adds ANY to the Accessibility list and opens it in System Settings.
    static func requestAccess() {
        _ = hasAccess(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func accessibilitySelection() -> AccessibilityResult {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .unsupported }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        prepare(application, pid: app.processIdentifier)

        guard let focused = element(application, kAXFocusedUIElementAttribute) else { return .unsupported }
        AXUIElementSetMessagingTimeout(focused, messagingTimeout)
        guard let value = attribute(focused, kAXSelectedTextAttribute), let text = value as? String else {
            return .unsupported
        }
        guard let cleaned = clean(text) else { return .empty }
        return .selection(TextSelection(text: cleaned, bounds: selectionBounds(in: focused)))
    }

    /// Copies the selection with ⌘C and reads it, leaving the pasteboard as it was. With nothing
    /// selected, apps don't answer; give up quickly so the launcher isn't kept waiting.
    static func copySelection() async -> String? {
        await Pasteboard.borrow { () async -> String? in
            let pasteboard = NSPasteboard.general
            let changeCount = pasteboard.changeCount
            Pasteboard.postCommandKey(CGKeyCode(kVK_ANSI_C))
            for _ in 0..<15 {
                try? await Task.sleep(for: .milliseconds(10))
                guard pasteboard.changeCount != changeCount else { continue }
                // Some apps clear the pasteboard a moment before writing to it.
                try? await Task.sleep(for: .milliseconds(20))
                return pasteboard.string(forType: .string).flatMap(clean)
            }
            return nil
        }
    }

    // MARK: - Accessibility

    /// Chromium-based apps only build their accessibility tree once something asks for it.
    private static func prepare(_ application: AXUIElement, pid: pid_t) {
        guard preparedProcesses.insert(pid).inserted else { return }
        AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func selectionBounds(in element: AXUIElement) -> NSRect? {
        guard let range = attribute(element, kAXSelectedTextRangeAttribute) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            range,
            &value
        ) == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgRect, &rect),
              rect.width > 0 || rect.height > 0
        else { return nil }
        return appKitRect(fromScreenRect: rect)
    }

    /// Accessibility measures from the top-left of the primary display; AppKit from its bottom-left.
    private static func appKitRect(fromScreenRect rect: CGRect) -> NSRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        let converted = NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        let probe = converted.insetBy(dx: -1, dy: -1)
        guard NSScreen.screens.contains(where: { $0.frame.intersects(probe) }) else { return nil }
        return converted
    }

    private static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

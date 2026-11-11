import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum Pasteboard {
    /// Set while ANY borrows the pasteboard to read a selection; clipboard history ignores it.
    private(set) static var isBorrowed = false
    /// The change count left by putting borrowed contents back, which clipboard history skips too.
    private(set) static var restoredChangeCount: Int?

    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Whether ANY may synthesize keystrokes. Pass `prompt: true` to show the system permission dialog.
    static func canSimulatePaste(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Sends ⌘V to the frontmost app. Call after the launcher has been hidden; waits for its
    /// exit animation so the keystroke reaches the app underneath.
    static func simulatePaste() async {
        try? await Task.sleep(for: .seconds(Motion.dismissDuration) + .milliseconds(80))
        postCommandKey(CGKeyCode(kVK_ANSI_V))
    }

    /// Sends ⌘ plus `keyCode` to the frontmost app, regardless of which modifiers are held down.
    static func postCommandKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Runs `body`, then puts back everything the pasteboard held if `body` changed it.
    static func borrow<T>(_ body: () async -> T) async -> T {
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        let changeCount = pasteboard.changeCount
        isBorrowed = true
        defer { isBorrowed = false }

        let result = await body()
        if pasteboard.changeCount != changeCount {
            pasteboard.clearContents()
            pasteboard.writeObjects(saved.map { entries in
                let item = NSPasteboardItem()
                for (type, data) in entries {
                    item.setData(data, forType: type)
                }
                return item
            })
            restoredChangeCount = pasteboard.changeCount
        }
        return result
    }
}

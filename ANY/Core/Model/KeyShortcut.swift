import AppKit
import Carbon.HIToolbox

struct KeyShortcut: Equatable {
    enum Key: Equatable {
        case character(Character)
        case `return`
        case delete
    }

    var key: Key
    var modifiers: NSEvent.ModifierFlags

    init(_ key: Key, modifiers: NSEvent.ModifierFlags = []) {
        self.key = key
        self.modifiers = modifiers
    }

    static let primary = KeyShortcut(.return)
    static let secondary = KeyShortcut(.return, modifiers: [.command])

    static let relevantModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    func matches(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(Self.relevantModifiers) == modifiers else { return false }
        switch key {
        case .return:
            return event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter)
        case .delete:
            return event.keyCode == UInt16(kVK_Delete)
        case .character(let character):
            return event.charactersIgnoringModifiers?.lowercased() == String(character).lowercased()
        }
    }

    /// As shown in key hints, e.g. "⌥⌘C".
    var displayText: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        switch key {
        case .return: text += "↩"
        case .delete: text += "⌫"
        case .character(let character): text += String(character).uppercased()
        }
        return text
    }

    /// Key equivalent string for `NSMenuItem`.
    var keyEquivalent: String {
        switch key {
        case .return: "\r"
        case .delete: "\u{8}"
        case .character(let character): String(character).lowercased()
        }
    }
}

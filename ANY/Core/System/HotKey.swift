import Carbon.HIToolbox
import SwiftUI

struct HotKey: Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let displayText: String
}

enum HotKeyPreset: String, CaseIterable, Identifiable {
    case optionSpace
    case commandOptionSpace
    case controlOptionSpace
    case commandShiftSpace

    var id: String { rawValue }

    var hotKey: HotKey {
        let space = UInt32(kVK_Space)
        switch self {
        case .optionSpace:
            return HotKey(keyCode: space, carbonModifiers: UInt32(optionKey), displayText: "⌥ Space")
        case .commandOptionSpace:
            return HotKey(keyCode: space, carbonModifiers: UInt32(cmdKey | optionKey), displayText: "⌥⌘ Space")
        case .controlOptionSpace:
            return HotKey(keyCode: space, carbonModifiers: UInt32(controlKey | optionKey), displayText: "⌃⌥ Space")
        case .commandShiftSpace:
            return HotKey(keyCode: space, carbonModifiers: UInt32(cmdKey | shiftKey), displayText: "⇧⌘ Space")
        }
    }

    var keyboardShortcut: KeyboardShortcut {
        switch self {
        case .optionSpace: KeyboardShortcut(.space, modifiers: .option)
        case .commandOptionSpace: KeyboardShortcut(.space, modifiers: [.command, .option])
        case .controlOptionSpace: KeyboardShortcut(.space, modifiers: [.control, .option])
        case .commandShiftSpace: KeyboardShortcut(.space, modifiers: [.command, .shift])
        }
    }
}

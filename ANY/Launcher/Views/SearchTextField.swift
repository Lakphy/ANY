import AppKit
import SwiftUI

/// Borderless search field whose text stays on the same baseline whether or not it's being edited.
///
/// SwiftUI's `TextField` (and a stock `NSTextField`) draws unfocused text with the cell but focused
/// text with the field editor, which lays out a point higher. Here both use the same vertically
/// centered rect, sized to the font's natural line height so the two renderings coincide.
struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let font: NSFont
    /// Changing this value moves keyboard focus into the field.
    let focusRequest: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = LauncherSearchNSTextField()
        let cell = BaselineStableTextFieldCell(textCell: "")
        cell.isEditable = true
        cell.isSelectable = true
        cell.isScrollable = true
        cell.wraps = false
        cell.usesSingleLineMode = true
        cell.lineBreakMode = .byClipping
        field.cell = cell

        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = font
        field.textColor = .labelColor
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text {
            field.stringValue = text
        }
        if field.placeholderString != placeholder {
            field.placeholderAttributedString = NSAttributedString(
                string: placeholder,
                attributes: [.font: font, .foregroundColor: NSColor.placeholderTextColor]
            )
        }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            Task {
                field.window?.makeFirstResponder(field)
                let end = field.stringValue.utf16.count
                field.currentEditor()?.selectedRange = NSRange(location: end, length: 0)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var lastFocusRequest: Int?

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

/// Distinguishes the launcher's own search field from text fields inside pages (e.g. settings),
/// so launcher shortcuts only apply while typing a search.
final class LauncherSearchNSTextField: NSTextField {}

private final class BaselineStableTextFieldCell: NSTextFieldCell {
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        var titleRect = super.titleRect(forBounds: rect)
        guard let font else { return titleRect }
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        titleRect.origin.y += floor((titleRect.height - lineHeight) / 2)
        titleRect.size.height = lineHeight
        return titleRect
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: titleRect(forBounds: cellFrame), in: controlView)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: titleRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: titleRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

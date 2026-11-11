import AppKit
import SwiftUI

/// Read-only text the user can drag to select and copy with ⌘C, inside launcher cards.
///
/// Backed by a plain `NSTextView` rather than SwiftUI's `textSelection`, so the launcher knows
/// exactly who holds focus: selecting takes it from the search field, and the launcher hands it
/// back on the next keystroke.
struct SelectableText: NSViewRepresentable {
    let text: String
    let font: NSFont
    var color: NSColor = .labelColor
    var lineLimit = 0

    func makeNSView(context: Context) -> SelectableTextView {
        let view = SelectableTextView()
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.setContentHuggingPriority(.defaultHigh, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateNSView(_ view: SelectableTextView, context: Context) {
        view.textContainer?.maximumNumberOfLines = lineLimit
        view.textContainer?.lineBreakMode = lineLimit > 0 ? .byTruncatingTail : .byWordWrapping
        if view.string != text || view.font != font || view.textColor != color {
            view.string = text
            view.font = font
            view.textColor = color
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: SelectableTextView, context: Context) -> CGSize? {
        guard let container = view.textContainer, let layout = view.layoutManager else { return nil }
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 10_000
        container.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        return CGSize(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? ceil(used.width), height: ceil(used.height))
    }
}

final class SelectableTextView: NSTextView {
    /// A selection left behind after focus moves on would be copied by nothing and only look stale.
    override func resignFirstResponder() -> Bool {
        setSelectedRange(NSRange(location: 0, length: 0))
        return super.resignFirstResponder()
    }

    /// Without a selection there's nothing for the text menu to act on; show the row's actions instead.
    override func menu(for event: NSEvent) -> NSMenu? {
        selectedRange().length > 0 ? super.menu(for: event) : superview?.menu(for: event)
    }
}

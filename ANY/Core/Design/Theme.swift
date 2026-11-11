import AppKit
import SwiftUI

/// ANY's design tokens. Views take sizes, spacing and shapes from here rather than literals,
/// so everything shares one type scale, a 4pt spacing grid and one set of edges.
///
/// Geometry is built inside out: an icon sits the same distance from its row's top, left and
/// bottom edges, and every container's corner radius is its content's radius plus that inset,
/// so nested corners stay parallel (tile → row → panel, badge → toast).
///
/// Color is strictly black, white and gray: text uses the primary / secondary / tertiary
/// hierarchy, surfaces use the system fills listed in `Fill`.
enum Theme {
    enum Typography {
        /// Calculator results.
        static let display = Font.system(size: 28, weight: .semibold)
        /// Search text and page titles in the search bar.
        static let title = Font.system(size: titleSize)
        static let titleSize: CGFloat = 20
        static let titleNSFont = NSFont.systemFont(ofSize: titleSize)
        /// Card headings, confirmation titles.
        static let headline = Font.system(size: 15, weight: .semibold)
        /// The main text of a card, such as a translation.
        static let lead = Font.system(size: 15)
        static let body = Font.system(size: 13)
        static let bodyMedium = Font.system(size: 13, weight: .medium)
        static let bodySemibold = Font.system(size: 13, weight: .semibold)
        static let callout = Font.system(size: 12)
        /// Subtitles, accessories, metadata.
        static let caption = Font.system(size: 11)
        /// Section headers.
        static let captionSemibold = Font.system(size: 11, weight: .semibold)
        /// Chart axes.
        static let micro = Font.system(size: 10)
    }

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    enum IconSize {
        /// Result rows.
        static let row: CGFloat = 28
        /// Sidebar rows, settings lists, the search bar's leading glyph.
        static let small: CGFloat = 20
        /// About page.
        static let hero: CGFloat = 48
    }

    enum Metrics {
        static let panelWidth: CGFloat = 680
        static let searchBarHeight: CGFloat = 56
        static let rowHeight: CGFloat = 44
        /// Compact rows keep the same 8pt inset around their smaller icon.
        static let compactRowHeight: CGFloat = IconSize.small + rowInset * 2
        static let sidebarWidth: CGFloat = 200
        /// Gap between the panel edge and rows, so the selection highlight floats inside the panel.
        static let listInset: CGFloat = Space.s
        /// Space around a row's icon, equal on the top, left and bottom: (44 − 28) / 2.
        static let rowInset: CGFloat = (rowHeight - IconSize.row) / 2
        /// Panel edge to content. Row icons, the search glyph, section headers, the divider and
        /// detail pages all start here.
        static let contentInset: CGFloat = listInset + rowInset
        /// Padding inside cards, equal on every side.
        static let cardPadding: CGFloat = Space.l
        /// Icon-to-text gap in rows, also used after the search bar's glyph so their text lines up.
        static let iconGap: CGFloat = Space.s
        static let leadingGlyphWidth: CGFloat = IconSize.row
    }

    enum Radius {
        static let panel: CGFloat = 24
        /// Icon tiles, proportional to size (8pt at 28pt).
        static func tile(_ size: CGFloat) -> CGFloat { (size * 2 / 7).rounded() }
        /// Row highlight: the icon tile's radius plus the inset around it.
        static let row: CGFloat = tile(IconSize.row) + Metrics.rowInset
        static let compactRow: CGFloat = tile(IconSize.small) + Metrics.rowInset
        /// Cards share the row radius so the highlight morphs between them without changing shape.
        static let card: CGFloat = row
    }

    static func itemShape(radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

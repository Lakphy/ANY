import AppKit

/// Borderless, non-activating floating panel: it takes keyboard focus without
/// activating ANY, so the previously frontmost app stays frontmost (needed for paste).
///
/// Pinning leaves the panel up after it resigns key. A drag then moves it, and the
/// bottom-right handle resizes it until it's unpinned.
final class LauncherPanel: NSPanel {
    var isPinned = false {
        didSet {
            guard isPinned != oldValue else { return }
            if !isPinned {
                replayMouseDown = false
                suppressMouseUp = false
            }
            hidesOnDeactivate = false
            canHide = !isPinned
            collectionBehavior = isPinned ? Self.pinnedBehavior : Self.restingBehavior
            if isPinned, isVisible {
                orderFrontRegardless()
            }
        }
    }

    /// The mouse-down that started a window drag has been replayed as a click; deliver it as-is.
    private var replayMouseDown = false
    /// The window server owns the drag, so the mouse-up that ends it must not also activate a row.
    private var suppressMouseUp = false

    private static let dragThreshold: CGFloat = 4

    private static let restingBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle
    ]
    /// Stationary so Mission Control and deactivation don't tuck a pinned panel away.
    /// Floating windows otherwise default to transient.
    private static let pinnedBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle
    ]

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = Self.restingBehavior
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

    override func sendEvent(_ event: NSEvent) {
        if isPointerDragEvent(event), consumePinnedPointerEvent(event) {
            return
        }
        super.sendEvent(event)
    }

    private func isPointerDragEvent(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp: true
        default: false
        }
    }

    /// A still click is replayed, so rows and the pin keep working. Once the pointer moves,
    /// the window server drags the panel — past its edges and onto another display — and the
    /// content never sees the mouse-down, so the drag can't also open a row. AppKit controls
    /// are left alone so the search field can select text.
    private func consumePinnedPointerEvent(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown:
            if replayMouseDown {
                replayMouseDown = false
                return false
            }
            return trackPinnedDrag(event)
        case .leftMouseDragged:
            return suppressMouseUp
        case .leftMouseUp:
            if suppressMouseUp {
                suppressMouseUp = false
                return true
            }
            return false
        default:
            return false
        }
    }

    private func trackPinnedDrag(_ event: NSEvent) -> Bool {
        suppressMouseUp = false
        guard isPinned, !ignoresMouseEvents else { return false }
        if isOnResizeHandle(event) {
            trackResize(from: event)
            return true
        }
        guard !hitIsNativeControl(event) else { return false }

        let start = NSEvent.mouseLocation
        var mouseUp: NSEvent?
        var dragged = false
        while let next = nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp {
                mouseUp = next
                break
            }
            let loc = NSEvent.mouseLocation
            if hypot(loc.x - start.x, loc.y - start.y) >= Self.dragThreshold {
                dragged = true
                break
            }
        }

        if dragged {
            suppressMouseUp = true
            performDrag(with: event)
            return true
        }
        // The mouse-up was taken off the queue to tell a click from a drag. Put the pair
        // back, mouse-down first, and let the replayed mouse-down through unchanged.
        guard let mouseUp else { return true }
        replayMouseDown = true
        NSApp.postEvent(mouseUp, atStart: true)
        NSApp.postEvent(event, atStart: true)
        return true
    }

    private func isOnResizeHandle(_ event: NSEvent) -> Bool {
        let point = event.locationInWindow
        let reach = LauncherLayout.resizeCornerReach
        return point.x >= frame.width - LauncherLayout.margin - reach
            && point.x <= frame.width
            && point.y >= 0
            && point.y <= LauncherLayout.margin + reach
    }

    /// The top-left stays put; the bottom-right follows the pointer.
    private func trackResize(from event: NSEvent) {
        let anchor = NSEvent.mouseLocation
        let start = frame
        let cursor = NSCursor.frameResize(position: .bottomRight, directions: .all)
        cursor.push()
        defer { NSCursor.pop() }
        while let next = nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            cursor.set()
            setFrame(resizedFrame(from: start, pointer: NSEvent.mouseLocation, anchor: anchor), display: true)
        }
    }

    private func resizedFrame(from start: NSRect, pointer: NSPoint, anchor: NSPoint) -> NSRect {
        let minimum = LauncherLayout.minimumWindowSize
        var width = max(minimum.width, start.width + (pointer.x - anchor.x))
        var height = max(minimum.height, start.height - (pointer.y - anchor.y))
        let top = start.maxY
        if let visible = visibleFrame(containing: start) {
            width = min(width, max(minimum.width, visible.maxX - start.minX))
            height = min(height, max(minimum.height, top - visible.minY))
        }
        return NSRect(x: start.minX, y: top - height, width: width, height: height)
    }

    private func visibleFrame(containing rect: NSRect) -> NSRect? {
        NSScreen.screens.max { lhs, rhs in
            area(lhs.visibleFrame.intersection(rect)) < area(rhs.visibleFrame.intersection(rect))
        }?.visibleFrame
    }

    private func area(_ rect: NSRect) -> CGFloat {
        guard !rect.isNull, !rect.isEmpty else { return 0 }
        return rect.width * rect.height
    }

    private func hitIsNativeControl(_ event: NSEvent) -> Bool {
        guard let contentView else { return false }
        let point = contentView.convert(event.locationInWindow, from: nil)
        var view = contentView.hitTest(point)
        while let current = view, current !== contentView {
            if current is NSText || current is NSControl { return true }
            view = current.superview
        }
        return false
    }
}

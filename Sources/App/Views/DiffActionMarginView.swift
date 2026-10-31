import AppKit

/// A dedicated, text-free margin on the seam edge of each DiffEditor: trailing on the left pane,
/// leading (before the line numbers) on the right pane. The per-hunk action arrow lives here so it
/// never overlaps text or line numbers and always gets a standard arrow cursor.
public final class DiffActionMarginView: NSView {
    public override var isFlipped: Bool { return true }
    public static let width: CGFloat = 32.0

    /// Which pane this margin belongs to; decides which row kinds it tints.
    public var side: EditorSide = .left {
        didSet { needsDisplay = true }
    }

    /// Distance from the top of the document to the top of this view (editor-local, find-bar aware).
    public var scrollOffset: CGFloat = 0.0 {
        didSet {
            if scrollOffset != oldValue {
                needsDisplay = true
            }
        }
    }

    public var rowInfos: [RulerRowInfo] = [] {
        didSet {
            needsDisplay = true
        }
    }

    public weak var targetScrollView: NSScrollView?
    public var onHoverRow: ((Int?) -> Void)?
    private var trackingArea: NSTrackingArea?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        setAccessibilityElement(false)
    }

    public override func scrollWheel(with event: NSEvent) {
        if let scroll = targetScrollView {
            scroll.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    public override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    public override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        NSCursor.arrow.set()
    }

    public override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
        let point = convert(event.locationInWindow, from: nil)
        if let rowIdx = rowIndex(atY: point.y, scrollOffset: scrollOffset), rowIdx < rowInfos.count {
            onHoverRow?(rowIdx)
        } else {
            onHoverRow?(nil)
        }
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverRow?(nil)
    }

    public override func draw(_ dirtyRect: NSRect) {
        let lineHeight = DiffTheme.editorLineHeight

        // Left margin continues the text area; right margin continues the line-number gutter.
        let base = (side == .left) ? NSColor.textBackgroundColor : DiffTheme.gutterBackground
        base.setFill()
        dirtyRect.fill()

        guard let rows = visibleRowRange(in: dirtyRect, scrollOffset: scrollOffset, rowCount: rowInfos.count) else { return }

        for rowIdx in rows {
            let info = rowInfos[rowIdx]
            let rowY = DiffTheme.editorTextInsetY + CGFloat(rowIdx) * lineHeight - scrollOffset
            let rowRect = NSRect(x: 0, y: rowY, width: bounds.width, height: lineHeight)

            if info.kind == .spacer {
                DiffTheme.drawSpacer(in: rowRect, dirtyRect: dirtyRect)
            } else if info.kind == .deletion && side == .left {
                DiffTheme.deletionBackground.setFill()
                rowRect.intersection(dirtyRect).fill()
            } else if info.kind == .addition && side == .right {
                DiffTheme.additionGutterBackground.setFill()
                rowRect.intersection(dirtyRect).fill()
            }
        }
    }
}

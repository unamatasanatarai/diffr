import AppKit

public struct RulerRowInfo {
    public let lineNumber: Int?
    public let kind: DiffLineKind
    public let hunkIndex: Int?

    public init(lineNumber: Int?, kind: DiffLineKind, hunkIndex: Int?) {
        self.lineNumber = lineNumber
        self.kind = kind
        self.hunkIndex = hunkIndex
    }
}

/// Visible aligned-row range for a strip that shares the editor's vertical row grid.
func visibleRowRange(in rect: NSRect, scrollOffset: CGFloat, rowCount: Int) -> ClosedRange<Int>? {
    guard rowCount > 0 else { return nil }
    let lineHeight = DiffTheme.editorLineHeight
    let base = DiffTheme.editorTextInsetY - scrollOffset
    let first = max(0, Int(floor((rect.minY - base) / lineHeight)))
    let last = min(rowCount - 1, Int(ceil((rect.maxY - base) / lineHeight)))
    return first <= last ? first...last : nil
}

/// Row index under a point in a strip that shares the editor's vertical row grid.
func rowIndex(atY y: CGFloat, scrollOffset: CGFloat) -> Int? {
    let docY = y + scrollOffset - DiffTheme.editorTextInsetY
    guard docY >= 0 else { return nil }
    return Int(docY / DiffTheme.editorLineHeight)
}

public final class LineNumberRulerView: NSView {
    public override var isFlipped: Bool { return true }

    public static let leftMargin: CGFloat = 8.0
    public static let gap: CGFloat = 6.0
    public static let indicatorWidth: CGFloat = 10.0
    public static let rightMargin: CGFloat = 8.0
    public static let minGutterWidth: CGFloat = 36.0

    public static func requiredWidth(forMaxLineNumber maxLine: Int) -> CGFloat {
        let maxStr = "\(max(maxLine, 1))" as NSString
        let numWidth = ceil(maxStr.size(withAttributes: lineNumberAttrs).width)
        let total = leftMargin + numWidth + gap + indicatorWidth + rightMargin
        return max(minGutterWidth, ceil(total))
    }

    public let side: EditorSide
    public var rowInfos: [RulerRowInfo] = [] {
        didSet {
            updateRequiredGutterWidth()
            needsDisplay = true
        }
    }
    public var currentMaxLineNumber: Int = 1 {
        didSet {
            if currentMaxLineNumber != oldValue {
                updateRequiredGutterWidth()
            }
        }
    }
    public var onGutterWidthNeeded: ((CGFloat) -> Void)?

    /// Distance from the top of the document to the top of this view (editor-local, find-bar aware).
    public var scrollOffset: CGFloat = 0.0 {
        didSet {
            if scrollOffset != oldValue {
                needsDisplay = true
            }
        }
    }
    public var hoveredHunkIndex: Int? = nil {
        didSet {
            if hoveredHunkIndex != oldValue {
                needsDisplay = true
            }
        }
    }
    public var onHoverRow: ((Int?) -> Void)?
    public weak var targetScrollView: NSScrollView?

    private var trackingArea: NSTrackingArea?

    private static let lineNumberAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor.secondaryLabelColor
    ]
    private static let indicatorFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)

    public init(side: EditorSide) {
        self.side = side
        let initialWidth = Self.requiredWidth(forMaxLineNumber: 1)
        super.init(frame: NSRect(x: 0, y: 0, width: initialWidth, height: 100))
        wantsLayer = true
        setAccessibilityElement(false)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func updateRequiredGutterWidth() {
        let maxInRows = rowInfos.compactMap { $0.lineNumber }.max() ?? 1
        let maxLine = max(maxInRows, currentMaxLineNumber, 1)
        let needed = Self.requiredWidth(forMaxLineNumber: maxLine)
        onGutterWidthNeeded?(needed)
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
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    public override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let rowIdx = rowIndex(atY: point.y, scrollOffset: scrollOffset),
           rowIdx < rowInfos.count, let hIdx = rowInfos[rowIdx].hunkIndex {
            hoveredHunkIndex = hIdx
            onHoverRow?(rowIdx)
        } else {
            hoveredHunkIndex = nil
            onHoverRow?(nil)
        }
    }

    public override func mouseExited(with event: NSEvent) {
        hoveredHunkIndex = nil
        onHoverRow?(nil)
    }

    public override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    public override func draw(_ dirtyRect: NSRect) {
        let lineHeight = DiffTheme.editorLineHeight

        DiffTheme.gutterBackground.setFill()
        dirtyRect.fill()

        // Separator border on right edge
        DiffTheme.gutterBorder.setFill()
        NSRect(x: bounds.width - 1, y: dirtyRect.origin.y, width: 1, height: dirtyRect.height).fill()

        let displayInfos = rowInfos.isEmpty ? [RulerRowInfo(lineNumber: 1, kind: .unchanged, hunkIndex: nil)] : rowInfos
        guard let rows = visibleRowRange(in: dirtyRect, scrollOffset: scrollOffset, rowCount: displayInfos.count) else { return }

        // Layout within bounds.width:
        // [leftMargin] [num right-aligned to numRightX] [gap] [indicator at indicatorX] [rightMargin] [1px border]
        let numRightX = bounds.width - Self.rightMargin - Self.indicatorWidth - Self.gap
        let indicatorX = numRightX + Self.gap

        for rowIdx in rows {
            let info = displayInfos[rowIdx]
            let rowY = DiffTheme.editorTextInsetY + CGFloat(rowIdx) * lineHeight - scrollOffset
            let rowRect = NSRect(x: 0, y: rowY, width: bounds.width - 1, height: lineHeight)

            if info.kind == .spacer {
                DiffTheme.drawSpacer(in: rowRect, dirtyRect: dirtyRect)
                continue
            } else if info.kind == .deletion && side == .left {
                DiffTheme.deletionGutterBackground.setFill()
                rowRect.fill()
            } else if info.kind == .addition && side == .right {
                DiffTheme.additionGutterBackground.setFill()
                rowRect.fill()
            }

            if let num = info.lineNumber {
                let numStr = "\(num)" as NSString
                let numSize = numStr.size(withAttributes: Self.lineNumberAttrs)
                let numY = rowRect.origin.y + (rowRect.height - numSize.height) / 2
                let numX = max(Self.leftMargin, numRightX - numSize.width)
                numStr.draw(at: NSPoint(x: numX, y: numY), withAttributes: Self.lineNumberAttrs)
            }

            let indicator: (NSString, NSColor)?
            if info.kind == .deletion && side == .left {
                indicator = ("-", DiffTheme.deletionIndicatorColor)
            } else if info.kind == .addition && side == .right {
                indicator = ("+", DiffTheme.additionIndicatorColor)
            } else {
                indicator = nil
            }
            if let (glyph, color) = indicator {
                let attrs: [NSAttributedString.Key: Any] = [.font: Self.indicatorFont, .foregroundColor: color]
                let size = glyph.size(withAttributes: attrs)
                let glyphX = indicatorX + (Self.indicatorWidth - size.width) / 2
                glyph.draw(at: NSPoint(x: glyphX, y: rowRect.origin.y + (rowRect.height - size.height) / 2), withAttributes: attrs)
            }
        }
    }
}

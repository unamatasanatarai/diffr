import AppKit

public final class InvisibilityLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    public var showsInvisibles: Bool = false {
        didSet {
            guard showsInvisibles != oldValue else { return }
            firstTextView?.needsDisplay = true
        }
    }

    /// Per-row diff styling, indexed by aligned row (0-based).
    public var lineKinds: [DiffLineKind] = []

    /// Word-level highlight spans: alignedRowIndex (0-based) -> [WordHighlightSpan]
    public var lineWordHighlights: [Int: [WordHighlightSpan]] = [:]

    /// Line character ranges in textStorage, indexed by aligned row. Spacer rows hold `NSNotFound`.
    public var lineCharacterRanges: [NSRange] = []

    public override init() {
        super.init()
        delegate = self
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    // MARK: - Line breaking

    /// Only "\n" starts a new line, matching `DiffEngine.splitLines`. Other paragraph/line
    /// separators (lone CR, U+2028, U+2029, NEL, VT, FF) would otherwise create extra visual
    /// lines that the diff model does not know about and break row alignment.
    public func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldUse action: NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt charIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        guard let storage = textStorage, charIndex < storage.length else { return action }
        switch storage.mutableString.character(at: charIndex) {
        case 0x0D, 0x0B, 0x0C, 0x85, 0x2028, 0x2029:
            return .zeroAdvancement
        default:
            return action
        }
    }

    // MARK: - Diff Backgrounds (called by DiffTextView before selection/glyphs are drawn)

    /// - Parameters:
    ///   - rowOriginY: y of aligned row 0 in view coordinates (the fixed row grid).
    ///   - containerOrigin: text container origin, for converting glyph rects to view coordinates.
    public func drawDiffBackground(in dirtyRect: NSRect, rowOriginY: CGFloat, containerOrigin origin: NSPoint, viewWidth: CGFloat) {
        let lineHeight = DiffTheme.editorLineHeight
        guard !lineKinds.isEmpty else { return }

        let firstRow = max(0, Int(floor((dirtyRect.minY - rowOriginY) / lineHeight)))
        let lastRow = min(lineKinds.count - 1, Int(ceil((dirtyRect.maxY - rowOriginY) / lineHeight)))
        guard firstRow <= lastRow else { return }

        let fillWidth = max(viewWidth, dirtyRect.maxX)

        for rowIdx in firstRow...lastRow {
            let kind = lineKinds[rowIdx]
            guard kind != .unchanged else { continue }

            let lineRect = NSRect(x: 0, y: rowOriginY + CGFloat(rowIdx) * lineHeight, width: fillWidth, height: lineHeight)

            if kind == .spacer {
                DiffTheme.drawSpacer(in: lineRect, dirtyRect: dirtyRect)
                continue
            }

            let bgColor = (kind == .addition) ? DiffTheme.additionBackground : DiffTheme.deletionBackground
            bgColor.setFill()
            lineRect.intersection(dirtyRect).fill()

            let borderColor = (kind == .addition) ? DiffTheme.additionBorder : DiffTheme.deletionBorder
            borderColor.setFill()
            NSRect(x: 0, y: lineRect.origin.y, width: 3, height: lineRect.height).fill()

            // Word-level highlights inside modified lines
            if let words = lineWordHighlights[rowIdx],
               rowIdx < lineCharacterRanges.count,
               lineCharacterRanges[rowIdx].location != NSNotFound,
               let container = textContainers.first {
                let range = lineCharacterRanges[rowIdx]
                let storageLength = textStorage?.length ?? 0
                let wordBgColor = (kind == .addition) ? DiffTheme.additionWordHighlight : DiffTheme.deletionWordHighlight
                wordBgColor.setFill()

                for wordSpan in words {
                    let absolute = NSRange(location: range.location + wordSpan.range.location, length: wordSpan.range.length)
                    guard NSMaxRange(absolute) <= storageLength else { continue }
                    let glyphs = glyphRange(forCharacterRange: absolute, actualCharacterRange: nil)
                    guard glyphs.length > 0 else { continue }
                    // Horizontal extent from glyph positions: enclosing rects of control glyphs
                    // (e.g. a trailing "\r") stretch to the end of the line fragment.
                    let startX = location(forGlyphAt: glyphs.location).x
                    let lastGlyph = NSMaxRange(glyphs) - 1
                    let lastBounds = boundingRect(forGlyphRange: NSRange(location: lastGlyph, length: 1), in: container)
                    let fragment = lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
                    let endX = min(lastBounds.maxX - fragment.minX, location(forGlyphAt: lastGlyph).x + 2 * DiffTheme.editorFont.maximumAdvancement.width)
                    // Clamp vertically to the row so paragraph spacing above the line is not tinted.
                    let highlight = NSRect(
                        x: origin.x + fragment.minX + startX,
                        y: lineRect.origin.y + 2,
                        width: max(2, endX - startX), // zero-width chars stay visible
                        height: lineHeight - 4
                    )
                    NSBezierPath(roundedRect: highlight, xRadius: 2, yRadius: 2).fill()
                }
            }
        }
    }

    // MARK: - Glyph Drawing (Invisibles)

    public override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)

        guard showsInvisibles, let textStorage = self.textStorage else { return }

        let charRange = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let string = textStorage.mutableString
        let font = DiffTheme.editorFont
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: DiffTheme.invisibleCharacterColor
        ]

        let maxCharIndex = min(string.length, NSMaxRange(charRange))
        guard charRange.location < maxCharIndex else { return }

        for charIdx in charRange.location..<maxCharIndex {
            let ch = string.character(at: charIdx)
            let symbol: String
            var xNudge: CGFloat = 0

            switch ch {
            case 0x20: symbol = "·"
            case 0x09: symbol = "→"
            case 0x0A:
                symbol = "↵"
                xNudge = (charIdx > 0 && string.character(at: charIdx - 1) == 0x0D) ? 12 : 2
            case 0x0D: symbol = "␍"
            case 0xA0, 0x202F, 0x2007: symbol = "⍽" // non-breaking spaces
            case 0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF, 0x0B, 0x0C, 0x85, 0x2028, 0x2029:
                symbol = "¦" // zero-width / unusual separators: the classic "identical-looking" diff trap
                xNudge = -2
            default:
                continue
            }

            let glyphIdx = glyphIndexForCharacter(at: charIdx)
            guard glyphIdx < numberOfGlyphs else { continue }
            let glyphLocation = location(forGlyphAt: glyphIdx)
            let lineRect = lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
            // location(forGlyphAt:) is the baseline; NSString.draw(at:) takes the top-left in a flipped view.
            let point = NSPoint(
                x: origin.x + lineRect.origin.x + glyphLocation.x + xNudge,
                y: origin.y + lineRect.origin.y + glyphLocation.y - font.ascender
            )
            (symbol as NSString).draw(at: point, withAttributes: attrs)
        }
    }
}

/// Text view that paints diff row backgrounds beneath the selection and the glyphs,
/// and lets the owner handle dropped files.
public final class DiffTextView: NSTextView {
    public var onFileDropped: ((URL) -> Void)?
    private var isHandlingFileDrop = false

    public override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        (layoutManager as? InvisibilityLayoutManager)?.drawDiffBackground(
            in: rect,
            rowOriginY: DiffTheme.editorTextInsetY,
            containerOrigin: textContainerOrigin,
            viewWidth: bounds.width
        )
    }

    // MARK: File drop

    private func droppedFileURL(_ info: NSDraggingInfo) -> URL? {
        guard onFileDropped != nil else { return nil }
        let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        return urls?.first
    }

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if droppedFileURL(sender) != nil { return .copy }
        return super.draggingEntered(sender)
    }

    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if droppedFileURL(sender) != nil { return .copy }
        return super.draggingUpdated(sender)
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let url = droppedFileURL(sender), let handler = onFileDropped {
            isHandlingFileDrop = true
            handler(url)
            return true
        }
        return super.performDragOperation(sender)
    }

    public override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        if isHandlingFileDrop {
            isHandlingFileDrop = false
            return
        }
        super.concludeDragOperation(sender)
    }
}

import AppKit

/// Label that never intercepts mouse events (so clicking the placeholder focuses the editor).
final class PassthroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { return nil }
}

public final class DiffEditorView: NSView {
    public let gutterView: LineNumberRulerView
    public let actionMarginView: DiffActionMarginView?
    public let scrollView: NSScrollView
    public let textView: DiffTextView
    public let layoutManager: InvisibilityLayoutManager
    public let textStorage: NSTextStorage
    public let side: EditorSide

    public override var isFlipped: Bool { return true }
    public var onTextChange: (() -> Void)?
    public var onHoverRow: ((Int?) -> Void)?
    public var onMoveHunk: ((Int) -> Void)?
    /// Called when the editor's geometry changes so the owner can keep both panes' document sizes in sync.
    public var onLayout: (() -> Void)?

    public let hunkActionButton = HunkActionButton()
    public var hunkActionButtonHunkId: Int?
    public var allHunks: [DiffHunk] = []
    public let placeholderLabel: NSTextField = PassthroughLabel(labelWithString: "")
    public private(set) var gutterWidthConstraint: NSLayoutConstraint!

    public func setGutterWidth(_ width: CGFloat) {
        if gutterWidthConstraint != nil && gutterWidthConstraint.constant != width {
            gutterWidthConstraint.constant = width
            needsLayout = true
        }
    }


    private var trackingArea: NSTrackingArea?
    private var paragraphStyleCache: [CGFloat: NSParagraphStyle] = [:]

    public init(side: EditorSide) {
        self.side = side

        gutterView = LineNumberRulerView(side: side)
        let margin = DiffActionMarginView()
        margin.side = side
        actionMarginView = margin
        scrollView = NSScrollView()

        textStorage = NSTextStorage()
        layoutManager = InvisibilityLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        // Contiguous layout is deliberate: non-contiguous layout estimates the y of unlaid-out
        // lines, which breaks the exact row alignment the diff backgrounds are painted on.
        // Background layout fills the rest in idle time instead.
        layoutManager.allowsNonContiguousLayout = false
        layoutManager.backgroundLayoutEnabled = true

        let containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let textContainer = NSTextContainer(size: containerSize)
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        textContainer.lineFragmentPadding = 5
        layoutManager.addTextContainer(textContainer)

        textView = DiffTextView(frame: .zero, textContainer: textContainer)

        super.init(frame: .zero)

        setupUI()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shared, immutable paragraph styles (one per spacing value) to avoid per-line allocations.
    public func makeEditorParagraphStyle(spacingBefore: CGFloat = 0.0) -> NSParagraphStyle {
        if let cached = paragraphStyleCache[spacingBefore] { return cached }
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = DiffTheme.editorLineHeight
        style.maximumLineHeight = DiffTheme.editorLineHeight
        style.lineBreakMode = .byClipping
        style.paragraphSpacingBefore = spacingBefore
        let frozen = style.copy() as! NSParagraphStyle
        paragraphStyleCache[spacingBefore] = frozen
        return frozen
    }

    private var baseTextAttributes: [NSAttributedString.Key: Any] {
        return [
            .font: DiffTheme.editorFont,
            .paragraphStyle: makeEditorParagraphStyle(),
            .foregroundColor: NSColor.textColor
        ]
    }

    private func setupUI() {
        wantsLayer = true

        textView.font = DiffTheme.editorFont
        textView.defaultParagraphStyle = makeEditorParagraphStyle()
        textView.typingAttributes = baseTextAttributes
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.textColor
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = []
        textView.textContainerInset = NSSize(width: 4, height: DiffTheme.editorTextInsetY)

        // A diff tool must never silently rewrite what the user typed or pasted.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false

        textView.isIncrementalSearchingEnabled = true
        textView.usesFindBar = true
        textView.setAccessibilityLabel(side == .left ? "Original text" : "Modified text")

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChangeNotification(_:)),
            name: NSText.didChangeNotification,
            object: textView
        )

        // Configure scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        scrollView.findBarPosition = .aboveContent
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.postsFrameChangedNotifications = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewGeometryChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        // The find bar shifts the clip view; the gutter must follow or line numbers drift.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewGeometryChanged(_:)),
            name: NSView.frameDidChangeNotification,
            object: scrollView.contentView
        )

        // Gutter setup
        gutterView.translatesAutoresizingMaskIntoConstraints = false
        gutterView.targetScrollView = scrollView
        gutterView.onHoverRow = { [weak self] row in
            self?.onHoverRow?(row)
        }
        gutterView.onGutterWidthNeeded = { [weak self] width in
            self?.setGutterWidth(width)
        }

        addSubview(gutterView)
        addSubview(scrollView)

        if let marginView = actionMarginView {
            marginView.translatesAutoresizingMaskIntoConstraints = false
            marginView.targetScrollView = scrollView
            marginView.onHoverRow = { [weak self] row in
                self?.onHoverRow?(row)
            }
            addSubview(marginView)
        }

        // Floating action button on inner margin
        hunkActionButton.alphaValue = 0.0
        hunkActionButton.isHidden = true
        hunkActionButton.target = self
        hunkActionButton.action = #selector(hunkActionButtonClicked)
        if side == .left {
            hunkActionButton.title = "➔"
            hunkActionButton.toolTip = "Copy this change to the right pane (⌥⌘→)"
            hunkActionButton.setAccessibilityLabel("Copy change to right pane")
        } else {
            hunkActionButton.title = "⬅"
            hunkActionButton.toolTip = "Copy this change to the left pane (⌥⌘←)"
            hunkActionButton.setAccessibilityLabel("Copy change to left pane")
        }
        addSubview(hunkActionButton)

        // Placeholder for intuitive empty state
        let placeholderText = (side == .left)
            ? "Paste, type, or drop the original file here…"
            : "Paste, type, or drop the modified file here…"
        placeholderLabel.stringValue = placeholderText
        placeholderLabel.font = DiffTheme.editorFont
        placeholderLabel.textColor = NSColor.placeholderTextColor
        placeholderLabel.isEditable = false
        placeholderLabel.isSelectable = false
        placeholderLabel.isBezeled = false
        placeholderLabel.drawsBackground = false
        placeholderLabel.lineBreakMode = .byTruncatingTail
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(placeholderLabel)

        gutterWidthConstraint = gutterView.widthAnchor.constraint(
            equalToConstant: LineNumberRulerView.requiredWidth(forMaxLineNumber: 1)
        )

        // Left pane:  [gutter][text][margin] | seam
        // Right pane: seam | [margin][gutter][text]
        let trailingAnchorForText = (side == .left) ? (actionMarginView?.leadingAnchor ?? trailingAnchor) : trailingAnchor
        let gutterLeading = (side == .right) ? (actionMarginView?.trailingAnchor ?? leadingAnchor) : leadingAnchor
        var constraints: [NSLayoutConstraint] = [
            gutterView.topAnchor.constraint(equalTo: topAnchor),
            gutterView.leadingAnchor.constraint(equalTo: gutterLeading),
            gutterView.bottomAnchor.constraint(equalTo: bottomAnchor),
            gutterWidthConstraint,

            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: gutterView.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchorForText),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: DiffTheme.editorTextInsetY + 2),
            placeholderLabel.leadingAnchor.constraint(equalTo: gutterView.trailingAnchor, constant: 10),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchorForText, constant: -10)
        ]
        if let marginView = actionMarginView {
            constraints += [
                marginView.topAnchor.constraint(equalTo: topAnchor),
                side == .left
                    ? marginView.trailingAnchor.constraint(equalTo: trailingAnchor)
                    : marginView.leadingAnchor.constraint(equalTo: leadingAnchor),
                marginView.bottomAnchor.constraint(equalTo: bottomAnchor),
                marginView.widthAnchor.constraint(equalToConstant: DiffActionMarginView.width)
            ]
        }
        NSLayoutConstraint.activate(constraints)

        setupMouseTracking()
    }

    public override func layout() {
        super.layout()
        if let sync = onLayout {
            sync()
        } else {
            updateTextViewSize()
        }
        syncScrollDependentViews()
    }

    // MARK: - Geometry

    /// How far the document is scrolled relative to the top of this editor, including any
    /// find-bar offset. Editor-local y = document y - documentOffsetY.
    public var documentOffsetY: CGFloat {
        return -convert(NSPoint.zero, from: textView).y
    }

    /// Size the document needs on its own: enough rows for the aligned diff and the widest line.
    public func naturalDocumentSize(rowCount: Int? = nil) -> NSSize {
        // Never force layout here: this runs on every keystroke and every diff, and a full
        // TextKit layout of a large file costs ~50µs per line. Every row is exactly
        // `editorLineHeight` tall, so the height is known from counts alone; the width comes
        // from the last diff's estimate plus whatever TextKit has already laid out (which
        // always includes the line being typed in).
        // Lines typed since the last diff are not in rowCount yet; never cut them off.
        let linesSinceDiff = max(0, lineCount - diffedLineCount)
        let rows = max((rowCount ?? gutterView.rowInfos.count) + linesSinceDiff, lineCount, 1)
        let contentHeight = DiffTheme.editorTextInsetY * 2 + CGFloat(rows) * DiffTheme.editorLineHeight

        var usedWidth = CGFloat(estimatedMaxColumns) * DiffTheme.editorFont.maximumAdvancement.width
            + textView.textContainerInset.width * 2 + (textView.textContainer?.lineFragmentPadding ?? 0) * 2
        if let container = textView.textContainer {
            usedWidth = max(usedWidth, layoutManager.usedRect(for: container).width)
        }
        let height = max(scrollView.contentView.bounds.height, contentHeight + 80.0)
        let width = max(scrollView.contentView.bounds.width, usedWidth + 80.0)
        return NSSize(width: ceil(width), height: ceil(height))
    }

    /// Number of lines (same semantics as `DiffEngine.lineRanges`), kept current on every edit.
    public private(set) var lineCount: Int = 0
    /// `lineCount` when the currently applied diff was computed.
    public var diffedLineCount: Int = 0
    /// Upper-bound display width of the widest line, in monospace columns, from the last diff.
    public var estimatedMaxColumns: Int = 0

    /// Spacer rows above the first real line. TextKit ignores `paragraphSpacingBefore` on the
    /// first paragraph, so this offset is applied through the text container inset instead.
    public private(set) var leadingSpacerRows = 0

    public func setLeadingSpacerRows(_ rows: Int) {
        guard rows != leadingSpacerRows else { return }
        leadingSpacerRows = rows
        textView.textContainerInset = NSSize(
            width: 4,
            height: DiffTheme.editorTextInsetY + CGFloat(rows) * DiffTheme.editorLineHeight
        )
        textView.needsDisplay = true
    }

    public func setDocumentSize(_ size: NSSize) {
        if textView.frame.size != size {
            textView.setFrameSize(size)
        }
    }

    public func updateTextViewSize(contentRowCount: Int? = nil) {
        setDocumentSize(naturalDocumentSize(rowCount: contentRowCount))
    }

    private func syncScrollDependentViews() {
        let offset = documentOffsetY
        gutterView.scrollOffset = offset
        actionMarginView?.scrollOffset = offset
        if let hIdx = hunkActionButtonHunkId {
            setHoveredHunkIndex(hIdx)
        }
    }

    // MARK: - Hunk action button

    private func hideHunkActionButton() {
        hunkActionButtonHunkId = nil
        hunkActionButton.alphaValue = 0.0
        // Hidden, not just transparent: an invisible button must not swallow clicks.
        hunkActionButton.isHidden = true
    }

    public func setHoveredHunkIndex(_ hunkIndex: Int?) {
        guard let hIdx = hunkIndex,
              let hunk = (hIdx >= 0 && hIdx < allHunks.count && allHunks[hIdx].id == hIdx)
                ? allHunks[hIdx] : allHunks.first(where: { $0.id == hIdx }) else {
            hideHunkActionButton()
            return
        }

        let isEligible = (side == .left && hunk.kind != .addition) || (side == .right && hunk.kind != .deletion)
        guard isEligible else {
            hideHunkActionButton()
            return
        }

        hunkActionButtonHunkId = hunk.id

        let startRow = hunk.alignedRowRange.lowerBound
        let rowCount = max(1, hunk.alignedRowRange.count)
        let totalHunkHeight = CGFloat(rowCount) * DiffTheme.editorLineHeight
        let yInDoc = DiffTheme.editorTextInsetY + CGFloat(startRow) * DiffTheme.editorLineHeight
        let yInView = yInDoc - documentOffsetY
        let btnHeight: CGFloat = 22.0
        let btnWidth: CGFloat = 24.0
        // Keep the arrow on the first visible line of a tall hunk instead of off-screen in its middle.
        let visibleTop: CGFloat = 0
        let visibleBottom = bounds.height - btnHeight
        let hunkTop = yInView
        let hunkBottom = yInView + totalHunkHeight - btnHeight
        var buttonY = yInView + (totalHunkHeight - btnHeight) / 2.0
        if hunkBottom >= visibleTop && hunkTop <= visibleBottom {
            buttonY = min(max(buttonY, max(hunkTop, visibleTop)), min(hunkBottom, visibleBottom))
        }

        // Centered in the seam margin, with equal air on both sides.
        let inset = (DiffActionMarginView.width - btnWidth) / 2.0
        let btnX: CGFloat = (side == .left) ? bounds.width - btnWidth - inset : inset

        hunkActionButton.frame = NSRect(x: btnX, y: buttonY, width: btnWidth, height: btnHeight)
        hunkActionButton.isHidden = false
        hunkActionButton.alphaValue = 1.0
        window?.invalidateCursorRects(for: hunkActionButton)
    }

    @objc private func hunkActionButtonClicked() {
        guard let hIdx = hunkActionButtonHunkId else { return }
        onMoveHunk?(hIdx)
    }

    private func setupMouseTracking() {
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    @objc private func clipViewGeometryChanged(_ notification: Notification) {
        syncScrollDependentViews()
    }

    public override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onHoverRow?(rowIndex(atY: point.y, scrollOffset: documentOffsetY))
    }

    public override func mouseExited(with event: NSEvent) {
        onHoverRow?(nil)
    }

    // MARK: - Text

    /// Setting replaces the full contents through the undo-aware edit path.
    /// Reading returns the exact contents (lone surrogates included), e.g. for saving.
    /// Hot paths that only need to read the text quickly should use `diffText` instead.
    public var text: String {
        get { return textView.string }
        set { replaceText(with: newValue, actionName: nil) }
    }

    /// Native UTF-8 copy of the contents for the diff engine: a bulk UTF-16 copy plus a fast
    /// transcode. (Iterating the bridged `textView.string` pulls the mutable backing string
    /// through `characterAtIndex:` one unit at a time — over a second for a few MB.)
    /// Lone surrogates become U+FFFD, exactly as Swift's own bridging would make them.
    public var diffText: String {
        return DiffEngine.nativeString(from: textStorage.mutableString)
    }

    /// Replaces the contents with `newValue`, editing only the range that actually differs.
    ///
    /// Goes through `shouldChangeText`/`didChangeText`, so the change is undoable, keeps the
    /// existing undo stack valid, and notifies observers exactly like a user edit.
    public func replaceText(with newValue: String, actionName: String?) {
        let old = textStorage.mutableString
        let new = newValue as NSString
        let oldLength = old.length
        let newLength = new.length

        var prefix = 0
        var suffix = 0
        if oldLength > 0 && newLength > 0 {
            let oldBuf = UnsafeMutablePointer<unichar>.allocate(capacity: oldLength)
            let newBuf = UnsafeMutablePointer<unichar>.allocate(capacity: newLength)
            defer {
                oldBuf.deallocate()
                newBuf.deallocate()
            }
            old.getCharacters(oldBuf, range: NSRange(location: 0, length: oldLength))
            new.getCharacters(newBuf, range: NSRange(location: 0, length: newLength))

            let minLength = min(oldLength, newLength)
            while prefix < minLength && oldBuf[prefix] == newBuf[prefix] { prefix += 1 }
            while suffix < minLength - prefix && oldBuf[oldLength - 1 - suffix] == newBuf[newLength - 1 - suffix] { suffix += 1 }

            // Never split a surrogate pair at either edge of the edit.
            if prefix > 0 && UTF16.isLeadSurrogate(oldBuf[prefix - 1]) { prefix -= 1 }
            if suffix > 0 && UTF16.isTrailSurrogate(oldBuf[oldLength - suffix]) { suffix -= 1 }
        }

        let range = NSRange(location: prefix, length: oldLength - prefix - suffix)
        let replacement = new.substring(with: NSRange(location: prefix, length: newLength - prefix - suffix))
        guard range.length > 0 || !replacement.isEmpty else { return }

        let attributed = NSAttributedString(string: replacement, attributes: baseTextAttributes)
        textView.breakUndoCoalescing()
        // Replacing everything (opening a file, Copy All): TextKit would leave the caret after
        // the inserted text, and `didChangeText` then lays out the whole document synchronously
        // just to place it. Put the caret at the top instead; layout proceeds lazily.
        let replacesEverything = range.location == 0 && range.length == oldLength
        if textView.shouldChangeText(in: range, replacementString: replacement) {
            textStorage.replaceCharacters(in: range, with: attributed)
            if replacesEverything {
                textView.setSelectedRange(NSRange(location: 0, length: 0))
            }
            textView.didChangeText()
            if let name = actionName {
                textView.undoManager?.setActionName(name)
            }
        } else {
            // Not editable: still apply, and notify observers ourselves.
            textStorage.replaceCharacters(in: range, with: attributed)
            NotificationCenter.default.post(name: NSText.didChangeNotification, object: textView)
        }
        textView.breakUndoCoalescing()
    }

    @objc private func textDidChangeNotification(_ notification: Notification) {
        placeholderLabel.isHidden = textStorage.length > 0
        lineCount = DiffEngine.lineCount(in: textStorage.mutableString)
        gutterView.currentMaxLineNumber = max(lineCount, 1)
        gutterView.needsDisplay = true
        onTextChange?()
    }


    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

public final class HunkActionButton: NSButton {
    public override var isFlipped: Bool { return true }
    private var isHovered: Bool = false
    private var hoverTrackingArea: NSTrackingArea?

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
        isBordered = false
        setButtonType(.momentaryPushIn)
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.borderWidth = 0.0
        title = "➔"
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = hoverTrackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    public override var isHidden: Bool {
        didSet {
            if isHidden && isHovered {
                isHovered = false
                needsDisplay = true
            }
        }
    }

    public override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        needsDisplay = true
        NSCursor.arrow.set()
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        needsDisplay = true
    }

    public override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    private func symbolImage(pointSize: CGFloat) -> NSImage? {
        let name = (title == "⬅") ? "arrow.left" : "arrow.right"
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    public override func draw(_ dirtyRect: NSRect) {
        // A crisp SF Symbol arrow. On hover it sits on a soft accent disc — no border, ever.
        let accent = DiffTheme.hoverArrowColor
        let glyphColor: NSColor

        if isHovered {
            let diameter = min(bounds.width, bounds.height)
            let disc = NSRect(
                x: (bounds.width - diameter) / 2.0,
                y: (bounds.height - diameter) / 2.0,
                width: diameter,
                height: diameter
            )
            accent.setFill()
            NSBezierPath(ovalIn: disc).fill()
            glyphColor = .white
        } else {
            glyphColor = accent
        }

        guard let symbol = symbolImage(pointSize: 12.5) else { return }
        let size = symbol.size
        let rect = NSRect(
            x: ((bounds.width - size.width) / 2.0).rounded(),
            y: ((bounds.height - size.height) / 2.0).rounded(),
            width: size.width,
            height: size.height
        )
        let tinted = NSImage(size: size, flipped: false) { r in
            symbol.draw(in: r)
            glyphColor.set()
            r.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
    }
}

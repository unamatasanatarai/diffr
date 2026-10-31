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

    private var trackingArea: NSTrackingArea?
    private var paragraphStyleCache: [CGFloat: NSParagraphStyle] = [:]

    public init(side: EditorSide) {
        self.side = side

        gutterView = LineNumberRulerView(side: side)
        actionMarginView = (side == .left) ? DiffActionMarginView() : nil
        scrollView = NSScrollView()

        textStorage = NSTextStorage()
        layoutManager = InvisibilityLayoutManager()
        textStorage.addLayoutManager(layoutManager)

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

        let trailingAnchorForText = actionMarginView?.leadingAnchor ?? trailingAnchor
        var constraints: [NSLayoutConstraint] = [
            gutterView.topAnchor.constraint(equalTo: topAnchor),
            gutterView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gutterView.bottomAnchor.constraint(equalTo: bottomAnchor),
            gutterView.widthAnchor.constraint(equalToConstant: 80),

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
                marginView.trailingAnchor.constraint(equalTo: trailingAnchor),
                marginView.bottomAnchor.constraint(equalTo: bottomAnchor),
                marginView.widthAnchor.constraint(equalToConstant: 32)
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
        let lineCount = max(rowCount ?? gutterView.rowInfos.count, 1)
        var contentHeight = DiffTheme.editorTextInsetY * 2 + CGFloat(lineCount) * DiffTheme.editorLineHeight

        var usedWidth: CGFloat = 0
        if let container = textView.textContainer {
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container)
            usedWidth = used.width
            // Lines typed since the last diff are not in rowCount yet; never cut them off.
            contentHeight = max(contentHeight, used.maxY + textView.textContainerOrigin.y + DiffTheme.editorTextInsetY)
        }
        let height = max(scrollView.contentView.bounds.height, contentHeight + 80.0)
        let width = max(scrollView.contentView.bounds.width, usedWidth + 80.0)
        return NSSize(width: ceil(width), height: ceil(height))
    }

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
              let hunk = allHunks.first(where: { $0.id == hIdx }) else {
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
        let btnHeight: CGFloat = 24.0
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

        let btnX: CGFloat = (side == .left) ? bounds.width - btnWidth - 4.0 : 4.0

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
    public var text: String {
        get { return textView.string }
        set { replaceText(with: newValue, actionName: nil) }
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
        if textView.shouldChangeText(in: range, replacementString: replacement) {
            textStorage.replaceCharacters(in: range, with: attributed)
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

    public override func draw(_ dirtyRect: NSRect) {
        // Just the arrow glyph with NO background or border, preserving the full clickable bounds
        let arrow: NSString = (title.isEmpty ? "➔" : title) as NSString
        let isDark = (effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)

        let color: NSColor
        let fontSize: CGFloat
        var attrs: [NSAttributedString.Key: Any] = [:]

        if isHovered {
            color = isDark ? NSColor.white : NSColor(red: 3/255, green: 76/255, blue: 161/255, alpha: 1.0)
            fontSize = 16.5
            let shadow = NSShadow()
            shadow.shadowColor = isDark
                ? DiffTheme.hoverArrowColor.withAlphaComponent(0.95)
                : NSColor(red: 9/255, green: 105/255, blue: 218/255, alpha: 0.65)
            shadow.shadowBlurRadius = 5.0
            shadow.shadowOffset = NSSize(width: 0, height: 0)
            attrs[.shadow] = shadow
        } else {
            color = DiffTheme.hoverArrowColor
            fontSize = 14.0
        }

        attrs[.font] = NSFont.systemFont(ofSize: fontSize, weight: .black)
        attrs[.foregroundColor] = color

        let size = arrow.size(withAttributes: attrs)
        let point = NSPoint(
            x: (bounds.width - size.width) / 2.0,
            y: (bounds.height - size.height) / 2.0
        )
        arrow.draw(at: point, withAttributes: attrs)
    }
}

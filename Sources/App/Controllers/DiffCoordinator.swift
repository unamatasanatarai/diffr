import AppKit

public final class DiffCoordinator: NSObject {
    public let leftEditor: DiffEditorView
    public let rightEditor: DiffEditorView

    /// The latest applied diff. Only trust it for edits when `isDiffCurrent` is true.
    public private(set) var diffResult: DiffResult = .empty
    public var onDiffUpdated: ((DiffResult) -> Void)?

    public var leftCleanText: String { return leftEditor.text }
    public var rightCleanText: String { return rightEditor.text }

    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 0.10 // 100ms
    /// Bumped on every text change; a diff is only applied if computed for the current generation.
    private var textGeneration = 0
    private var computedGeneration = -1
    private var isComputingInBackground = false
    private let diffQueue = DispatchQueue(label: "Diffr.diff", qos: .userInitiated)

    public private(set) var activeHunkIndex: Int?
    private var hoveredHunkIndex: Int?

    /// True when `diffResult` reflects exactly what is in both editors right now.
    public var isDiffCurrent: Bool { return computedGeneration == textGeneration }
    public var hasChanges: Bool { return !diffResult.hunks.isEmpty }

    public init(leftEditor: DiffEditorView, rightEditor: DiffEditorView) {
        self.leftEditor = leftEditor
        self.rightEditor = rightEditor
        super.init()
        setupBindings()
    }

    private func setupBindings() {
        for editor in [leftEditor, rightEditor] {
            editor.onTextChange = { [weak self] in
                guard let self = self else { return }
                self.textGeneration &+= 1
                self.syncDocumentSizes()
                self.scheduleDiffRecalculation(immediate: false)
            }
            editor.onHoverRow = { [weak self] row in
                self?.handleHoverAtRow(row)
            }
            editor.onLayout = { [weak self] in
                self?.syncDocumentSizes()
            }
        }

        leftEditor.onMoveHunk = { [weak self] hunkIndex in
            self?.handleHunkMove(hunkIndex: hunkIndex, direction: .leftToRight)
        }
        rightEditor.onMoveHunk = { [weak self] hunkIndex in
            self?.handleHunkMove(hunkIndex: hunkIndex, direction: .rightToLeft)
        }
    }

    // MARK: - Hover & active hunk

    private func handleHoverAtRow(_ row: Int?) {
        guard let r = row, r >= 0 && r < diffResult.alignedRows.count else {
            setHoveredHunkIndex(nil)
            return
        }
        setHoveredHunkIndex(diffResult.alignedRows[r].hunkIndex)
    }

    private func setHoveredHunkIndex(_ index: Int?) {
        hoveredHunkIndex = index
        refreshHunkHighlight()
    }

    /// The hovered hunk wins; otherwise the active (navigated-to) hunk keeps its arrows visible.
    private func refreshHunkHighlight() {
        let shown = hoveredHunkIndex ?? activeHunkIndex
        leftEditor.gutterView.hoveredHunkIndex = shown
        rightEditor.gutterView.hoveredHunkIndex = shown
        leftEditor.setHoveredHunkIndex(shown)
        rightEditor.setHoveredHunkIndex(shown)
    }

    private func handleHunkMove(hunkIndex: Int, direction: MergeDirection) {
        // The arrow was positioned for the last applied diff. If text changed since,
        // the id may now name a different hunk: refresh instead of guessing.
        guard isDiffCurrent else {
            recalculateDiff()
            NSSound.beep()
            return
        }
        if let hunk = diffResult.hunks.first(where: { $0.id == hunkIndex }) {
            copyHunk(hunk, direction: direction)
        }
    }

    // MARK: - Change Navigation & Cursor Placement

    public func jumpToNextHunk() {
        ensureDiffCurrent()
        guard !diffResult.hunks.isEmpty else { return }
        let nextIdx: Int
        if let current = activeHunkIndex, let pos = diffResult.hunks.firstIndex(where: { $0.id == current }) {
            nextIdx = (pos + 1) % diffResult.hunks.count
        } else {
            nextIdx = 0
        }
        selectAndScrollToHunk(diffResult.hunks[nextIdx])
    }

    public func jumpToPreviousHunk() {
        ensureDiffCurrent()
        guard !diffResult.hunks.isEmpty else { return }
        let prevIdx: Int
        if let current = activeHunkIndex, let pos = diffResult.hunks.firstIndex(where: { $0.id == current }) {
            prevIdx = (pos - 1 + diffResult.hunks.count) % diffResult.hunks.count
        } else {
            prevIdx = diffResult.hunks.count - 1
        }
        selectAndScrollToHunk(diffResult.hunks[prevIdx])
    }

    public func selectAndScrollToHunk(_ hunk: DiffHunk) {
        activeHunkIndex = hunk.id
        hoveredHunkIndex = nil
        placeCursorAtHunk(hunk)
        scrollToHunk(hunk)
        refreshHunkHighlight()
    }

    private func placeCursorAtHunk(_ hunk: DiffHunk) {
        leftEditor.textView.setSelectedRange(NSRange(location: characterOffset(forLine: hunk.leftLineRange.lowerBound, in: leftEditor), length: 0))
        rightEditor.textView.setSelectedRange(NSRange(location: characterOffset(forLine: hunk.rightLineRange.lowerBound, in: rightEditor), length: 0))
    }

    /// UTF-16 offset of the start of a 0-based line (same line semantics as the diff model).
    private func characterOffset(forLine targetLine: Int, in editor: DiffEditorView) -> Int {
        let ranges = DiffEngine.lineRanges(in: editor.textStorage.mutableString)
        guard targetLine >= 0 else { return 0 }
        return targetLine < ranges.count ? ranges[targetLine].location : editor.textStorage.length
    }

    private func scrollToHunk(_ hunk: DiffHunk) {
        let rowY = DiffTheme.editorTextInsetY + CGFloat(hunk.alignedRowRange.lowerBound) * DiffTheme.editorLineHeight
        let clip = leftEditor.scrollView.contentView
        let visibleHeight = clip.bounds.height
        let maxY = max(0, leftEditor.textView.frame.height - visibleHeight)
        let targetY = min(max(0, rowY - visibleHeight / 3.0), maxY)
        // The scroll coordinator mirrors this onto the right pane (find-bar aware).
        clip.scroll(to: NSPoint(x: 0, y: targetY))
        leftEditor.scrollView.reflectScrolledClipView(clip)
    }

    // MARK: - Diff computation

    public func setInitialTexts(left: String, right: String) {
        leftEditor.text = left
        rightEditor.text = right
        recalculateDiff()
    }

    public func scheduleDiffRecalculation(immediate: Bool = false) {
        debounceTimer?.invalidate()
        debounceTimer = nil
        if immediate {
            recalculateDiff()
            return
        }
        let timer = Timer(timeInterval: debounceInterval, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.debounceTimer = nil
            self.startBackgroundDiff()
        }
        // .common so the diff keeps updating during scroll/drag tracking.
        RunLoop.main.add(timer, forMode: .common)
        debounceTimer = timer
    }

    /// Computes the diff off the main thread; the result is dropped if the text changed meanwhile.
    private func startBackgroundDiff() {
        guard !isDiffCurrent, !isComputingInBackground else { return }
        isComputingInBackground = true

        let generation = textGeneration
        var left = leftEditor.text
        var right = rightEditor.text
        left.makeContiguousUTF8()
        right.makeContiguousUTF8()

        diffQueue.async { [weak self] in
            let result = DiffEngine.computeDiff(leftText: left, rightText: right, includeWordDiff: true)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isComputingInBackground = false
                if generation == self.textGeneration {
                    if !self.isDiffCurrent {
                        self.apply(result, generation: generation)
                    }
                } else if self.debounceTimer == nil {
                    self.startBackgroundDiff()
                }
            }
        }
    }

    /// Synchronously brings the diff up to date (used before any action that edits by hunk).
    public func ensureDiffCurrent() {
        if !isDiffCurrent {
            recalculateDiff()
        }
    }

    public func recalculateDiff() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        let generation = textGeneration
        let result = DiffEngine.computeDiff(
            leftText: leftEditor.text,
            rightText: rightEditor.text,
            includeWordDiff: true
        )
        apply(result, generation: generation)
    }

    private func apply(_ result: DiffResult, generation: Int) {
        diffResult = result
        computedGeneration = generation
        if let active = activeHunkIndex, !result.hunks.contains(where: { $0.id == active }) {
            activeHunkIndex = nil
        }

        let leftLineRanges = DiffEngine.lineRanges(in: leftEditor.textStorage.mutableString)
        let rightLineRanges = DiffEngine.lineRanges(in: rightEditor.textStorage.mutableString)

        // Align real lines via paragraph spacing without modifying the actual text
        applyParagraphSpacings(to: leftEditor, side: .left, alignedRows: result.alignedRows, lineRanges: leftLineRanges)
        applyParagraphSpacings(to: rightEditor, side: .right, alignedRows: result.alignedRows, lineRanges: rightLineRanges)

        let rowCount = result.alignedRows.count
        var leftKinds: [DiffLineKind] = []
        var rightKinds: [DiffLineKind] = []
        var leftCharRanges: [NSRange] = []
        var rightCharRanges: [NSRange] = []
        var leftWordMap: [Int: [WordHighlightSpan]] = [:]
        var rightWordMap: [Int: [WordHighlightSpan]] = [:]
        var leftRowInfos: [RulerRowInfo] = []
        var rightRowInfos: [RulerRowInfo] = []
        leftKinds.reserveCapacity(rowCount)
        rightKinds.reserveCapacity(rowCount)
        leftCharRanges.reserveCapacity(rowCount)
        rightCharRanges.reserveCapacity(rowCount)
        leftRowInfos.reserveCapacity(rowCount)
        rightRowInfos.reserveCapacity(rowCount)

        let notFound = NSRange(location: NSNotFound, length: 0)
        var leftRealLineIdx = 0
        var rightRealLineIdx = 0

        for (rowIdx, row) in result.alignedRows.enumerated() {
            leftKinds.append(row.leftKind)
            rightKinds.append(row.rightKind)

            if row.leftKind != .spacer {
                leftCharRanges.append(leftRealLineIdx < leftLineRanges.count ? leftLineRanges[leftRealLineIdx] : notFound)
                if !row.leftWordHighlights.isEmpty {
                    leftWordMap[rowIdx] = row.leftWordHighlights
                }
                leftRealLineIdx += 1
            } else {
                leftCharRanges.append(notFound)
            }

            if row.rightKind != .spacer {
                rightCharRanges.append(rightRealLineIdx < rightLineRanges.count ? rightLineRanges[rightRealLineIdx] : notFound)
                if !row.rightWordHighlights.isEmpty {
                    rightWordMap[rowIdx] = row.rightWordHighlights
                }
                rightRealLineIdx += 1
            } else {
                rightCharRanges.append(notFound)
            }

            leftRowInfos.append(RulerRowInfo(lineNumber: row.leftLineNumber, kind: row.leftKind, hunkIndex: row.hunkIndex))
            rightRowInfos.append(RulerRowInfo(lineNumber: row.rightLineNumber, kind: row.rightKind, hunkIndex: row.hunkIndex))
        }

        leftEditor.layoutManager.lineKinds = leftKinds
        leftEditor.layoutManager.lineCharacterRanges = leftCharRanges
        leftEditor.layoutManager.lineWordHighlights = leftWordMap

        rightEditor.layoutManager.lineKinds = rightKinds
        rightEditor.layoutManager.lineCharacterRanges = rightCharRanges
        rightEditor.layoutManager.lineWordHighlights = rightWordMap

        leftEditor.gutterView.rowInfos = leftRowInfos
        leftEditor.actionMarginView?.rowInfos = leftRowInfos
        rightEditor.gutterView.rowInfos = rightRowInfos

        syncDocumentSizes()

        leftEditor.textView.needsDisplay = true
        rightEditor.textView.needsDisplay = true

        leftEditor.allHunks = result.hunks
        rightEditor.allHunks = result.hunks
        refreshHunkHighlight()

        onDiffUpdated?(result)
    }

    /// Gives both documents the same size so vertical and horizontal scrolling stay in lockstep.
    public func syncDocumentSizes() {
        let rows = diffResult.alignedRows.count
        let leftSize = leftEditor.naturalDocumentSize(rowCount: rows)
        let rightSize = rightEditor.naturalDocumentSize(rowCount: rows)
        let common = NSSize(width: max(leftSize.width, rightSize.width), height: max(leftSize.height, rightSize.height))
        leftEditor.setDocumentSize(common)
        rightEditor.setDocumentSize(common)
    }

    /// Inserts spacer gaps above lines via `paragraphSpacingBefore`. Only lines whose spacing
    /// actually changed are touched, so typing in a large file does not re-layout the whole document.
    private func applyParagraphSpacings(
        to editor: DiffEditorView,
        side: EditorSide,
        alignedRows: [AlignedDiffRow],
        lineRanges: [NSRange]
    ) {
        let storage = editor.textStorage
        guard storage.length > 0 else {
            editor.setLeadingSpacerRows(0)
            return
        }

        var spacersBeforeLine: [Int] = []
        spacersBeforeLine.reserveCapacity(lineRanges.count)
        var pendingSpacers = 0
        for row in alignedRows {
            let kind = (side == .left) ? row.leftKind : row.rightKind
            if kind == .spacer {
                pendingSpacers += 1
            } else {
                spacersBeforeLine.append(pendingSpacers)
                pendingSpacers = 0
            }
        }

        // TextKit ignores spacing before the first paragraph: offset it via the container inset.
        editor.setLeadingSpacerRows(spacersBeforeLine.first ?? 0)

        let lineHeight = DiffTheme.editorLineHeight
        var isEditing = false
        for (i, range) in lineRanges.enumerated() where range.length > 0 {
            let spacers = (i > 0 && i < spacersBeforeLine.count) ? spacersBeforeLine[i] : 0
            let wanted = CGFloat(spacers) * lineHeight
            if let current = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle,
               current.paragraphSpacingBefore == wanted,
               current.minimumLineHeight == lineHeight,
               current.maximumLineHeight == lineHeight {
                continue
            }
            if !isEditing {
                storage.beginEditing()
                isEditing = true
            }
            storage.addAttribute(.paragraphStyle, value: editor.makeEditorParagraphStyle(spacingBefore: wanted), range: range)
        }
        if isEditing {
            storage.endEditing()
        }
    }

    // MARK: - Copying changes

    private func targetEditor(for direction: MergeDirection) -> DiffEditorView {
        return direction == .leftToRight ? rightEditor : leftEditor
    }

    public func copyAll(direction: MergeDirection) {
        let source = direction == .leftToRight ? leftEditor : rightEditor
        let name = direction == .leftToRight ? "Copy All to Right" : "Copy All to Left"
        targetEditor(for: direction).replaceText(with: source.text, actionName: name)
        recalculateDiff()
    }

    public func copyHunk(_ hunk: DiffHunk, direction: MergeDirection) {
        ensureDiffCurrent()
        // Only act on a hunk that is part of the diff of the text as it is right now.
        guard let current = diffResult.hunks.first(where: { $0.id == hunk.id }), current == hunk else {
            NSSound.beep()
            return
        }

        let outcome = DiffEngine.applyHunk(
            current,
            leftText: leftEditor.text,
            rightText: rightEditor.text,
            direction: direction
        )
        let name = direction == .leftToRight ? "Copy Change to Right" : "Copy Change to Left"
        switch direction {
        case .leftToRight:
            rightEditor.replaceText(with: outcome.newRightText, actionName: name)
        case .rightToLeft:
            leftEditor.replaceText(with: outcome.newLeftText, actionName: name)
        }
        recalculateDiff()
    }

    /// Keyboard/menu variant: copies the active hunk (or the one at the cursor), then moves on to the next.
    public func copyCurrentHunk(direction: MergeDirection, focusedEditor: DiffEditorView?) {
        ensureDiffCurrent()
        guard let hunk = hunkForCommand(focusedEditor: focusedEditor),
              let position = diffResult.hunks.firstIndex(of: hunk) else {
            NSSound.beep()
            return
        }
        copyHunk(hunk, direction: direction)
        if diffResult.hunks.isEmpty {
            activeHunkIndex = nil
            refreshHunkHighlight()
        } else {
            selectAndScrollToHunk(diffResult.hunks[min(position, diffResult.hunks.count - 1)])
        }
    }

    private func hunkForCommand(focusedEditor: DiffEditorView?) -> DiffHunk? {
        if let active = activeHunkIndex, let hunk = diffResult.hunks.first(where: { $0.id == active }) {
            return hunk
        }
        guard let editor = focusedEditor else { return nil }
        let caret = editor.textView.selectedRange().location
        let ranges = DiffEngine.lineRanges(in: editor.textStorage.mutableString)
        var line = ranges.count
        for (idx, range) in ranges.enumerated() where caret < NSMaxRange(range) || (caret == NSMaxRange(range) && idx == ranges.count - 1) {
            line = idx
            break
        }
        let isLeft = (editor === leftEditor)
        return diffResult.hunks.first { hunk in
            let range = isLeft ? hunk.leftLineRange : hunk.rightLineRange
            return range.contains(line) || (range.isEmpty && range.lowerBound == line)
        }
    }

    public func clearAll() {
        let undoManager = leftEditor.textView.undoManager
        undoManager?.beginUndoGrouping()
        leftEditor.replaceText(with: "", actionName: nil)
        rightEditor.replaceText(with: "", actionName: nil)
        undoManager?.setActionName("Clear")
        undoManager?.endUndoGrouping()
        activeHunkIndex = nil
        hoveredHunkIndex = nil
        recalculateDiff()
    }

    /// Replaces one pane's contents (e.g. from an opened file) as a single undoable step.
    public func loadText(_ text: String, into side: EditorSide) {
        let editor = (side == .left) ? leftEditor : rightEditor
        editor.replaceText(with: text, actionName: "Open File")
        activeHunkIndex = nil
        recalculateDiff()
    }

    public func setShowsInvisibles(_ shows: Bool) {
        leftEditor.layoutManager.showsInvisibles = shows
        rightEditor.layoutManager.showsInvisibles = shows
    }
}

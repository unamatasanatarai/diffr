import AppKit

public enum DiffEngineTests {
    public static func run(testRunner: (String, () throws -> Void) -> Void) {
        testRunner("DiffEngine detects identical text files") {
            let left = "line 1\nline 2\nline 3"
            let right = "line 1\nline 2\nline 3"
            let result = DiffEngine.computeDiff(leftText: left, rightText: right)

            try expect(result.isIdentical, "Files should be identical")
            try expect(result.hunks.isEmpty, "There should be no hunks")
            try expect(result.additionsCount == 0, "No additions")
            try expect(result.deletionsCount == 0, "No deletions")
            try expect(result.alignedRows.count == 3, "Should have 3 aligned rows")
            for row in result.alignedRows {
                try expect(row.leftKind == .unchanged)
                try expect(row.rightKind == .unchanged)
            }
        }

        testRunner("DiffEngine detects pure line additions on right") {
            let left = "line 1\nline 2"
            let right = "line 1\nline added\nline 2"
            let result = DiffEngine.computeDiff(leftText: left, rightText: right)

            try expect(!result.isIdentical, "Files should not be identical")
            try expect(result.hunks.count == 1, "Should have 1 hunk")
            let hunk = result.hunks[0]
            try expect(hunk.kind == .addition, "Hunk should be addition")
            try expect(hunk.rightLines == ["line added"])
            try expect(result.additionsCount == 1)
            try expect(result.deletionsCount == 0)

            // Verify spacer row on left
            let spacerRows = result.alignedRows.filter { $0.leftKind == .spacer }
            try expect(spacerRows.count == 1, "Left should have 1 spacer row")
            try expect(spacerRows[0].rightKind == .addition)
            try expect(spacerRows[0].rightText == "line added")
        }

        testRunner("DiffEngine detects pure line deletions on left") {
            let left = "alpha\nbeta\ngamma"
            let right = "alpha\ngamma"
            let result = DiffEngine.computeDiff(leftText: left, rightText: right)

            try expect(!result.isIdentical)
            try expect(result.hunks.count == 1)
            let hunk = result.hunks[0]
            try expect(hunk.kind == .deletion)
            try expect(hunk.leftLines == ["beta"])
            try expect(result.deletionsCount == 1)
            try expect(result.additionsCount == 0)

            // Verify spacer row on right
            let spacerRows = result.alignedRows.filter { $0.rightKind == .spacer }
            try expect(spacerRows.count == 1, "Right should have 1 spacer row")
            try expect(spacerRows[0].leftKind == .deletion)
            try expect(spacerRows[0].leftText == "beta")
        }

        testRunner("DiffEngine detects modified line and computes intra-line highlights") {
            let left = "let config = \"old_value\""
            let right = "let config = \"new_value\""
            let result = DiffEngine.computeDiff(leftText: left, rightText: right)

            try expect(!result.isIdentical)
            try expect(result.hunks.count == 1)
            try expect(result.hunks[0].kind == .modification)
            try expect(result.alignedRows.count == 1)

            let row = result.alignedRows[0]
            try expect(row.leftKind == .deletion)
            try expect(row.rightKind == .addition)
            try expect(!row.leftWordHighlights.isEmpty, "Left should have intra-line word highlight")
            try expect(!row.rightWordHighlights.isEmpty, "Right should have intra-line word highlight")
        }

        testRunner("DiffEngine handles completely empty inputs") {
            let resultEmpty = DiffEngine.computeDiff(leftText: "", rightText: "")
            try expect(resultEmpty.isIdentical)
            try expect(resultEmpty.hunks.isEmpty)
        }

        testRunner("DiffEngine correctly identifies identical texts with multiple empty lines") {
            let textWithEmptyLines = "Usage:\n  cmd\n\nArguments:\n  v\n\nOptions:\n  -h\n"
            let result = DiffEngine.computeDiff(leftText: textWithEmptyLines, rightText: textWithEmptyLines)
            try expect(result.isIdentical, "Must be identical")
            try expect(result.hunks.isEmpty, "Must have no hunks")
            try expect(result.additionsCount == 0)
            try expect(result.deletionsCount == 0)
        }

        testRunner("DiffCoordinator handles pasting identical text with empty lines into left then right") {
            let leftEditor = DiffEditorView(side: .left)
            let rightEditor = DiffEditorView(side: .right)
            let coord = DiffCoordinator(leftEditor: leftEditor, rightEditor: rightEditor)

            let sample = """
            Usage:
              ggrel <version> [options]

            Arguments:
              <version>             Target version (e.g. 1.0.1 or v1.0.1).

            Release Notes Options (Required):
              -f, --notes-file FILE  Read release notes from FILE (use "-" for stdin).

            Execution Modes:
              -n, --dry-run, --preview
            """

            // Paste on left first
            leftEditor.text = sample
            leftEditor.onTextChange?()
            coord.scheduleDiffRecalculation(immediate: true)

            try expect(!coord.diffResult.isIdentical)
            try expect(coord.diffResult.deletionsCount > 0)

            // Paste identical text on right
            rightEditor.text = sample
            rightEditor.onTextChange?()
            coord.scheduleDiffRecalculation(immediate: true)

            try expect(coord.diffResult.isIdentical, "Files must be identical after pasting same text on right")
            try expect(coord.diffResult.hunks.isEmpty, "Hunks must be empty")
            try expect(coord.diffResult.additionsCount == 0)
            try expect(coord.diffResult.deletionsCount == 0)
            try expect(coord.leftCleanText == coord.rightCleanText)
        }

        testRunner("Hunk action button appears on right edge of Left pane on hover") {
            let leftEditor = DiffEditorView(side: .left)
            leftEditor.frame = NSRect(x: 0, y: 0, width: 400, height: 600)
            let rightEditor = DiffEditorView(side: .right)
            rightEditor.frame = NSRect(x: 0, y: 0, width: 400, height: 600)
            let coord = DiffCoordinator(leftEditor: leftEditor, rightEditor: rightEditor)

            coord.setInitialTexts(left: "Line A\nLine B\n", right: "Line B\n")
            try expect(!coord.diffResult.hunks.isEmpty)

            let hunk = coord.diffResult.hunks[0]

            // Hover over hunk row on left
            coord.leftEditor.onHoverRow?(0)

            try expect(leftEditor.hunkActionButtonHunkId == hunk.id)
            try expect(leftEditor.hunkActionButton.alphaValue == 1.0)
            try expect(leftEditor.hunkActionButton.title == "➔")
            // Position must be at the right edge of left pane
            let expectedMinX = leftEditor.bounds.width - 32.0 - 4.0
            try expect(leftEditor.hunkActionButton.frame.origin.x >= expectedMinX, "Action button must be on right edge of left pane")

            // Simulate clicking the action button
            var movedHunkId: Int?
            leftEditor.onMoveHunk = { hunkId in
                movedHunkId = hunkId
            }
            leftEditor.hunkActionButton.performClick(nil)
            let moved = (movedHunkId == hunk.id)
            try expect(moved, "Clicking action button must trigger hunk move")
        }

        testRunner("Right pane action button appears at the middle separator on hover and moves right-to-left") {
            let leftEditor = DiffEditorView(side: .left)
            leftEditor.frame = NSRect(x: 0, y: 0, width: 400, height: 600)
            let rightEditor = DiffEditorView(side: .right)
            rightEditor.frame = NSRect(x: 0, y: 0, width: 400, height: 600)
            let coord = DiffCoordinator(leftEditor: leftEditor, rightEditor: rightEditor)

            coord.setInitialTexts(left: "Line 1\nLine 3\n", right: "Line 1\nLine 2 Added\nLine 3\n")
            try expect(!coord.diffResult.hunks.isEmpty)
            let hunk = coord.diffResult.hunks[0]

            // Hover over hunk row on right (row 1 is addition)
            coord.rightEditor.onHoverRow?(1)

            try expect(rightEditor.hunkActionButtonHunkId == hunk.id)
            try expect(rightEditor.hunkActionButton.alphaValue == 1.0)
            try expect(rightEditor.hunkActionButton.title == "⬅")
            // Must be placed at the middle separator (at btnX = 4.0)
            try expect(rightEditor.hunkActionButton.frame.origin.x == 4.0, "Right action button must be at the middle separator")

            // Simulate clicking the action button
            var movedHunkId: Int?
            rightEditor.onMoveHunk = { hunkId in
                movedHunkId = hunkId
            }
            rightEditor.hunkActionButton.performClick(nil)
            let moved = (movedHunkId == hunk.id)
            try expect(moved, "Clicking right action button must trigger right-to-left hunk move")
        }

        testRunner("Next Change and Previous Change jump between hunks and place cursor") {
            let leftEditor = DiffEditorView(side: .left)
            leftEditor.frame = NSRect(x: 0, y: 0, width: 400, height: 600)
            let rightEditor = DiffEditorView(side: .right)
            rightEditor.frame = NSRect(x: 0, y: 0, width: 400, height: 600)
            let coord = DiffCoordinator(leftEditor: leftEditor, rightEditor: rightEditor)

            let sampleLeft = "Top\nChange1 Left\nMiddle\nChange2 Left\nBottom\n"
            let sampleRight = "Top\nChange1 Right\nMiddle\nChange2 Right\nBottom\n"

            coord.setInitialTexts(left: sampleLeft, right: sampleRight)
            try expect(coord.diffResult.hunks.count == 2)

            // Initially activeHunkIndex is nil
            try expect(coord.activeHunkIndex == nil)

            // Jump next -> hunk 0 (Change1)
            coord.jumpToNextHunk()
            try expect(coord.activeHunkIndex == coord.diffResult.hunks[0].id)
            // Cursor in leftEditor and rightEditor should be at line 1
            try expect(leftEditor.textView.selectedRange().location == 4) // "Top\n" = 4 chars
            try expect(rightEditor.textView.selectedRange().location == 4)

            // Jump next -> hunk 1 (Change2)
            coord.jumpToNextHunk()
            try expect(coord.activeHunkIndex == coord.diffResult.hunks[1].id)
            let expectedCharOffset = "Top\nChange1 Left\nMiddle\n".count
            try expect(leftEditor.textView.selectedRange().location == expectedCharOffset)

            // Jump previous -> hunk 0
            coord.jumpToPreviousHunk()
            try expect(coord.activeHunkIndex == coord.diffResult.hunks[0].id)
            try expect(leftEditor.textView.selectedRange().location == 4)
        }

        testRunner("Left pane has dedicated 32pt text-free seam margin with arrow cursor") {
            let leftEditor = DiffEditorView(side: .left)
            leftEditor.frame = NSRect(x: 0, y: 0, width: 400, height: 600)
            leftEditor.layoutSubtreeIfNeeded()

            try expect(leftEditor.actionMarginView != nil, "Left pane must have actionMarginView")
            guard let marginView = leftEditor.actionMarginView else { return }
            try expect(marginView.frame.width == 32.0, "Margin view width must be 32pt")
            try expect(marginView.frame.origin.x == 368.0, "Margin view must sit on trailing edge")
            try expect(leftEditor.scrollView.frame.maxX <= marginView.frame.minX, "Text scrollView must not enter action margin")

            // Test cursor update
            marginView.cursorUpdate(with: NSEvent())
            leftEditor.hunkActionButton.cursorUpdate(with: NSEvent())
        }
    }
}
